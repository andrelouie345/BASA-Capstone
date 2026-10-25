// lib/viewmodels/report_settings_viewmodel.dart
//
// Report settings (dashboard D2): the progress "done" threshold, saved per
// region (superadmin) with school overrides (their admin/coordinator). Sync
// (S6) adds the auto-approve switch and the offline sign-in window, same rows.
// Progress monitoring and coordinator reminders read the value that applies:
// the built-in default (0.85), then the region row, then the school row.
// Written online and mirrored to this device; read from the local copy.
import 'package:supabase/supabase.dart' show PostgrestException, SupabaseClient;

import '../core/console/logger.dart';
import '../core/models/report_setting.dart';
import '../core/models/user.dart';
import '../core/models/user_role.dart';
import '../core/repositories/report_setting_repository.dart';
import '../core/services/auth_messages.dart';
import 'auth_viewmodel.dart';
import 'viewmodel_exception.dart';

class ReportSettingsViewModel {
  final ScopedLogger _log;
  final AuthViewModel _auth;
  final ReportSettingRepository _local;
  final ReportSettingRepository Function(SupabaseClient client) _cloudFor;

  /// Set when the last change reached the cloud but its local copy failed.
  String? lastMirrorWarning;

  ReportSettingsViewModel({
    required AuthViewModel auth,
    required ReportSettingRepository local,
    required ReportSettingRepository Function(SupabaseClient client) cloud,
    Logger? logger,
  })  : _auth = auth,
        _local = local,
        _cloudFor = cloud,
        _log = ScopedLogger(logger, 'ReportSettingsViewModel');

  // ---- Reading (this device's copy) ----

  /// Local reads need a signed-in user too (finding F18), like the other
  /// ViewModels (F5/F6): screens call these directly.
  void _requireSignIn() {
    final error = _auth.requireActiveSession();
    if (error != null) throw ViewModelException(error);
  }

  /// The settings that apply to [schoolId]: defaults <- region <- school.
  Future<ReportSettings> effective(int schoolId) async {
    _requireSignIn();
    final region = await _local.getRegion();
    final school = await _local.getForSchool(schoolId);
    return ReportSettings.fromMap({...?region?.settings, ...?school?.settings});
  }

  /// The stored done thresholds (null = not set) and the one that applies to
  /// [schoolId] (null = the region's).
  Future<({double? region, double? school, double effective})> doneThresholdLayers(int? schoolId) async {
    _log('doneThresholdLayers($schoolId)');
    _requireSignIn();
    final region = await _local.getRegion();
    final school = schoolId == null ? null : await _local.getForSchool(schoolId);
    double? read(ReportSetting? s) => (s?.settings[ReportSettings.doneThresholdKey] as num?)?.toDouble();
    return (
      region: read(region),
      school: read(school),
      effective: ReportSettings.fromMap({...?region?.settings, ...?school?.settings}).doneThreshold,
    );
  }

  /// The stored auto-approve values (null = not set) and the one that
  /// applies to [schoolId] (null = the region's).
  Future<({bool? region, bool? school, bool effective})> autoApproveLayers(int? schoolId) async {
    _log('autoApproveLayers($schoolId)');
    _requireSignIn();
    final (region, school) = await _layers(schoolId);
    bool? read(ReportSetting? s) => s?.settings[ReportSettings.syncAutoApproveKey] as bool?;
    return (
      region: read(region),
      school: read(school),
      effective: ReportSettings.fromMap({...?region?.settings, ...?school?.settings}).syncAutoApprove,
    );
  }

  /// The stored offline sign-in windows (null = not set) and the one that
  /// applies to [schoolId] (null = the region's).
  Future<({int? region, int? school, int effective})> offlineDaysLayers(int? schoolId) async {
    _log('offlineDaysLayers($schoolId)');
    _requireSignIn();
    final (region, school) = await _layers(schoolId);
    int? read(ReportSetting? s) => (s?.settings[ReportSettings.offlineSigninDaysKey] as num?)?.toInt();
    return (
      region: read(region),
      school: read(school),
      effective: ReportSettings.fromMap({...?region?.settings, ...?school?.settings}).offlineSigninDays,
    );
  }

  Future<(ReportSetting?, ReportSetting?)> _layers(int? schoolId) async =>
      (await _local.getRegion(), schoolId == null ? null : await _local.getForSchool(schoolId));

  // ---- Writing (online, then mirrored) ----

