// lib/viewmodels/learner_leavers_viewmodel.dart
//
// SF1 leavers (spec docs/superpowers/specs/2026-11-12-sf1-leavers-design.md):
// learners who are no longer on a section's SF1. An admin or coordinator
// archives them (transferred out / dropped out), moves them to another
// section of the same grade with this year's records, restores a returner,
// and later anonymizes long-archived learners. Admin build only.
//
// Every action is one server function (one transaction, online), which also
// checks the caller (superadmin, or an admin/coordinator of the learner's
// school). What it returns is copied onto this device (mirrorLeaverResult);
// that copy can lag behind the server in rare cases (a move this device
// hasn't pulled), so each message says to pull (owner 2026-11-13).
//
// Only anonymizing takes a confirm code (owner 2026-11-12): it acts on a
// whole list; archive, move and restore name one learner each.
import 'dart:async' show TimeoutException;
import 'dart:convert';
import 'dart:io' show SocketException;

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' show ClientException;
import 'package:supabase/supabase.dart' show PostgrestException, SupabaseClient;

import '../core/console/logger.dart';
import '../core/models/enrollment.dart';
import '../core/models/enrollment_move.dart';
import '../core/models/sf1_missing_learner.dart';
import '../core/models/student.dart';
import '../core/models/user.dart';
import '../core/models/user_role.dart';
import '../core/repositories/learner_leaver_repository.dart';
import 'auth_viewmodel.dart';
import 'viewmodel_exception.dart';

/// The end of every action's message when the device copy was updated.
const leaverSavedNote = 'saved on the server; pull to refresh this device.';

/// The end of the message when the device copy could not be updated.
const leaverNotMirroredNote = "saved on the server, but this device's copy was not updated: "
    'pull to refresh this device.';

/// Shown when the anonymize code no longer matches the list.
/// (Wording rule, console_wording_test: the command goes in brackets.)
const leaverAnonymizeStaleMessage = 'The list changed since the preview: preview again (learner-anonymize-preview).';

/// Refuses an archive, move or restore while this device holds the learner's
/// records that are not on the server yet ([n] of them): the server change
/// would turn them into a sync conflict, or stop the upload.
String leaverUploadFirstMessage(int n) => 'This device has $n record${n == 1 ? '' : 's'} of this learner that '
    "${n == 1 ? 'is' : 'are'} not on the server yet: upload this device's work first (sync-upload), then try again.";

/// Shown when the server could not be reached during an action.
const leaverUnreachableMessage = 'The server could not be reached: check the connection, then download the latest '
    'data to see whether the change was saved (pull-cloud).';

/// What one archive, move or restore did.
class LearnerLeaverOutcome {
  /// The enrollment as the server holds it now.
  final Enrollment? enrollment;

  /// Set when the learner was moved to another section.
  final EnrollmentMove? move;

  /// False when this device's copy could not be updated (pull to fix it).
  final bool mirrored;
  final String message;

  const LearnerLeaverOutcome({this.enrollment, this.move, required this.mirrored, required this.message});
}

/// A learner who may be anonymized now (spec D3).
class AnonymizeCandidate {
  final int studentId;

  /// When the latest enrollment was archived (ISO date) and its school year.
  final String? leftOn;
  final String schoolYear;

  /// From this device's copy; null when the learner isn't on it.
  final String? lrn;
  final String? name;

  const AnonymizeCandidate(
      {required this.studentId, required this.leftOn, required this.schoolYear, this.lrn, this.name});
}

class LearnerLeaversViewModel {
  static const forbiddenMessage = 'Forbidden: only an admin or coordinator archives, moves or restores learners.';
  static const _codeLength = 12;

  final ScopedLogger _log;
  final AuthViewModel _auth;
  final LearnerLeaverRepository Function(SupabaseClient client) _cloudFor;
  final Future<void> Function(Map<String, dynamic> result) _mirror;
  final Future<Student?> Function(int studentId) _localStudent;
  final Future<int> Function(int enrollmentId) _unsentRecords;

