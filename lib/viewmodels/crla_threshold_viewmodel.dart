// lib/viewmodels/crla_threshold_viewmodel.dart
//
// CRLA adjustable thresholds (online): view the region row and a school's
// override, change them, and re-score chosen assessments with today's values.
//
// Like PhilIriContentViewModel: reads and writes go through the signed-in
// user's client (RLS applies), and each successful write is mirrored into the
// local database so CrlaViewModel (offline) stamps new assessments with the
// new values. A failed mirror never undoes the cloud write; it is reported in
// [lastMirrorWarning] (pull-cloud repairs the local copy).
//
// Who may write (checked here for a clear message; the cloud enforces it):
// the region row and any school: superadmin; a school's override: that
// school's admin/coordinator. Tutors only read. Regenerate: superadmin, or an
// admin/coordinator for their own school's assessments.
import 'package:supabase/supabase.dart';

import '../core/console/logger.dart';
import '../core/models/crla_threshold_setting.dart';
import '../core/models/user_role.dart';
import '../core/repositories/crla_assessment_repository.dart';
import '../core/repositories/crla_part1_english_repository.dart';
import '../core/repositories/crla_part1_standard_repository.dart';
import '../core/repositories/crla_threshold_repository.dart';
import '../core/services/crla_rules.dart';
import 'auth_viewmodel.dart';
import 'viewmodel_exception.dart';

/// The Supabase repositories, built per signed-in client.
class CrlaThresholdCloudRepos {
  final CrlaThresholdRepository thresholds;
  final CrlaAssessmentRepository assessments;
  final CrlaPart1StandardRepository part1Standard;
  final CrlaPart1EnglishRepository part1English;

  const CrlaThresholdCloudRepos({
    required this.thresholds,
    required this.assessments,
    required this.part1Standard,
    required this.part1English,
  });
}

/// The stored threshold rows that apply to one school and their merge.
class CrlaThresholdLayers {
  final CrlaThresholdSetting? region;
  final CrlaThresholdSetting? school;
  final CrlaThresholds effective;
  const CrlaThresholdLayers(this.region, this.school, this.effective);

  /// The built-in values that apply when neither row sets a key.
  CrlaThresholds get defaults => CrlaThresholds.defaults;
}

class CrlaThresholdViewModel {
  final ScopedLogger _log;
  final AuthViewModel _auth;
  final CrlaThresholdCloudRepos Function(SupabaseClient client) _cloudFor;
  final CrlaThresholdRepository _localThresholds;
  final CrlaAssessmentRepository _localAssessments;
  final CrlaPart1StandardRepository _localPart1Standard;
  final CrlaPart1EnglishRepository _localPart1English;

  /// Set when the last write reached the cloud but its local copy failed.
  String? lastMirrorWarning;

  CrlaThresholdViewModel({
    required AuthViewModel auth,
    required CrlaThresholdCloudRepos Function(SupabaseClient client) cloudFactory,
    required CrlaThresholdRepository localThresholds,
    required CrlaAssessmentRepository localAssessments,
    required CrlaPart1StandardRepository localPart1Standard,
    required CrlaPart1EnglishRepository localPart1English,
    Logger? logger,
  })  : _auth = auth,
        _cloudFor = cloudFactory,
        _localThresholds = localThresholds,
        _localAssessments = localAssessments,
        _localPart1Standard = localPart1Standard,
        _localPart1English = localPart1English,
        _log = ScopedLogger(logger, 'CrlaThresholdViewModel');

  // ---- Access ----

  bool get _isSuperadmin =>
      _auth.currentUser?.role == UserRole.admin && _auth.currentUser?.schoolId == null;

  CrlaThresholdCloudRepos _cloud() {
    final sessionError = _auth.requireOnlineSession();
    if (sessionError != null) throw ViewModelException(sessionError);
    return _cloudFor(_auth.client!);
  }

  /// For writes: also clears the previous mirror warning.
  CrlaThresholdCloudRepos _writer() {
    final cloud = _cloud();
    final role = _auth.currentUser?.role;
    if (role != UserRole.admin && role != UserRole.coordinator) {
      throw const ViewModelException('Forbidden: admin or coordinator only.');
    }
    lastMirrorWarning = null;
    return cloud;
  }

  /// [schoolId] null = region-wide.
  void _checkCanManageSchool(int? schoolId) {
    if (_isSuperadmin) return;
    if (schoolId == null) {
      throw const ViewModelException('Forbidden: only the superadmin manages the region-wide CRLA thresholds.');
    }
    if (_auth.currentUser?.schoolId != schoolId) {
      throw const ViewModelException('Forbidden: you can only manage the CRLA thresholds of your own school.');
    }
  }

  // ---- Thresholds ----

  /// The region row, [schoolId]'s override (none when null) and the values
  /// that apply: built-in defaults <- region <- school, key by key.
  Future<CrlaThresholdLayers> thresholdLayers(int? schoolId) async {
    _log('thresholdLayers($schoolId)');
    final cloud = _cloud();
    final region = await cloud.thresholds.getRegion();
    final school = schoolId == null ? null : await cloud.thresholds.getForSchool(schoolId);
    return CrlaThresholdLayers(
        region, school, CrlaThresholds.fromMap({...?region?.settings, ...?school?.settings}));
  }

