// lib/viewmodels/learner_history_viewmodel.dart
//
// Learner history (spec docs/superpowers/specs/2026-10-25-learner-history-design.md):
// one learner's progress by school year, for coordinators deciding on a
// learner. Admin build only. Read-only, from the device copy (pull-cloud
// copies every year the user can read). Built from what other modules
// already score: nothing here re-implements a rule.
//  * Per year: section enrollment, CRLA profile per round and test (MT /
//    Filipino / English, latest attempt), Phil-IRI results per section
//    (PhilIriViewModel.learnerResults), the ARAL entry (class, tutor,
//    attendance, 16th/32nd check-in as the check-in report picks it), SRP class.
//  * A part that can't be read on this device (section or check-in tool
//    missing, section grade changed) gets a note; the rest still shows.
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

/// A check-in (after session 16 or 32) as the history shows it: the latest
/// attempt (aralLatestCheckin). unavailable = the check-ins can't be read on
/// this device (LearnerHistoryAral.unavailable says why).
enum LearnerHistoryCheckin { passed, failed, notTaken, unavailable }

/// Start of the note on a part that can't be read on this device.
const learnerHistoryUnavailable = 'Not available on this device: ';

class LearnerHistoryEnrollment {
  final String sectionName;
  final String gradeLevel;
  final String? schoolName; // null when the school is not on this device
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
  /// Set when the check-ins can't be read on this device ("Not available on this device: ...").
  final String? unavailable;

  const LearnerHistoryAral({
    required this.enrollment,
    required this.className,
    required this.tutorName,
    required this.attendance,
    required this.checkin16,
    required this.checkin32,
    this.unavailable,
  });
}

/// The year's Phil-IRI results in one section. The GST counts for the whole
/// year (PhilIriViewModel.learnerResults), so a learner moved between sections
/// shows the same GST under each. When the results can't be read on this
/// device (section missing, or no longer Grade 4-10), [results] is null and
/// [unavailable] says why.
class LearnerHistoryPhilIri {
  final int sectionId;
  final String? sectionName; // null when the section is not on this device
  final PhilIriLearnerResults? results;
  final String? unavailable;

  const LearnerHistoryPhilIri(
      {required this.sectionId, required this.sectionName, required this.results, this.unavailable});
}

class LearnerHistoryYear {
  final String schoolYear;
  final List<LearnerHistoryEnrollment> enrollments;
  /// Round -> test -> reading profile of the latest attempt (null = no
  /// profile). Tests in the order "MT (language)", "Filipino", "English".
  final Map<CrlaRound, Map<String, String?>> crla;
  /// One per section the learner has Phil-IRI rows in that year (usually one;
  /// two after a section move).
  final List<LearnerHistoryPhilIri> philIri;
  /// At most one (one ARAL entry per learner per year).
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

  /// No CRLA, Phil-IRI, ARAL or SRP in the year, only the enrollment ("No assessments recorded").
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
    if (lrn.trim().isEmpty) throw const ViewModelException('Enter an LRN.');
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
        philIri: [for (final sectionId in philIriSections) await _philIriIn(id, sectionId, year)],
        aral: [for (final e in aral.where((e) => e.schoolYear == year)) await _aral(e)],
        srp: yearSrp == null
            ? null
            : LearnerHistorySrp(
                className: yearSrp.className, tutorName: await _userName(yearSrp.tutorId), room: yearSrp.room),
      ));
    }
    return LearnerHistory(student: s, years: out, scopeNote: me.schoolId == null ? null : learnerHistoryScopeNote);
  }

  Future<LearnerHistoryPhilIri> _philIriIn(int studentId, int sectionId, String year) async {
    final sectionName = (await _sections.getById(sectionId))?.sectionName;
    try {
      return LearnerHistoryPhilIri(
        sectionId: sectionId,
        sectionName: sectionName,
        results: await _philIri.learnerResults(studentId: studentId, sectionId: sectionId, schoolYear: year),
      );
    } on ViewModelException catch (e) {
      return LearnerHistoryPhilIri(
          sectionId: sectionId, sectionName: sectionName, results: null, unavailable: '$learnerHistoryUnavailable${e.message}');
    }
  }

  /// Latest attempt per round and test (subject variant; attempt numbers count
  /// per variant): highest attempt number, then the latest date.
  Map<CrlaRound, Map<String, String?>> _crlaByRound(Iterable<CrlaResult> results) {
    final latest = <(CrlaRound, String), CrlaResult>{};
    for (final r in results) {
      final key = (r.round, r.subjectVariant);
      final prev = latest[key];
      if (prev == null ||
          r.attemptNo > prev.attemptNo ||
          (r.attemptNo == prev.attemptNo && r.assessedAt.compareTo(prev.assessedAt) > 0)) {
        latest[key] = r;
      }
    }
    const order = ['mt', 'fil', 'eng'];
    int rank(String variant) => order.contains(variant) ? order.indexOf(variant) : order.length;
    final out = <CrlaRound, Map<String, String?>>{};
    for (final round in CrlaRound.values) {
      final inRound = latest.entries.where((e) => e.key.$1 == round).toList()
        ..sort((a, b) => rank(a.key.$2).compareTo(rank(b.key.$2)));
      if (inRound.isNotEmpty) {
        out[round] = {for (final e in inRound) _crlaTestLabel(e.value): e.value.readingProfile};
      }
    }
    return out;
  }

  /// "MT (language)", "Filipino" or "English". The fil test stores its
  /// language as "Tagalog" (normalizeCrlaLanguage), so the label comes from the variant.
  static String _crlaTestLabel(CrlaResult r) => switch (r.subjectVariant) {
        'mt' => 'MT (${r.language})',
        'fil' => 'Filipino',
        'eng' => 'English',
        _ => r.subjectVariant,
      };

  Future<LearnerHistoryAral> _aral(AralEnrollment e) async {
    final cls = e.classId == null ? null : await _classes.findById(e.classId!);
    AralLearnerCheckins? checkins;
    String? unavailable;
    try {
      checkins = await _checkins.learnerCheckins(e.id!);
    } on ViewModelException catch (err) {
      unavailable = '$learnerHistoryUnavailable${err.message}';
    }
    LearnerHistoryCheckin at(int checkpoint) {
      final last = checkins?.latestAt(checkpoint);
      if (checkins == null) return LearnerHistoryCheckin.unavailable;
      if (last == null) return LearnerHistoryCheckin.notTaken;
      return last.passed ? LearnerHistoryCheckin.passed : LearnerHistoryCheckin.failed;
    }

    return LearnerHistoryAral(
      enrollment: e,
      className: cls?.className,
      tutorName: await _userName(cls?.tutorId),
      attendance: AralAttendanceSummary.of(await _sessions.getAttendanceForEnrollment(e.id!)),
      checkin16: at(16),
      checkin32: at(32),
      unavailable: unavailable,
    );
  }

  Future<String?> _userName(String? id) async => id == null ? null : (await _users.getById(id))?.fullName;
}