  /// The message of the last action (archive, move, restore, anonymize).
  String? lastMessage;

  LearnerLeaversViewModel({
    required AuthViewModel auth,
    required LearnerLeaverRepository Function(SupabaseClient client) cloud,
    required Future<void> Function(Map<String, dynamic> result) mirror,
    required Future<Student?> Function(int studentId) localStudent,
    required Future<int> Function(int enrollmentId) unsentRecords,
    Logger? logger,
  })  : _auth = auth,
        _unsentRecords = unsentRecords,
        _cloudFor = cloud,
        _mirror = mirror,
        _localStudent = localStudent,
        _log = ScopedLogger(logger, 'learner-leavers');

  // ---- Lists ----

  /// Learners still active in a section of the school (or in [sectionId])
  /// whose LRN is not on that section's last imported SF1 (spec D9). Only
  /// sections imported since this feature have a last import. [schoolId]:
  /// the superadmin names it; a school-bound user gets their own.
  Future<List<Sf1MissingLearner>> missing({int? sectionId, int? schoolId}) async {
    _log('missing(sectionId: $sectionId, schoolId: $schoolId)');
    final (repo, school) = _cloud(schoolId);
    final rows = await _server(() => repo.missing(school, sectionId: sectionId));
    return [
      for (final r in rows)
        Sf1MissingLearner(
          enrollmentId: (r['enrollment_id'] as num).toInt(),
          studentId: (r['student_id'] as num).toInt(),
          lrn: r['lrn'] as String,
          name: '${r['last_name']}, ${r['first_name']}',
          sectionId: (r['section_id'] as num?)?.toInt(),
          sectionName: r['section_name'] as String?,
        ),
    ];
  }

  // ---- Archive, move, restore ----

  /// Archives an active enrollment: transferred out or dropped out (spec
  /// D1). The learner's active ARAL entry that year is exited too.
  Future<LearnerLeaverOutcome> archive(int enrollmentId, EnrollmentStatus reason, {String? note}) async {
    _log('archive($enrollmentId, ${reason.value})');
    final (repo, _) = _cloud(null, needSchool: false);
    if (!reason.isArchived) throw const ViewModelException('The reason must be transferred out or dropped out.');
    await _requireNothingUnsent(enrollmentId);
    final trimmed = note?.trim();
    final result = await _server(
        () => repo.archive(enrollmentId, reason.value, trimmed == null || trimmed.isEmpty ? null : trimmed));
    final label = reason == EnrollmentStatus.transferredOut ? 'transferred out' : 'dropped out';
    final aral = result['aral_enrollment'] != null ? ' Their ARAL entry was exited too.' : '';
    return _finish(result, 'Enrollment $enrollmentId archived ($label):', aral);
  }

  /// Moves an active learner to another section of the same school, year
  /// and grade, with this year's CRLA, Phil-IRI and GST records (spec D5-D7).
  /// [source] is decided here when left out, from the learner's own data:
  /// `sf1_missing` when the enrollment is on its section's missing list (the
  /// old section's last SF1 left the learner out), else `sf1_incoming`
  /// (confirmed from the new section's file). Both can be true (left off X's
  /// re-import AND on Y's file): the missing list wins, it was X's import
  /// that left them out first. [schoolId] (the superadmin may give it) must
  /// be the enrollment's school when given.
  Future<LearnerLeaverOutcome> move(int enrollmentId, int toSectionId, {String? source, int? schoolId}) async {
    _log('move($enrollmentId, $toSectionId, $source)');
    final (repo, _) = _cloud(schoolId, needSchool: false);
    if (source != null &&
        source != EnrollmentMoveSource.sf1Missing.value &&
        source != EnrollmentMoveSource.sf1Incoming.value) {
      throw const ViewModelException('The move source must be sf1_missing or sf1_incoming.');
    }
    await _requireNothingUnsent(enrollmentId);
    final chosen = source ?? await _moveSource(repo, enrollmentId, schoolId);
    final result = await _server(() => repo.move(enrollmentId, toSectionId, chosen));
    return _finish(result, 'Enrollment $enrollmentId moved to section $toSectionId ${_movedCounts(result)}:', '');
  }

