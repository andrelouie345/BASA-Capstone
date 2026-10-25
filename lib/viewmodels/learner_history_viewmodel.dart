// lib/viewmodels/learner_history_viewmodel.dart
//
// Learner history (spec docs/superpowers/specs/2026-10-25-learner-history-design.md):
// one learner's progress by school year, for coordinators deciding on a
// learner. Admin build only. Read-only, from the device copy (pull-cloud
// copies every year the user can read). Built from what other modules
// already score: nothing here re-implements a rule.
//  * Per year: section enrollment(s), CRLA profile per round and language
//    (latest attempt), Phil-IRI results per section (PhilIriViewModel.learnerResults),
//    each ARAL entry (class, tutor, attendance, 16th/32nd check-in), SRP class.
//  * Tutors are refused; a school-bound admin/coordinator reads only their
//    school's learners and gets a fixed scope note (other schools' rows never
//    reach the device, so their absence can't be detected).
import '../core/console/logger.dart';
import '../core/models/aral_enrollment.dart';
import '../core/models/crla_assessment.dart' show CrlaRound;
import '../core/models/crla_result.dart';
import '../core/models/student.dart';
import '../core/models/user.dart';
import '../core/models/user_role.dart';
import '../core/repositories/aral_class_repository.dart';
import '../core/repositories/aral_session_repository.dart';
import '../core/repositories/crla_result_repository.dart';
import '../core/repositories/learner_history_repository.dart';
import '../core/repositories/phil_iri_assessment_repository.dart';
import '../core/repositories/phil_iri_gst_repository.dart';
import '../core/repositories/section_repository.dart';
import '../core/repositories/user_repository.dart';
import '../core/services/auth_messages.dart';
import 'aral_checkin_viewmodel.dart';
import 'aral_session_viewmodel.dart' show AralAttendanceSummary;
import 'auth_viewmodel.dart';
import 'phil_iri_viewmodel.dart';
import 'viewmodel_exception.dart';

/// Shown to a school-bound viewer (null for a superadmin).
const learnerHistoryScopeNote = "Only your school's records are shown.";

/// A check-in (after session 16 or 32) as the history shows it: the latest attempt.
enum LearnerHistoryCheckin { passed, failed, notTaken }

class LearnerHistoryEnrollment {
  final String sectionName;
  final String gradeLevel;
  final String schoolName;
  final String status;

  const LearnerHistoryEnrollment(
      {required this.sectionName, required this.gradeLevel, required this.schoolName, required this.status});
}

/// The year's Summer Remediation class.
class LearnerHistorySrp {
  final String className;
  final String? tutorName;
  final String? room;

  const LearnerHistorySrp({required this.className, this.tutorName, this.room});
}

/// One ARAL entry of the year.
class LearnerHistoryAral {
  final AralEnrollment enrollment;
  final String? className; // null = waiting for a class
  final String? tutorName;
  final AralAttendanceSummary attendance;
  final LearnerHistoryCheckin checkin16;
  final LearnerHistoryCheckin checkin32;

  const LearnerHistoryAral({
    required this.enrollment,
    required this.className,
    required this.tutorName,
    required this.attendance,
    required this.checkin16,
    required this.checkin32,
  });
}

/// The year's Phil-IRI results in one section. The GST counts for the whole
/// year (PhilIriViewModel.learnerResults), so a learner moved between sections
/// shows the same GST under each.
class LearnerHistoryPhilIri {
  final int sectionId;
  final String? sectionName; // null when the section is not on this device
  final PhilIriLearnerResults results;

  const LearnerHistoryPhilIri({required this.sectionId, required this.sectionName, required this.results});
}

class LearnerHistoryYear {
  final String schoolYear;
  final List<LearnerHistoryEnrollment> enrollments;
  /// Round -> language -> reading profile of the latest attempt (null = no profile).
  final Map<CrlaRound, Map<String, String?>> crla;
  /// One per section the learner has Phil-IRI rows in that year (usually one).
  final List<LearnerHistoryPhilIri> philIri;
  final List<LearnerHistoryAral> aral;
  final LearnerHistorySrp? srp;