  /// Changes some keys of the region row ([schoolId] null, superadmin) or a
  /// school's override. Keys not in [changes] keep their stored value; a key
  /// set to null is removed from the row, so the layer below applies again.
  /// [replace] stores exactly [changes] instead. The values that would apply
  /// are validated before anything is saved. Only assessments started after
  /// this use the new values (see [regenerate]).
  Future<CrlaThresholdSetting> saveThresholds({
    required int? schoolId,
    required Map<String, Object?> changes,
    bool replace = false,
  }) async {
    _log('saveThresholds(schoolId: $schoolId, changes: $changes, replace: $replace)');
    final cloud = _writer();
    _checkCanManageSchool(schoolId);
    _checkThresholdKeys(changes);

    final region = await cloud.thresholds.getRegion();
    final current = schoolId == null ? region : await cloud.thresholds.getForSchool(schoolId);
    final settings = <String, Object?>{if (!replace) ...?current?.settings, ...changes}
      ..removeWhere((_, v) => v == null);
    final effective = CrlaThresholds.fromMap(schoolId == null ? settings : {...?region?.settings, ...settings});
    try {
      effective.validate();
    } on ArgumentError catch (e) {
      throw ViewModelException('${e.message}');
    }

    final saved = await _cloudWrite(() => cloud.thresholds.save(schoolId, settings));
    await _mirror('CRLA thresholds', () => _localThresholds.upsertWithId(saved));
    return saved;
  }

  /// Removes a school's override so the region values apply again.
  Future<void> resetSchoolThresholds(int schoolId) async {
    _log('resetSchoolThresholds($schoolId)');
    final cloud = _writer();
    _checkCanManageSchool(schoolId);
    if (await cloud.thresholds.getForSchool(schoolId) == null) {
      throw ViewModelException('School $schoolId has no CRLA threshold override.');
    }
    await _cloudWrite(() => cloud.thresholds.deleteForSchool(schoolId));
    await _mirror('CRLA thresholds', () => _localThresholds.removeMirroredForSchool(schoolId));
  }

  /// fromMap silently ignores unknown keys and falls back on bad types, so a
  /// typo would save "nothing changed"; refuse it here instead.
  void _checkThresholdKeys(Map<String, Object?> changes) {
    final known = CrlaThresholds.defaults.toMap();
    for (final e in changes.entries) {
      if (!known.containsKey(e.key)) {
        throw ViewModelException('Unknown CRLA threshold "${e.key}". Known: ${known.keys.join(', ')}.');
      }
      final v = e.value;
      if (v == null) continue;
      final ok = known[e.key] is bool ? v is bool : v is int;
      if (!ok) {
        throw ViewModelException(
            'CRLA threshold "${e.key}" must be ${known[e.key] is bool ? 'true or false' : 'a whole number'} (got $v).');
      }
    }
  }

  // ---- Regenerate ----

  /// Re-scores cloud assessments with today's thresholds (their snapshot,
  /// Part 1 level and reading profile change; scores don't). All-or-nothing.
  /// The re-scored rows are mirrored to this device. Assessments entered on
  /// this device and not uploaded yet are not in the cloud and can't be
  /// regenerated here.
  Future<int> regenerate(List<int> assessmentIds) async {
    _log('regenerate($assessmentIds)');
    if (assessmentIds.isEmpty) throw const ViewModelException('Give at least one assessment id.');
    final cloud = _writer();
    final count = await _cloudWrite(() => cloud.assessments.regenerateResults(assessmentIds));
    await _mirror('Regenerated CRLA results', () async {
      for (final id in assessmentIds.toSet()) {
        final a = await cloud.assessments.findById(id);
        if (a == null) continue;
        await _localAssessments.upsertWithId(a);
        final std = await cloud.part1Standard.findByAssessmentId(id);
        if (std != null) await _localPart1Standard.upsertWithId(std);
        final eng = await cloud.part1English.findByAssessmentId(id);
        if (eng != null) await _localPart1English.upsertWithId(eng);
      }
    });
    return count;
  }

  // ---- Helpers ----

  /// Runs a cloud write and turns the database's refusals into messages.
  Future<T> _cloudWrite<T>(Future<T> Function() write) async {
    try {
      return await write();
    } on PostgrestException catch (e) {
      if (e.code == '42501') {
        throw ViewModelException(e.message.startsWith('only an admin')
            ? 'Forbidden: ${e.message}.'
            : 'Forbidden: the database refused this change.');
      }
      if (e.code == 'P0001' && e.message.isNotEmpty) {
        throw ViewModelException(e.message[0].toUpperCase() + e.message.substring(1));
      }
      rethrow;
    }
  }

  Future<void> _mirror(String what, Future<void> Function() write) async {
    try {
      await write();
    } catch (e) {
      lastMirrorWarning = '$what saved online, but the local copy was not updated. Run pull-cloud.';
      _log('WARNING: $what mirror failed: $e');
    }
  }
}