  Future<String> _moveSource(LearnerLeaverRepository repo, int enrollmentId, int? schoolId) async {
    final place = await _server(() => repo.enrollmentPlace(enrollmentId));
    if (place == null) throw ViewModelException('Enrollment $enrollmentId not found (or not one you can manage).');
    if (schoolId != null && schoolId != place.schoolId) {
      throw ViewModelException('Enrollment $enrollmentId is at school ${place.schoolId}, not school $schoolId.');
    }
    final missing = await _server(() => repo.missing(place.schoolId, sectionId: place.sectionId));
    return missing.any((r) => (r['enrollment_id'] as num).toInt() == enrollmentId)
        ? EnrollmentMoveSource.sf1Missing.value
        : EnrollmentMoveSource.sf1Incoming.value;
  }

  /// Restores an archived learner (spec D8): into their own section, or
  /// moved into [toSectionId] (same grade). ARAL is not restored.
  Future<LearnerLeaverOutcome> restore(int enrollmentId, {int? toSectionId}) async {
    _log('restore($enrollmentId, $toSectionId)');
    final (repo, _) = _cloud(null, needSchool: false);
    // Into another section the learner's records move as in [move]; into
    // their own section only the enrollment (not a synced record) changes.
    if (toSectionId != null) await _requireNothingUnsent(enrollmentId);
    final result = await _server(() => repo.restore(enrollmentId, toSectionId));
    final where = result['move'] != null ? ' into section $toSectionId ${_movedCounts(result)}' : '';
    return _finish(result, 'Enrollment $enrollmentId restored$where:',
        ' ARAL is not restored: enroll them in ARAL again if they need it.');
  }

  // ---- Anonymize ----

  /// The school's learners who may be anonymized now (spec D3) and the
  /// confirm code [anonymize] needs.
  Future<({List<AnonymizeCandidate> learners, String code})> anonymizePreview({int? schoolId}) async {
    _log('anonymizePreview($schoolId)');
    final (repo, school) = _cloud(schoolId);
    final rows = await _server(() => repo.anonymizeEligible(school));
    final learners = <AnonymizeCandidate>[];
    for (final r in rows) {
      final id = (r['student_id'] as num).toInt();
      final s = await _localStudent(id);
      learners.add(AnonymizeCandidate(
        studentId: id,
        leftOn: r['left_on'] as String?,
        schoolYear: r['school_year'] as String,
        lrn: s?.lrn,
        name: s == null ? null : '${s.lastName}, ${s.firstName}',
      ));
    }
    return (learners: learners, code: _code(school, learners));
  }

  /// Anonymizes every learner of the preview whose [code] is given (spec D2):
  /// the list is read again and refused when it changed. Returns how many.
  Future<int> anonymize(String code, {int? schoolId}) async {
    _log('anonymize(${code.trim()}, $schoolId)');
    final (repo, school) = _cloud(schoolId);
    final preview = await anonymizePreview(schoolId: school);
    if (code.trim().toLowerCase() != preview.code) throw const ViewModelException(leaverAnonymizeStaleMessage);
    var done = 0;
    var mirrored = true;
    for (final l in preview.learners) {
      try {
        final result = await _server(() => repo.anonymize(l.studentId));
        mirrored = await _tryMirror(result) && mirrored;
      } on ViewModelException catch (e) {
        lastMessage = 'Anonymized $done of ${preview.learners.length} learners; learner ${l.studentId} was '
            'refused: ${e.message} Pull to finish clearing, then preview again (learner-anonymize-preview).';
        throw ViewModelException(lastMessage!);
      }
      done++;
    }
    lastMessage = done == 0
        ? 'No learner can be anonymized now.'
        : '$done learner${done == 1 ? '' : 's'} anonymized: '
            '${mirrored ? 'saved on the server' : "saved on the server, but this device's copy was not updated"}; '
            "old LRNs in this device's import conflicts clear on the next pull: pull to finish clearing.";
    return done;
  }