  /// Sets the done threshold (a share 0.01-1) of the region ([schoolId] null,
  /// superadmin) or a school (its admin/coordinator).
  Future<ReportSetting> setDoneThreshold(int? schoolId, double share) async {
    _log('setDoneThreshold($schoolId, $share)');
    final cloud = _writer(schoolId);
    if (!(share >= 0.01 && share <= 1)) {
      throw ViewModelException('The done threshold is a share from 0.01 to 1 (1% to 100%), not $share.');
    }
    return _setKey(cloud, schoolId, ReportSettings.doneThresholdKey, share);
  }

  /// Turns sync auto-approve on or off for the region ([schoolId] null,
  /// superadmin) or a school (its admin/coordinator). Uploads already
  /// waiting are not applied by turning it on.
  Future<ReportSetting> setAutoApprove(int? schoolId, bool on) async {
    _log('setAutoApprove($schoolId, $on)');
    return _setKey(_writer(schoolId), schoolId, ReportSettings.syncAutoApproveKey, on);
  }

  /// Sets the offline sign-in window (whole days 1-60) of the region or a
  /// school. Tablets get it with their next pull.
  Future<ReportSetting> setOfflineDays(int? schoolId, int days) async {
    _log('setOfflineDays($schoolId, $days)');
    final cloud = _writer(schoolId);
    if (days < ReportSettings.minOfflineSigninDays || days > ReportSettings.maxOfflineSigninDays) {
      throw ViewModelException('The offline sign-in window is ${ReportSettings.minOfflineSigninDays} to '
          '${ReportSettings.maxOfflineSigninDays} days, not $days.');
    }
    return _setKey(cloud, schoolId, ReportSettings.offlineSigninDaysKey, days);
  }

  /// Removes a school's override so the region values apply again.
  Future<void> resetSchool(int schoolId) async {
    _log('resetSchool($schoolId)');
    final cloud = _writer(schoolId);
    if (await cloud.getForSchool(schoolId) == null) {
      throw ViewModelException('School $schoolId has no report settings override.');
    }
    await _cloudWrite(() => cloud.deleteForSchool(schoolId));
    await _mirror(() => _local.removeMirroredForSchool(schoolId));
  }

  // ---- Helpers ----

  /// Saves one key into the row of [schoolId] (null = the region's), keeping
  /// its other keys, then mirrors it.
  Future<ReportSetting> _setKey(ReportSettingRepository cloud, int? schoolId, String key, Object value) async {
    final current = schoolId == null ? await cloud.getRegion() : await cloud.getForSchool(schoolId);
    final saved = await _cloudWrite(() => cloud.save(schoolId, {...?current?.settings, key: value}));
    await _mirror(() => _local.upsertWithId(saved));
    return saved;
  }

  User _me() {
    final me = _auth.currentUser;
    if (me == null) throw const ViewModelException(notSignedInMessage);
    return me;
  }

  /// The cloud repository for a change to [schoolId]'s row (null = the
  /// region's): an online session of the superadmin, or of an admin/
  /// coordinator of that school.
  ReportSettingRepository _writer(int? schoolId) {
    final sessionError = _auth.requireOnlineSession();
    if (sessionError != null) throw ViewModelException(sessionError);
    final me = _me();
    final superadmin = me.role == UserRole.admin && me.schoolId == null;
    if (!superadmin) {
      if (me.role != UserRole.admin && me.role != UserRole.coordinator) {
        throw const ViewModelException('Forbidden: only an admin or coordinator sets the report settings.');
      }
      if (schoolId == null) {
        throw const ViewModelException('Forbidden: only the superadmin sets the region-wide report settings.');
      }
      if (me.schoolId != schoolId) {
        throw const ViewModelException("Forbidden: you can only set your own school's report settings.");
      }
    }
    lastMirrorWarning = null;
    return _cloudFor(_auth.client!);
  }

  Future<T> _cloudWrite<T>(Future<T> Function() write) async {
    try {
      return await write();
    } on PostgrestException catch (e) {
      if (e.code == '42501') throw const ViewModelException('Forbidden: the database refused this change.');
      if (e.code == '23505') {
        throw const ViewModelException('The settings were just saved by someone else; show them and try again.');
      }
      if (e.code == 'P0001' || e.code == '23514') throw ViewModelException('The database refused it: ${e.message}.');
      rethrow;
    }
  }

  Future<void> _mirror(Future<void> Function() write) async {
    try {
      await write();
    } catch (e) {
      // The detail goes to the log only: raw database text is no message for a screen (F20).
      lastMirrorWarning = 'The report settings were changed online, but the copy on this device was not updated. '
          'Download the latest data (pull-cloud).';
      _log('WARNING: $lastMirrorWarning ($e)');
    }
  }
}