  const LearnerHistoryYear({
    required this.schoolYear,
    required this.enrollments,
    required this.crla,
    required this.philIri,
    required this.aral,
    required this.srp,
  });

  /// Nothing but the enrollment ("No assessments recorded").
  bool get isEmpty => crla.isEmpty && philIri.isEmpty && aral.isEmpty && srp == null;
}

class LearnerHistory {
  final Student student;
  /// Latest school year first.
  final List<LearnerHistoryYear> years;
  final String? scopeNote;

  const LearnerHistory({required this.student, required this.years, required this.scopeNote});
}

class LearnerHistoryViewModel {
  final ScopedLogger _log;
  final AuthViewModel _auth;
  final LearnerHistoryRepository _history;
  final CrlaResultRepository _crlaResults;
  final PhilIriAssessmentRepository _philIriSessions;
  final PhilIriGstRepository _gst;
  final PhilIriViewModel _philIri;
  final AralCheckinViewModel _checkins;
  final AralSessionRepository _sessions;
  final AralClassRepository _classes;
  final UserRepository _users;
  final SectionRepository _sections;

  LearnerHistoryViewModel({
    required AuthViewModel auth,
    required LearnerHistoryRepository history,
    required CrlaResultRepository crlaResults,
    required PhilIriAssessmentRepository philIriSessions,
    required PhilIriGstRepository gst,
    required PhilIriViewModel philIri,
    required AralCheckinViewModel checkins,
    required AralSessionRepository sessions,
    required AralClassRepository classes,
    required UserRepository users,
    required SectionRepository sections,
    Logger? logger,
  })  : _auth = auth,
        _history = history,
        _crlaResults = crlaResults,
        _philIriSessions = philIriSessions,
        _gst = gst,
        _philIri = philIri,
        _checkins = checkins,
        _sessions = sessions,
        _classes = classes,
        _users = users,
        _sections = sections,
        _log = ScopedLogger(logger, 'LearnerHistoryViewModel');

  /// The learner's history, latest school year first.
  Future<LearnerHistory> history(int studentId) async {
    _log('history($studentId)');
    final me = _requireManager();
    final s = await _history.student(studentId);
    if (s == null) {
      throw const ViewModelException('Learner not found on this device. Download the latest data first (pull-cloud).');
    }
    return _build(me, s);
  }

  /// The same, found by LRN (a search box).
  Future<LearnerHistory> historyByLrn(String lrn) async {
    _log('historyByLrn($lrn)');
    final me = _requireManager();
    final s = await _history.studentByLrn(lrn);
    if (s == null) {
      throw ViewModelException(
          'No learner with LRN ${lrn.trim()} on this device. Download the latest data first (pull-cloud).');
    }
    return _build(me, s);
  }

  User _requireManager() {
    final me = _auth.currentUser;
    if (me == null) throw const ViewModelException(notSignedInMessage);
    if (me.role != UserRole.admin && me.role != UserRole.coordinator) {
      throw const ViewModelException('Forbidden: only an admin or coordinator can view learner history.');
    }
    return me;
  }