  // ---- Helpers ----

  /// An online session of an admin or coordinator, and the school the call
  /// is about (school-bound: their own; the superadmin: [schoolId]).
  (LearnerLeaverRepository, int) _cloud(int? schoolId, {bool needSchool = true}) {
    final sessionError = _auth.requireOnlineSession();
    if (sessionError != null) throw ViewModelException(sessionError);
    final User me = _auth.currentUser!;
    if (me.role != UserRole.admin && me.role != UserRole.coordinator) {
      throw const ViewModelException(forbiddenMessage);
    }
    final repo = _cloudFor(_auth.client!);
    if (!needSchool) return (repo, 0);
    if (me.schoolId != null) {
      if (schoolId != null && schoolId != me.schoolId) {
        throw const ViewModelException("Forbidden: you can only manage your own school's learners.");
      }
      return (repo, me.schoolId!);
    }
    if (schoolId == null) throw const ViewModelException('Give the school: the superadmin has no school of their own.');
    return (repo, schoolId);
  }

  /// Refuses while this device holds the learner's records not on the server
  /// yet (owner 2026-11-13): the server change would bump them under an
  /// unsent edit (a sync conflict) or stop the upload (archived learner).
  Future<void> _requireNothingUnsent(int enrollmentId) async {
    final n = await _unsentRecords(enrollmentId);
    if (n > 0) throw ViewModelException(leaverUploadFirstMessage(n));
  }

  /// The server's refusals (the functions raise readable messages), and a
  /// lost connection, as messages a screen or the console shows as they are.
  Future<T> _server<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on PostgrestException catch (e) {
      if (e.code == '42501') throw const ViewModelException('Forbidden: the database refused this change.');
      throw ViewModelException('The database refused it: ${e.message}.');
    } on SocketException {
      throw const ViewModelException(leaverUnreachableMessage);
    } on TimeoutException {
      throw const ViewModelException(leaverUnreachableMessage);
    } on ClientException {
      // The supabase client's lost connection (package:http).
      throw const ViewModelException(leaverUnreachableMessage);
    }
  }

  Future<bool> _tryMirror(Map<String, dynamic> result) async {
    try {
      await _mirror(result);
      return true;
    } catch (e) {
      _log('WARNING: the device copy was not updated ($e)');
      return false;
    }
  }

  Future<LearnerLeaverOutcome> _finish(Map<String, dynamic> result, String what, String extra) async {
    final mirrored = await _tryMirror(result);
    final e = result['enrollment'], m = result['move'];
    final out = LearnerLeaverOutcome(
      enrollment: e is Map ? Enrollment.fromMap(Map<String, Object?>.from(e)) : null,
      move: m is Map ? EnrollmentMove.fromMap(Map<String, Object?>.from(m)) : null,
      mirrored: mirrored,
      message: '$what ${mirrored ? leaverSavedNote : leaverNotMirroredNote}$extra',
    );
    lastMessage = out.message;
    return out;
  }

  /// "with this year's records (N CRLA, N Phil-IRI, N GST)".
  static String _movedCounts(Map<String, dynamic> result) {
    final moved = result['moved'];
    int n(String table) => moved is Map ? ((moved[table] as List?)?.length ?? 0) : 0;
    return "with this year's records (${n('crla_assessments')} CRLA, ${n('phil_iri_assessments')} Phil-IRI, "
        "${n('phil_iri_gst_results')} GST)";
  }

  static String _code(int schoolId, List<AnonymizeCandidate> learners) {
    final parts = ['$schoolId', for (final l in learners) '${l.studentId}|${l.leftOn}|${l.schoolYear}'];
    return sha256.convert(utf8.encode(parts.join('\n'))).toString().substring(0, _codeLength);
  }
}
