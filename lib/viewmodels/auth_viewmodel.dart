// lib/viewmodels/auth_viewmodel.dart
import 'package:basa_capstone/core/data/remote/login_log_repository_supabase.dart';
import 'package:supabase/supabase.dart' hide User;
import '../core/console/logger.dart';
import '../core/models/user.dart';
import '../core/models/login_log.dart';
import '../core/models/login_method.dart';
import '../core/repositories/user_repository.dart';
import '../core/repositories/login_log_repository.dart';
import '../core/data/remote/supabase_config.dart';
import '../core/release.dart';
import '../core/repositories/migration_ledger_repository.dart';
import '../core/services/version_check.dart';
import '../core/services/version_check.dart' as rule show checkVersion;
import 'dart:convert';
import 'dart:math';
import '../core/models/offline_credential.dart';
import '../core/models/report_setting.dart';
import '../core/repositories/offline_credential_repository.dart';
import '../core/repositories/report_setting_repository.dart';
import '../core/services/offline_signin_rules.dart';
import '../core/services/pbkdf2.dart';
import '../core/services/auth_messages.dart';


/// ViewModel for Authentication
/// You will find methods related to authentication here

class AuthViewModel {
  final ScopedLogger _log;
  final LoginLogRepository _loginLogRepo;
  final SupabaseConfigStore _config;
  final UserRepository Function(SupabaseClient client) _userRepoFactory;
  final MigrationLedgerRepository Function(SupabaseClient client) _ledgerRepoFactory;
  final OfflineCredentialRepository _credentials;
  final UserRepository _localUsers;
  final ReportSettingRepository _localReportSettings;

  SupabaseClient? _client;
  User? currentUser;
  bool mustChangePassword = false;
  bool _offline = false;

  /// Set when the last sign-in succeeded but the database has additions this
  /// app doesn't know (version check verdict warn); null otherwise.
  String? versionWarning;

  /// Set when the last online sign-in or password change succeeded but the
  /// offline credential could not be saved on this device; null otherwise.
  String? offlineWarning;

  AuthViewModel({
    required LoginLogRepository loginLogRepo,
    required SupabaseConfigStore config,
    required UserRepository Function(SupabaseClient client) userRepoFactory,
    required MigrationLedgerRepository Function(SupabaseClient client) ledgerRepoFactory,
    required OfflineCredentialRepository credentials,
    required UserRepository localUsers,
    required ReportSettingRepository localReportSettings,
    Logger? logger,
  })  : _loginLogRepo = loginLogRepo,
        _config = config,
        _userRepoFactory = userRepoFactory,
        _ledgerRepoFactory = ledgerRepoFactory,
        _credentials = credentials,
        _localUsers = localUsers,
        _localReportSettings = localReportSettings,
        _log = ScopedLogger(logger, 'AuthViewModel');

  /// Signed in online or offline. Offline sessions have no [client].
  bool get isSignedIn => currentUser != null && (_client != null || _offline);

  /// Signed in offline (local-copy work only, no server).
  bool get isOffline => _offline && currentUser != null;
  SupabaseClient? get client => _client; // exposed so user-create etc. can reuse the active session

