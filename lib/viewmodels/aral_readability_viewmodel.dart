// lib/viewmodels/aral_readability_viewmodel.dart
//
// The readability log of an ARAL learner (piece R4): the reading selections
// used in the intervention with their counts, and the Flesch reading ease and
// grade level computed from them (aral_readability.dart). Reading
// coordinator's workbook, sheet "Readability"; owner (2026-10-18): only
// available while the school's foundational literacy program (SHARP) is
// switched on. Offline-first like the check-ins: written on this device
// (origin 'local'); the learner's ARAL tutor and the school's admins/
// coordinators read and write it.
import '../core/console/logger.dart';
import '../core/models/aral_enrollment.dart';
import '../core/models/aral_readability_log.dart';
import '../core/models/user.dart';
import '../core/models/user_role.dart';
import '../core/repositories/aral_enrollment_repository.dart';
import '../core/repositories/aral_material_repository.dart';
import '../core/repositories/aral_readability_repository.dart';
import '../core/repositories/aral_setting_repository.dart';
import '../core/services/aral_readability.dart';
import '../core/services/sync_upload_rules.dart' show pendingLockMessage;
import '../core/services/aral_rules.dart' show AralProgramSettings;
import 'viewmodel_exception.dart';
import 'auth_viewmodel.dart';

/// One entry with its scores.
class AralReadabilityEntry {
  final AralReadabilityLog log;
  final AralReadability readability;
  const AralReadabilityEntry(this.log, this.readability);
}

class AralReadabilityViewModel {
  // RAISE(ABORT, ...) texts of the local triggers (aral_local_schema.dart) and
  // the repository's StateErrors. Keep in sync.
  static const _dbRefusals = [
    'The learner is not active in ARAL',
    "The readability log is only kept while the school's foundational literacy program (SHARP) is switched on",
    'A reading cannot be dated before the learner entered ARAL',
    'A readability log entry keeps its learner; only the selection, counts, date and source change',
    'No readability log entry with id',
  ];

  final ScopedLogger _log;
  final AuthViewModel _auth;
  final AralReadabilityRepository _logs;
  final AralEnrollmentRepository _roster;
  final AralSettingRepository _localSettings;
  final AralMaterialRepository _materials;

  AralReadabilityViewModel({
    required AuthViewModel auth,
    required AralReadabilityRepository logs,
    required AralEnrollmentRepository roster,
    required AralSettingRepository localSettings,
    required AralMaterialRepository materials,
    Logger? logger,
  })  : _auth = auth,
        _logs = logs,
        _roster = roster,
        _localSettings = localSettings,
        _materials = materials,
        _log = ScopedLogger(logger, 'AralReadabilityViewModel');

  /// Is the readability log available for [schoolId] (its SHARP switch, on
  /// this device's copy of the settings)?
  Future<bool> available(int schoolId) async {
    final region = await _localSettings.getRegion();
    final school = await _localSettings.getForSchool(schoolId);
    return AralProgramSettings.fromMap({...?region?.settings, ...?school?.settings}).foundationalProgram;
  }

  /// The learner's entries with their scores, oldest first.
  Future<List<AralReadabilityEntry>> entries(int enrollmentId) async {
    _log('entries($enrollmentId)');
    final e = await _require(enrollmentId);
    await _requireAvailable(e);
    return [
      for (final l in await _logs.forEnrollment(enrollmentId))
        AralReadabilityEntry(l, aralReadability(words: l.words, sentences: l.sentences, syllables: l.syllables)),
    ];
  }

  /// Logs a selection read with the learner. [materialId] links a catalog
  /// material (its title is used when [title] is blank).
  Future<AralReadabilityEntry> add({
    required int enrollmentId,
    String? title,
    required int words,
    required int sentences,
    required int syllables,
    DateTime? readOn,
    String? source,
    int? materialId,
  }) async {
    _log('add(enrollment: $enrollmentId, "$title", $words/$sentences/$syllables, material: $materialId)');
    final e = await _require(enrollmentId);
    await _requireAvailable(e);
    if (e.status != AralStatus.active) throw const ViewModelException('The learner is not active in ARAL.');
    var name = _blankToNull(title);
    if (materialId != null) {
      final m = await _materials.findById(materialId);
      if (m == null) throw ViewModelException('No ARAL material with id $materialId on this device.');
      name ??= m.title;
    }
    if (name == null) throw const ViewModelException('Give the title of the selection.');
    final readability = _score(words, sentences, syllables);
    final saved = await _write(() => _logs.insert(AralReadabilityLog(
          enrollmentId: enrollmentId,
          readOn: _checkDate(readOn, e),
          title: name!,
          words: words,
          sentences: sentences,
          syllables: syllables,
          source: _blankToNull(source),
          materialId: materialId,
          createdBy: _auth.currentUser?.id,
        )));
    return AralReadabilityEntry(saved, readability);
  }