  Future<LearnerHistory> _build(User me, Student s) async {
    if (me.schoolId != null && s.schoolId != me.schoolId) {
      throw const ViewModelException('Forbidden: that learner is not in your school.');
    }
    final id = s.id!;
    final sections = await _history.sectionEnrollments(id);
    final crla = await _crlaResults.getByStudent(id);
    final philIriSessions = await _philIriSessions.getByStudent(id);
    final gsts = await _gst.getByStudent(id);
    final aral = await _history.aralEntries(id);
    final srp = await _history.srpClasses(id);

    final years = {
      ...sections.map((r) => r.schoolYear),
      ...crla.map((r) => r.schoolYear),
      ...philIriSessions.map((r) => r.schoolYear),
      ...gsts.map((r) => r.schoolYear),
      ...aral.map((r) => r.schoolYear),
      ...srp.map((r) => r.schoolYear),
    }.toList()
      ..sort((a, b) => b.compareTo(a));

    final out = <LearnerHistoryYear>[];
    for (final year in years) {
      final philIriSections = {
        ...philIriSessions.where((r) => r.schoolYear == year).map((r) => r.sectionId),
        ...gsts.where((r) => r.schoolYear == year).map((r) => r.sectionId),
      }.toList()
        ..sort();
      final yearSrp = srp.where((c) => c.schoolYear == year).firstOrNull;
      out.add(LearnerHistoryYear(
        schoolYear: year,
        enrollments: [
          for (final r in sections.where((r) => r.schoolYear == year))
            LearnerHistoryEnrollment(
                sectionName: r.sectionName, gradeLevel: r.gradeLevel, schoolName: r.schoolName, status: r.status),
        ],
        crla: _crlaByRound(crla.where((r) => r.schoolYear == year)),
        philIri: [
          for (final sectionId in philIriSections)
            LearnerHistoryPhilIri(
              sectionId: sectionId,
              sectionName: (await _sections.getById(sectionId))?.sectionName,
              results: await _philIri.learnerResults(studentId: id, sectionId: sectionId, schoolYear: year),
            ),
        ],
        aral: [for (final e in aral.where((e) => e.schoolYear == year)) await _aral(e)],
        srp: yearSrp == null
            ? null
            : LearnerHistorySrp(
                className: yearSrp.className, tutorName: await _userName(yearSrp.tutorId), room: yearSrp.room),
      ));
    }
    return LearnerHistory(student: s, years: out, scopeNote: me.schoolId == null ? null : learnerHistoryScopeNote);
  }

  /// Latest attempt per round and language (highest attempt number, then the latest date).
  Map<CrlaRound, Map<String, String?>> _crlaByRound(Iterable<CrlaResult> results) {
    final latest = <(CrlaRound, String), CrlaResult>{};
    for (final r in results) {
      final key = (r.round, r.language);
      final prev = latest[key];
      if (prev == null ||
          r.attemptNo > prev.attemptNo ||
          (r.attemptNo == prev.attemptNo && r.assessedAt.compareTo(prev.assessedAt) > 0)) {
        latest[key] = r;
      }
    }
    final out = <CrlaRound, Map<String, String?>>{};
    for (final round in CrlaRound.values) {
      final byLanguage = {
        for (final e in latest.entries.where((e) => e.key.$1 == round)) e.key.$2: e.value.readingProfile,
      };
      if (byLanguage.isNotEmpty) out[round] = byLanguage;
    }
    return out;
  }

  Future<LearnerHistoryAral> _aral(AralEnrollment e) async {
    final cls = e.classId == null ? null : await _classes.findById(e.classId!);
    final checkins = await _checkins.learnerCheckins(e.id!);
    LearnerHistoryCheckin at(int checkpoint) {
      final taken = checkins.results.where((r) => r.tool.checkpoint == checkpoint);
      if (taken.isEmpty) return LearnerHistoryCheckin.notTaken;
      final last = taken.reduce((a, b) => b.checkin.attemptNo > a.checkin.attemptNo ? b : a);
      return last.passed ? LearnerHistoryCheckin.passed : LearnerHistoryCheckin.failed;
    }

    return LearnerHistoryAral(
      enrollment: e,
      className: cls?.className,
      tutorName: await _userName(cls?.tutorId),
      attendance: AralAttendanceSummary.of(await _sessions.getAttendanceForEnrollment(e.id!)),
      checkin16: at(16),
      checkin32: at(32),
    );
  }

  Future<String?> _userName(String? id) async => id == null ? null : (await _users.getById(id))?.fullName;
}
