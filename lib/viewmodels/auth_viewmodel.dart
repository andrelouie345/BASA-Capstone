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


/// ViewModel for Authentication
/// You will find methods related to authentication here

class AuthViewModel {
  final ScopedLogger _log;
  final LoginLogRepository _loginLogRepo;
  final SupabaseConfigStore _config;
  final UserRepository Function(SupabaseClient client) _userRepoFactory;

  SupabaseClient? _client;
  User? currentUser;
  bool mustChangePassword = false;

  AuthViewModel({
    required LoginLogRepository loginLogRepo,
    required SupabaseConfigStore config,
    required UserRepository Function(SupabaseClient client) userRepoFactory,
    Logger? logger,
  })  : _loginLogRepo = loginLogRepo,
        _config = config,
        _userRepoFactory = userRepoFactory,
        _log = ScopedLogger(logger, 'AuthViewModel');

  bool get isSignedIn => _client != null && currentUser != null;
  SupabaseClient? get client => _client; // exposed so user-create etc. can reuse the active session

  Future<String?> signIn({
    required String target,
    required String email,
    required String password,
  }) async {
    _log('signIn(target: $target, email: "$email")');
    final profile = switch (target) {
      'cloud' => _config.cloud,
      'lan' => _config.lan,
      _ => null,
    };
    if (profile == null) return 'Invalid target: "$target" (expected cloud or lan)';
    if (profile.url.isEmpty) return '$target.url not set.';

    final client = SupabaseClient(profile.url, profile.anonKey);
    try {
      final res = await client.auth.signInWithPassword(email: email, password: password);
      final authUser = res.user;
      if (authUser == null) {
        await _recordAttempt(email, success: false, failureReason: 'no user returned', client: client );
        return 'Sign-in failed: no user returned';
      }

      final userRepo = _userRepoFactory(client);
      final profileRow = await userRepo.getById(authUser.id);
      if (profileRow == null) {
        await _recordAttempt(email, success: false, failureReason: 'no matching profile row', client: client);
        return 'Sign-in failed: account has no profile row (contact admin)';
      }
      if (!profileRow.isActive) {
        await _recordAttempt(email, success: false, failureReason: 'account inactive', client: client);
        return 'Sign-in failed: account is inactive';
      }

      _client = client;
      currentUser = profileRow;
      mustChangePassword = authUser.userMetadata?['must_change_password'] == true;

      await _recordAttempt(email, success: true, client: client);
      return null; // null return = success
    } catch (e) {
      await _recordAttempt(email, success: false, failureReason: e.toString(), client: client);
      return 'Sign-in failed: $e';
    }
  }

  Future<void> signOut() async {
    _log('signOut()');
    await _client?.auth.signOut();
    _client = null;
    currentUser = null;
    mustChangePassword = false;
  }

  Future<String?> changePassword(String newPassword) async {
    _log('changePassword()');
    final client = _client;
    if (client == null) return 'Not signed in.';
    try {
      await client.auth.updateUser(UserAttributes(
        password: newPassword,
        data: {'must_change_password': false},
      ));
      mustChangePassword = false;
      return null;
    } catch (e) {
      return 'Password change failed: $e';
    }
  }


  Future<void> _recordAttempt(
    String email, {
    required bool success,
    String? failureReason,
    SupabaseClient? client,
  }) async {
    final entry = LoginLog(
      emailAttempted: email,
      userId: currentUser?.id,
      success: success,
      method: LoginMethod.online,
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
    if (!isSignedIn) return 'Not signed in. Use sign-in <cloud|lan> <email> <password> first.';
    if (mustChangePassword) return 'You must change your password first. Use change-password <new password...>.';
    return null;
  }
}