  /// Corrects an entry (the learner stays).
  Future<AralReadabilityEntry> update(
    int id, {
    String? title,
    int? words,
    int? sentences,
    int? syllables,
    DateTime? readOn,
    String? Function()? source,
  }) async {
    _log('update($id)');
    final (current, e) = await _requireEntry(id);
    await _requireAvailable(e);
    final next = current.copyWith(
      title: title == null ? null : (_blankToNull(title) ?? (throw const ViewModelException('A title cannot be blank.'))),
      words: words,
      sentences: sentences,
      syllables: syllables,
      readOn: readOn == null ? null : _checkDate(readOn, e),
      source: source == null ? null : () => _blankToNull(source()),
    );
    final readability = _score(next.words, next.sentences, next.syllables);
    return AralReadabilityEntry(await _write(() => _logs.update(next)), readability);
  }

  Future<void> delete(int id) async {
    _log('delete($id)');
    final (_, e) = await _requireEntry(id);
    await _requireAvailable(e);
    await _write(() => _logs.delete(id));
  }

  // ---- helpers ----

  AralReadability _score(int words, int sentences, int syllables) {
    try {
      return aralReadability(words: words, sentences: sentences, syllables: syllables);
    } on ArgumentError catch (err) {
      throw ViewModelException('Check the counts: ${err.message} (words $words, sentences $sentences, '
          'syllables $syllables).');
    }
  }

  Future<void> _requireAvailable(AralEnrollment e) async {
    if (!await available(e.schoolId)) {
      throw const ViewModelException("The readability log is only kept while the school's foundational literacy "
          'program (SHARP) is switched on (aral-sharp-set).');
    }
  }

  User _me() {
    final u = _auth.currentUser;
    if (u == null) throw const ViewModelException('Not signed in.');
    return u;
  }

  /// The learner's ARAL tutor, or an admin/coordinator of the learner's
  /// school (any school for the superadmin).
  Future<AralEnrollment> _require(int enrollmentId) async {
    final e = await _roster.findById(enrollmentId);
    if (e == null) throw ViewModelException('No ARAL enrollment with id $enrollmentId.');
    final me = _me();
    if (me.role == UserRole.tutor) {
      if (e.tutorId != me.id) throw const ViewModelException('Forbidden: not your ARAL learner.');
    } else if (me.role == UserRole.admin || me.role == UserRole.coordinator) {
      if (me.schoolId != null && me.schoolId != e.schoolId) {
        throw const ViewModelException('Forbidden: that learner is in another school.');
      }
    } else {
      throw const ViewModelException('Forbidden.');
    }
    return e;
  }

  Future<(AralReadabilityLog, AralEnrollment)> _requireEntry(int id) async {
    final l = await _logs.findById(id);
    if (l == null) throw ViewModelException('No readability log entry with id $id.');
    return (l, await _require(l.enrollmentId));
  }

  /// Today or earlier, and not before the learner entered ARAL.
  String _checkDate(DateTime? on, AralEnrollment e) {
    final date = _date(on ?? DateTime.now());
    if (date.compareTo(_date(DateTime.now())) > 0) throw ViewModelException('The date $date is in the future.');
    if (date.compareTo(e.enteredOn) < 0) {
      throw ViewModelException('The date $date is before the learner entered ARAL (${e.enteredOn}).');
    }
    return date;
  }

  Future<T> _write<T>(Future<T> Function() write) async {
    try {
      return await write();
    } catch (err) {
      // A record waiting in an upload (sync): say so, whatever else the
      // statement's text happens to contain.
      if ('$err'.contains(pendingLockMessage)) throw const ViewModelException(pendingLockMessage);
      final text = err.toString();
      for (final refusal in _dbRefusals) {
        if (text.contains(refusal)) throw ViewModelException(refusal.endsWith('.') ? refusal : '$refusal.');
      }
      rethrow;
    }
  }

  static String? _blankToNull(String? s) => s == null || s.trim().isEmpty ? null : s.trim();

  static String _date(DateTime t) {
    final d = t.toLocal();
    return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
  }
}