  Future<String?> signIn({
    required String target,
    required String email,
    required String password,
  }) async {
    _log('signIn(target: $target, email: "$email")');
    versionWarning = null;
    offlineWarning = null;
    final profile = switch (target) {
      'cloud' => _config.cloud,
      'lan' => _config.lan,
      _ => null,
    };
    if (profile == null) return 'Invalid target: "$target" (expected cloud or lan)';
    if (profile.url.isEmpty) return '$target.url not set.';

    final client = SupabaseClient(profile.url, profile.anonKey);
    var kept = false; // the client became the session
    try {
      final res = await client.auth.signInWithPassword(email: email, password: password);
      final authUser = res.user;
      if (authUser == null) {
        await _recordAttempt(email, success: false, failureReason: 'no user returned', client: client);
        return 'Sign-in failed: no user returned';
      }

      final userRepo = _userRepoFactory(client);
      final profileRow = await userRepo.getById(authUser.id);
      if (profileRow == null) {
        await _recordAttempt(email, success: false, userId: authUser.id,
            failureReason: 'no matching profile row', client: client);
        await _revokeOffline(authUser.id);
        await _abandon(client);
        return 'Sign-in failed: account has no profile row (contact admin)';
      }
      if (!profileRow.isActive) {
        await _recordAttempt(email, success: false, userId: authUser.id,
            failureReason: 'account inactive', client: client);
        await _revokeOffline(authUser.id);
        await _abandon(client);
        return 'Sign-in failed: account is inactive';
      }

      // Version check (rule A). Runs before the session is kept, so a refusal
      // leaves any earlier session untouched. Fails closed.
      final VersionCheck check;
      try {
        check = await checkVersion(client);
      } catch (e) {
        await _recordAttempt(email, success: false, userId: authUser.id,
            failureReason: fetchFailedReason, client: client);
        await _abandon(client);
        return fetchFailedMessage(e);
      }
      if (check.blocks) {
        await _recordAttempt(email, success: false, userId: authUser.id,
            failureReason: versionFailureReason(check), client: client);
        await _revokeOffline(authUser.id); // this build must not keep working offline
        await _abandon(client);
        return versionMessage(check);
      }

      // Replacing an existing session: end the old one so its refresh token dies.
      final previous = _client;
      if (previous != null && previous != client) await _abandon(previous);

      _client = client;
      kept = true;
      _offline = false;
      currentUser = profileRow;
      mustChangePassword = authUser.userMetadata?['must_change_password'] == true;
      if (check.verdict == VersionVerdict.warn) versionWarning = versionMessage(check);

      await _recordAttempt(email, success: true, userId: authUser.id, client: client);
      // A pending password change (e.g. an admin reset) saves the credential
      // only after change-password; until then the old password must not
      // work offline either.
      if (mustChangePassword) {
        await _revokeOffline(profileRow.id);
      } else {
        await _saveOfflineCredential(profileRow, password);
      }
      return null; // null return = success
    } catch (e) {
      await _recordAttempt(email, success: false, failureReason: e.toString(), client: client);
      _log('sign-in failed: $e');
      // A failure after authenticating (e.g. reading the profile row) must
      // not leave a signed-in client behind (L1).
      if (!kept) await _abandon(client);
      return 'Sign-in failed: ${authFailureMessage(e)}';
    }
  }

  /// Signs a client out without touching the current session state.
  /// Used for clients that authenticated but must not be kept.
  Future<void> _abandon(SupabaseClient client) async {
    try {
      await client.auth.signOut();
    } catch (e) {
      _log('sign-out of abandoned client failed (non-fatal): $e');
    }
  }

  Future<void> signOut() async {
    _log('signOut()');
    await _client?.auth.signOut();
    _client = null;
    _offline = false;
    currentUser = null;
    mustChangePassword = false;
    versionWarning = null;
    offlineWarning = null;
  }

  // ---- Offline sign-in (sync spec section 6) ----

  /// Signs the device owner in without a connection, against the credential
  /// saved at their last online sign-in. Null = success. The session has no
  /// [client]: only work on this device's copy is possible.
  Future<String?> signInOffline({required String email, required String password}) async {
    _log('signInOffline(email: "$email")');
    final stored = await _credentials.get();
    final user = stored == null ? null : await _localUsers.getById(stored.userId);
    final windowDays = await offlineWindowDays(user?.schoolId);
    var matches = false;
    if (stored != null) {
      final hash = await pbkdf2HmacSha256InIsolate(utf8.encode(password), fromHex(stored.salt), stored.iterations);
      matches = constantTimeEquals(hash, fromHex(stored.hash));
    }
    final refusal = offlineSignInRefusal(
      stored: stored,
      email: email,
      passwordMatches: matches,
      dataOwnerId: await _credentials.dataOwnerId(),
      localUserActive: user?.isActive,
      windowDays: windowDays,
      now: DateTime.now().toUtc(),
    );
    final ownerEmail = stored != null && email.trim().toLowerCase() == stored.email.trim().toLowerCase();
    if (refusal == OfflineRefusal.wrongEmailOrPassword && ownerEmail) {
      await _credentials.recordFailure(stored.userId);
    }
    await _recordAttempt(email,
        success: refusal == null,
        userId: ownerEmail ? stored.userId : null,
        failureReason: refusal?.name,
        method: LoginMethod.offline);
    if (refusal != null) return offlineRefusalMessage(refusal, windowDays: windowDays);

    final previous = _client;
    if (previous != null) await _abandon(previous);
    _client = null;
    _offline = true;
    currentUser = user;
    mustChangePassword = false;
    versionWarning = null;
    offlineWarning = null;
    return null;
  }

  /// The saved offline credential, if any (for a status line; holds no password).
  Future<OfflineCredential?> offlineCredential() => _credentials.get();

  /// The local users row of the saved credential's owner, or null.
  Future<User?> offlineCredentialUser() async {
    final c = await _credentials.get();
    return c == null ? null : _localUsers.getById(c.userId);
  }

  /// Offline window in days for a user of [schoolId] (null = superadmin):
  /// the school's report setting, else the region's, else 14.
  Future<int> offlineWindowDays(int? schoolId) async {
    final region = await _localReportSettings.getRegion();
    final school = schoolId == null ? null : await _localReportSettings.getForSchool(schoolId);
    return ReportSettings.fromMap({...?region?.settings, ...?school?.settings}).offlineSigninDays;
  }

  /// Drops [userId]'s offline credential (the server refused or reset the
  /// account). A failure is logged only: the online refusal stands either way.
  Future<void> _revokeOffline(String userId) async {
    try {
      await _credentials.revoke(userId);
    } catch (e) {
      _log('offline credential revoke failed (non-fatal): ${e.runtimeType}');
    }
  }

  /// Replaces the device's offline credential with [user] + [password]
  /// (fresh salt, failed attempts 0). A failure keeps the online session and
  /// sets [offlineWarning].
  Future<void> _saveOfflineCredential(User user, String password) async {
    try {
      final rnd = Random.secure();
      final salt = List<int>.generate(16, (_) => rnd.nextInt(256));
      await _credentials.save(OfflineCredential(
        userId: user.id,
        email: user.email,
        salt: toHex(salt),
        iterations: offlineHashIterations,
        hash: toHex(await pbkdf2HmacSha256InIsolate(utf8.encode(password), salt, offlineHashIterations)),
        lastOnlineAt: DateTime.now().toUtc().toIso8601String(),
      ));
    } catch (e) {
      _log('offline credential save failed (non-fatal): $e');
      offlineWarning = 'Offline sign-in was not saved on this device: $e';
    }
  }

  /// Compares this build's migrations (lib/core/release.dart) with the
  /// server's basa_migrations ledger. Defaults to the session's client.
  /// A missing ledger table gives verdict noLedger; any other fetch error is
  /// rethrown (sign-in treats it as a refusal).
  Future<VersionCheck> checkVersion([SupabaseClient? client]) async {
    final c = client ?? _client;
    if (c == null) throw StateError('Not signed in.');
    try {
      return rule.checkVersion(basaMigrations, await _ledgerRepoFactory(c).fetchAll());
    } on PostgrestException catch (e) {
      // PGRST205: table not in PostgREST's schema cache; 42P01: undefined table.
      if (e.code == 'PGRST205' || e.code == '42P01') return rule.checkVersion(basaMigrations, null);
      rethrow;
    }
  }

  Future<String?> changePassword(String newPassword) async {
    _log('changePassword()');
    final sessionError = requireOnlineSession(allowPendingPasswordChange: true);
    if (sessionError != null) return sessionError;
    final client = _client!;
    offlineWarning = null;
    try {
      await client.auth.updateUser(UserAttributes(
        password: newPassword,
        data: {'must_change_password': false},
      ));
      mustChangePassword = false;
      await _saveOfflineCredential(currentUser!, newPassword);
      return null;
    } catch (e) {
      _log('password change failed: $e');
      return 'Password change failed: ${authFailureMessage(e)}';
    }
  }


  Future<void> _recordAttempt(
    String email, {
    required bool success,
    String? userId, // the account this attempt resolved to; null if it never did
    String? failureReason,
    SupabaseClient? client,
    LoginMethod method = LoginMethod.online,
  }) async {
    final entry = LoginLog(
      emailAttempted: email,
      userId: userId,
      success: success,
      method: method,
      timestamp: DateTime.now(),
      failureReason: failureReason,
    );

    await _loginLogRepo.log(entry); // local — always, non-negotiable

    if (client != null) {
      try {
        await LoginLogRepositorySupabase(client).log(entry);
      } catch (e) {
        _log('cloud login-log write failed (non-fatal): $e');
      }
    }
  }

  String? requireActiveSession() {
    if (!isSignedIn) return notSignedInMessage;
    if (mustChangePassword) return mustChangePasswordMessage;
    return null;
  }

  /// Like [requireActiveSession], but also needs a live server session
  /// (anything that reads or writes the server: admin/content writes,
  /// imports, pull, sync, user management, version check). Guard every
  /// [client]`!` with this, never with [requireActiveSession] alone.
  String? requireOnlineSession({bool allowPendingPasswordChange = false}) {
    if (!isSignedIn) return notSignedInMessage;
    if (_client == null) return needsOnlineSignInMessage;
    if (allowPendingPasswordChange) return null;
    return requireActiveSession();
  }
}