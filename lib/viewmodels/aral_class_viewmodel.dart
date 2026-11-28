// lib/viewmodels/aral_class_viewmodel.dart
//
// ARAL classes (spec docs/superpowers/specs/2026-10-23-aral-classes-design.md).
// Offline-first like the roster: reads and writes this device's copy; the
// classes travel with sync-upload.
//
// Owner decisions (2026-10-23):
//  * A class belongs to a school and a school year (not a section), with at
//    most 15 active learners (aral_rules.dart; since the ARAL memo settings,
//    the school's class_max_learners).
//  * One tutor per class, possibly blank for a while; a tutor may teach
//    several classes.
//  * Admins and coordinators create, change and delete classes; a tutor reads
//    the classes they teach.
// The device checks here mirror the cloud triggers, so the device refuses
// first with a readable message.
//  * Placing a learner (or moving them to another class) checks the class's
//    school and year, program (one-program classes) and its 15 active places
//    (aral_rules.dart). A program change by aral-update keeps the learner in
//    their class (decision 7); new placements must match.
//  * A class keeps its grade and program once it has learners, and is
//    deleted only when nobody points at it.
// Owner decisions (2026-10-24, from the reading coordinator; plan
// docs/superpowers/plans/2026-10-24-aral-class-grade.md):
//  * G1-G2: a class has a home grade (1-10) and one program or mixed
//    programs (program null).
//  * G3: a learner of another grade goes in only when the coordinator says
//    so (place(otherGrade: true)); the cloud doesn't check grades.
import '../core/console/logger.dart';
import '../core/models/aral_class.dart';
import '../core/models/aral_enrollment.dart';
import '../core/models/aral_progress.dart';
import '../core/models/aral_session.dart' show AralMark;
import '../core/models/crla_assessment.dart' show CrlaRound;
import '../core/models/crla_result.dart';
import '../core/models/phil_iri_assessment.dart' show PhilIriRound;
import '../core/models/report_setting.dart' show PhilIriValues, PhilIriValueList;
import '../core/models/student.dart';
import '../core/repositories/crla_result_repository.dart';
import '../core/services/calendar_rules.dart' show calendarDate;
import '../core/services/phil_iri_results.dart' show PhilIriRoundView, PhilIriRoundStatus;
import '../core/services/phil_iri_rules.dart' show PhilIriLevel;
import 'aral_checkin_viewmodel.dart';
import 'phil_iri_viewmodel.dart';
import '../core/services/aral_checkin_rules.dart' show aralCheckinCheckpoints;
import '../core/services/aral_effectiveness_rules.dart';
import '../core/models/user_role.dart';
import '../core/repositories/aral_class_repository.dart';
import '../core/repositories/aral_enrollment_repository.dart';
import '../core/repositories/aral_setting_repository.dart';
import '../core/repositories/aral_session_repository.dart';
import '../core/repositories/section_repository.dart';
import '../core/repositories/student_repository.dart';
import '../core/repositories/user_repository.dart';
import '../core/services/aral_rule_settings.dart';
import '../core/services/aral_rules.dart';
import '../core/services/normalizers.dart';
import '../core/services/sync_upload_rules.dart' show pendingLockMessage;
import 'auth_viewmodel.dart';
import 'viewmodel_exception.dart';
import '../core/services/auth_messages.dart';

/// The school's ARAL rule settings on this device: defaults <- region row <-
/// school row of the aral_settings mirror (pull-cloud refreshes it).
Future<AralRuleSettings> aralLocalRuleSettings(AralSettingRepository settings, int schoolId) async {
  final region = await settings.getRegion();
  final school = await settings.getForSchool(schoolId);
  return AralRuleSettings.fromMap({...?region?.settings, ...?school?.settings});
}

/// Why [e] (Grade [grade], named [learner]) can't go into [c], and the
/// reason as a readable sentence; null = they can. [otherGradeOk] = the
/// coordinator confirmed another grade. Counts [c]'s other active learners
/// from [roster] against the school's class maximum in [rules], and, when
/// the school's advisers don't tutor their own learners, refuses a class
/// whose tutor advises [e]'s section (read from [sections]). Shared by
/// AralClassViewModel and AralViewModel.
Future<(AralPlacementProblem, String)?> aralPlacementRefusal(
    AralEnrollmentRepository roster, SectionRepository sections, AralClass c, AralEnrollment e,
    {required int grade, required String learner, required AralRuleSettings rules, bool otherGradeOk = false}) async {
  final others = (await roster.getByClass(c.id!)).where((x) => x.isActive && x.id != e.id).length;
  final program = AralClassProgram.of(e.keyStage, e.track);
  final maxLearners = rules.classMaxLearners;
  final section = c.tutorId == null || rules.adviserTutorsOwnClass ? null : await sections.getById(e.sectionId);
  final tutorIsAdviser = section != null && section.adviserUserId == c.tutorId;
  final problem = aralPlacementProblem(
      target: c,
      schoolId: e.schoolId,
      schoolYear: e.schoolYear,
      program: program,
      grade: grade,
      activeOthersInClass: others,
      maxLearners: maxLearners,
      otherGradeOk: otherGradeOk,
      tutorIsAdviser: tutorIsAdviser);
  return problem == null
      ? null
      : (problem,
          aralPlacementMessage(problem,
              learner: learner,
              target: c,
              grade: grade,
              program: program,
              maxLearners: maxLearners,
              sectionName: section?.sectionName));
}

/// The device and cloud placement refusals (trigger texts), mapped back to
/// readable sentences by the ViewModels. The class maximum's text names the
/// school's number: see [aralClassFullDbRefusal].
const aralPlacementDbRefusals = [
  "The learner's program does not match the ARAL class",
  'The ARAL class belongs to another school or school year',
  'An adviser does not tutor their own learners at this school',
];

/// The device or cloud refusal of a full class in [text] ("An ARAL class has
/// at most N active learners", the number = the school's maximum), or null.
String? aralClassFullDbRefusal(String text) {
  final m = RegExp(r'an ARAL class has at most (\d+) active learners', caseSensitive: false).firstMatch(text);
  return m == null ? null : 'An ARAL class has at most ${m.group(1)} active learners.';
}

class AralClassViewModel {
  /// The local trigger texts, shown as they are.
  static const _dbRefusals = [
    "The ARAL class tutor must be an active tutor of the class's school",
    'An ARAL class keeps its school and school year',
    'An ARAL class with learners keeps its grade and program',
    ...aralPlacementDbRefusals,
  ];

  final ScopedLogger _log;
  final AuthViewModel _auth;
  final AralClassRepository _classes;
  final AralEnrollmentRepository _roster;
  final AralSessionRepository _sessions;
  final SectionRepository _sections;
  final StudentRepository _students;
  final UserRepository _users;
  final AralSettingRepository _localSettings;

  AralClassViewModel({
    required AuthViewModel auth,
    required AralClassRepository classes,
    required AralEnrollmentRepository roster,
    required AralSessionRepository sessions,
    required SectionRepository sections,
    required StudentRepository students,
    required UserRepository users,
    required AralSettingRepository localSettings,
    required CrlaResultRepository crlaResults,
    required PhilIriViewModel philIri,
    required AralCheckinViewModel checkins,
    Logger? logger,
  })  : _auth = auth,
        _checkins = checkins,
        _crlaResults = crlaResults,
        _philIri = philIri,
        _localSettings = localSettings,
        _classes = classes,
        _roster = roster,
        _sessions = sessions,
        _sections = sections,
        _students = students,
        _users = users,
        _log = ScopedLogger(logger, 'AralClassViewModel');

  /// Every public method starts here: signed in, online or offline. Screens
  /// call this ViewModel directly, so the console's own check is not enough.
  void _requireSignIn() {
    final error = _auth.requireActiveSession();
    if (error != null) throw ViewModelException(error);
  }

  // ---- Reading ----

  /// The school's classes for [schoolYear] (all years when null), by name. A
  /// tutor gets only the classes they teach.
  Future<List<AralClass>> classes({required int schoolId, String? schoolYear}) async {
    _requireSignIn();
    _log('classes(school: $schoolId, year: $schoolYear)');
    final year = schoolYear == null ? null : _year(schoolYear);
    final me = _auth.currentUser!;
    if (me.role == UserRole.tutor) {
      return (await _classes.getByTutor(me.id, schoolYear: year)).where((c) => c.schoolId == schoolId).toList();
    }
    _requireOwnSchool(schoolId);
    return _classes.getBySchool(schoolId, schoolYear: year);
  }

  /// One class. A tutor reads only the classes they teach.
  Future<AralClass> getClass(int classId) async {
    _requireSignIn();
    _log('getClass($classId)');
    return _readable(classId);
  }

  /// The learners placed in the class (active and exited).
  Future<List<AralEnrollment>> classRoster(int classId) async {
    _requireSignIn();
    _log('classRoster($classId)');
    await _readable(classId);
    return _roster.getByClass(classId);
  }

  /// The most active learners a class of [schoolId] holds: the school's
  /// class_max_learners on this device (default 15).
  Future<int> classMax(int schoolId) async {
    _requireSignIn();
    return (await aralLocalRuleSettings(_localSettings, schoolId)).classMaxLearners;
  }

  /// The fewest active learners a class of [schoolId] should hold: the
  /// school's class_min_learners on this device (0 = no minimum). A class
  /// below it is a coordinator notice, never a refusal.
  Future<int> classMin(int schoolId) async {
    _requireSignIn();
    return (await aralLocalRuleSettings(_localSettings, schoolId)).classMinLearners;
  }

  /// How many active learners the class holds (at most the school's
  /// maximum, [classMax]; more when the maximum was lowered later).
  Future<int> activeCount(int classId) async {
    _requireSignIn();
    await _readable(classId);
    return (await _roster.getByClass(classId)).where((e) => e.isActive).length;
  }

  // ---- Placing learners (admin / coordinator) ----

  /// Puts an active ARAL learner in a class, or moves them from their class
  /// to another one. The class must be of the learner's school and year, teach
  /// their program (unless it mixes programs) and have a free place (fewer
  /// active learners than the school's maximum, [classMax]). A learner of another grade than the class's goes in only with
  /// [otherGrade] (the coordinator's decision, G3).
  Future<AralEnrollment> place(int enrollmentId, int classId, {bool otherGrade = false}) async {
    _requireSignIn();
    _log('place($enrollmentId, $classId, otherGrade: $otherGrade)');
    _requireManager();
    final e = await _requireLearner(enrollmentId);
    final c = await _require(classId);
    if (!e.isActive) {
      throw const ViewModelException('This learner left ARAL; reactivate them before placing them in a class.');
    }
    if (e.classId == classId) throw ViewModelException('This learner is already in class "${c.className}".');
    final (grade, name) = await _gradeAndName(e);
    final rules = await aralLocalRuleSettings(_localSettings, c.schoolId);
    final refusal = await aralPlacementRefusal(_roster, _sections, c, e,
        grade: grade, learner: name, rules: rules, otherGradeOk: otherGrade);
    if (refusal != null) {
      throw ViewModelException(refusal.$1 == AralPlacementProblem.otherGrade
          ? '${refusal.$2} To place them in it anyway, confirm the other grade (other-grade).'
          : refusal.$2);
    }
    return _write(() => _roster.update(e.copyWith(classId: () => classId)));
  }

  /// Takes the learner out of their class: they wait for a class.
  Future<AralEnrollment> unplace(int enrollmentId) async {
    _requireSignIn();
    _log('unplace($enrollmentId)');
    _requireManager();
    final e = await _requireLearner(enrollmentId);
    if (e.classId == null) throw const ViewModelException('This learner is not in a class.');
    return _write(() => _roster.update(e.copyWith(classId: () => null)));
  }

  // ---- Writing (admin / coordinator) ----

  /// A new class of Grade [gradeLevel] (1-10) teaching [program], or mixed
  /// programs when [program] is null.
  Future<AralClass> createClass({
    required int schoolId,
    required String schoolYear,
    required String className,
    required int gradeLevel,
    AralClassProgram? program,
    String? tutorId,
    String? room,
    String? schedule,
    String? notes,
    AralSessionType? sessionType,
  }) async {
    _requireSignIn();
    _log('createClass(school: $schoolId, year: $schoolYear, name: $className, grade $gradeLevel, '
        '${program?.value ?? 'mixed'}, tutor: $tutorId)');
    _requireManager();
    _requireOwnSchool(schoolId);
    _checkGrade(gradeLevel);
    final year = _year(schoolYear);
    final name = _name(className);
    await _checkName(schoolId, year, name, null);
    tutorId = _blankToNull(tutorId);
    if (tutorId != null) await _checkTutor(tutorId, schoolId);
    return _write(() => _classes.insert(AralClass(
          schoolId: schoolId,
          schoolYear: year,
          className: name,
          gradeLevel: gradeLevel,
          program: program,
          tutorId: tutorId,
          room: _blankToNull(room),
          schedule: _blankToNull(schedule),
          notes: _blankToNull(notes),
          sessionType: sessionType,
          createdBy: _auth.currentUser?.id,
        )));
  }

  /// The memo-style name for the next class of Grade [grade] (Division
  /// Memorandum 180 s. 2026): `ARAL-R-G<grade>-<nn>`, one more than the
  /// highest number of that grade at the school that year (names compared
  /// ignoring case; a deleted class's number is never given again). Names
  /// stay free text: this is only a suggestion.
  Future<String> suggestClassName({required int schoolId, required String schoolYear, required int grade}) async {
    _requireSignIn();
    _log('suggestClassName(school: $schoolId, year: $schoolYear, grade $grade)');
    _requireManager();
    _requireOwnSchool(schoolId);
    _checkGrade(grade);
    final pattern = RegExp('^ARAL-R-G$grade-(\\d+)\$', caseSensitive: false);
    var highest = 0;
    for (final c in await _classes.getBySchool(schoolId, schoolYear: _year(schoolYear))) {
      final n = int.tryParse(pattern.firstMatch(c.className.trim())?.group(1) ?? '') ?? 0;
      if (n > highest) highest = n;
    }
    return 'ARAL-R-G$grade-${(highest + 1).toString().padLeft(2, '0')}';
  }

  /// Saves a changed class: name, grade, program (null = mixed), tutor, room,
  /// schedule, notes. School and year never change; grade and program only
  /// while the class has no learners.
  Future<AralClass> editClass(AralClass changed) async {
    _requireSignIn();
    _log('editClass(${changed.id})');
    _requireManager();
    if (changed.id == null) throw const ViewModelException('Save the class first.');
    final current = await _require(changed.id!);
    if (changed.schoolId != current.schoolId || changed.schoolYear != current.schoolYear) {
      throw const ViewModelException('A class keeps its school and school year.');
    }
    final name = _name(changed.className);
    if (name.toLowerCase() != current.className.trim().toLowerCase()) {
      await _checkName(current.schoolId, current.schoolYear, name, current.id);
    }
    final tutorId = _blankToNull(changed.tutorId);
    if (tutorId != null && tutorId != current.tutorId) {
      await _checkTutor(tutorId, current.schoolId);
      await _checkAdviserTutor(current, tutorId);
    }
    _checkGrade(changed.gradeLevel);
    if ((changed.program != current.program || changed.gradeLevel != current.gradeLevel) &&
        (await _roster.getByClass(current.id!)).isNotEmpty) {
      throw ViewModelException("Class \"${current.className}\" has learners; its grade and program can't change.");
    }
    return _write(() => _classes.update(changed.copyWith(
          className: name,
          tutorId: () => tutorId,
          room: () => _blankToNull(changed.room),
          schedule: () => _blankToNull(changed.schedule),
          notes: () => _blankToNull(changed.notes),
        )));
  }

  Future<void> deleteClass(int classId) async {
    _requireSignIn();
    _log('deleteClass($classId)');
    _requireManager();
    final c = await _require(classId);
    // Sessions too (review C3): the device doesn't enforce foreign keys, and
    // the cloud refuses the delete of a class its sessions point at.
    if ((await _roster.getByClass(classId)).isNotEmpty || (await _sessions.getByClass(classId)).isNotEmpty) {
      throw ViewModelException("Class \"${c.className}\" still has learners or sessions; it can't be deleted.");
    }
    await _write(() => _classes.delete(classId));
  }

  // ---- helpers ----

  void _requireManager() {
    final role = _auth.currentUser?.role;
    if (role != UserRole.admin && role != UserRole.coordinator) {
      throw const ViewModelException('Not allowed: admin or coordinator only.');
    }
  }

  void _requireOwnSchool(int schoolId) {
    final mine = _auth.currentUser?.schoolId;
    if (mine != null && mine != schoolId) throw const ViewModelException('Not allowed: that school is not yours.');
  }

  /// The class, if the caller may change it (their school, or any for the
  /// superadmin).
  Future<AralClass> _require(int classId) async {
    final c = await _classes.findById(classId);
    if (c == null) throw ViewModelException(notOnDeviceMessage('ARAL class'));
    final mine = _auth.currentUser?.schoolId;
    if (mine != null && mine != c.schoolId) throw const ViewModelException('Not allowed: that class is in another school.');
    return c;
  }

  Future<AralEnrollment> _requireLearner(int enrollmentId) async {
    final e = await _roster.findById(enrollmentId);
    if (e == null) throw ViewModelException(notOnDeviceMessage('ARAL learner'));
    final mine = _auth.currentUser?.schoolId;
    if (mine != null && mine != e.schoolId) throw const ViewModelException('Not allowed: that learner is in another school.');
    return e;
  }

  /// The learner's grade (their section's) and "Last, First".
  Future<(int, String)> _gradeAndName(AralEnrollment e) async {
    final section = await _sections.getById(e.sectionId);
    final grade = int.tryParse(section?.gradeLevel ?? '') ?? 0;
    final s = (await _students.getBySection(e.sectionId)).where((s) => s.id == e.studentId).firstOrNull;
    return (grade, s == null ? 'Learner ${e.studentId}' : '${s.lastName}, ${s.firstName}');
  }

  // ---- Class progress (spec 2026-11-27 ARAL class tutor D2) ----

  final CrlaResultRepository _crlaResults;
  final PhilIriViewModel _philIri;

  /// Each learner placed in the class this school year (active and exited),
  /// by name: their ARAL starting round and profile, their latest round after
  /// it with a result of their own, and the change (profile step; the numbers
  /// beside it). Values follow the school's values_aral switch; the rows carry
  /// no carried/actual wording. [asOf] YYYY-MM-DD, default today. [atRound]
  /// (a CRLA or Phil-IRI round name; the progress trend, spec 2026-11-27 ARAL
  /// effectiveness D6): the change from the start to that round only; a round
  /// of the other instrument, or not after the start, is "not assessed yet".
  Future<List<AralLearnerProgress>> classProgress(int classId, {String? asOf, String? atRound}) async {
    _requireSignIn();
    _log('classProgress($classId${atRound == null ? '' : ', atRound: $atRound'})');
    final c = await _readable(classId);
    final day = asOf ?? calendarDate(DateTime.now());
    final values = await _philIri.valueSource(c.schoolId, PhilIriValueList.aral);
    final learnersOf = <int, Map<int, Student>>{};
    final out = <AralLearnerProgress>[];
    for (final e in await _roster.getByClass(classId)) {
      if (e.schoolYear != c.schoolYear) continue;
      final grade = int.tryParse((await _sections.getById(e.sectionId))?.gradeLevel ?? '');
      if (grade == null) continue;
      final st = (learnersOf[e.sectionId] ??= {
        for (final s in await _students.getBySection(e.sectionId)) s.id!: s,
      })[e.studentId];
      final name = st == null ? 'Learner ${e.studentId}' : '${st.lastName.toUpperCase()}, ${st.firstName}';
      out.add(grade <= 3
          ? await _crlaProgress(e, grade, name, day, atRound)
          : await _philIriProgress(e, grade, name, day, values, atRound));
    }
    out.sort((a, b) => a.learnerName.compareTo(b.learnerName));
    return out;
  }

  static AralProgressChange _change(int? start, int? latest) => start == null
      ? AralProgressChange.noStartingResult
      : latest == null
          ? AralProgressChange.notAssessedYet
          : latest > start
              ? AralProgressChange.up
              : latest < start
                  ? AralProgressChange.down
                  : AralProgressChange.same;

  Future<AralLearnerProgress> _crlaProgress(AralEnrollment e, int grade, String name, String day, String? atRound) async {
    final results = (await _crlaResults.getByStudent(e.studentId)).where((r) => r.schoolYear == e.schoolYear).toList();
    final start = CrlaRound.values.where((r) => r.name == e.basisRound).firstOrNull ??
        (grade == 1 ? CrlaRound.mosy : CrlaRound.bosy);
    CrlaResult? at(CrlaRound r) => aralCrlaLearnerResult(results, r, day, grade: grade);
    int? rank(CrlaResult? r) {
      final i = r == null ? -1 : aralCrlaProfileOrder.indexOf(r.readingProfile!);
      return i < 0 ? null : i;
    }

    AralProgressNumbers? numbers(CrlaResult? r) => r == null
        ? null
        : AralProgressNumbers(
            correctWordsPct: r.pctCorrectWordsRead == null ? null : r.pctCorrectWordsRead! * 100,
            wpm: r.wpm,
            comprehension: r.comprehensionCorrect?.toDouble());
    final s = at(start);
    CrlaRound? latestRound;
    CrlaResult? latest;
    for (final r in CrlaRound.values.where((r) => r.index > start.index && (atRound == null || r.name == atRound))) {
      final x = at(r);
      if (x != null) (latestRound, latest) = (r, x);
    }
    return AralLearnerProgress(
      enrollment: e,
      learnerName: name,
      grade: grade,
      instrument: AralLearnerProgress.crla,
      startRound: start.name,
      startProfile: s?.readingProfile,
      startNumbers: numbers(s),
      latestRound: latestRound?.name,
      latestProfile: latest?.readingProfile,
      latestNumbers: numbers(latest),
      latestAssessedOn: latest?.assessedAt.substring(0, 10),
      change: _change(rank(s), rank(latest)),
    );
  }

  /// Phil-IRI profile steps: Struggling / Non-Reader 0, Frustration 1,
  /// Instructional 2, Independent 3.
  static int? _philIriRank(PhilIriLevel? p) => switch (p) {
        PhilIriLevel.struggling || PhilIriLevel.nonReader => 0,
        PhilIriLevel.frustration => 1,
        PhilIriLevel.instructional => 2,
        PhilIriLevel.independent => 3,
        null => null,
      };

  Future<AralLearnerProgress> _philIriProgress(
      AralEnrollment e, int grade, String name, String day, PhilIriValues values, String? atRound) async {
    final res = await _philIri.reportResults(
        studentId: e.studentId, sectionId: e.sectionId, schoolYear: e.schoolYear, asOf: day);
    final start = PhilIriRound.values.where((r) => r.name == e.basisRound).firstOrNull ??
        (e.basisRound == 'mosy' ? PhilIriRound.mosy1 : PhilIriRound.bosy);
    // A round of the learner's own that is assessed (words read, time and
    // comprehension), as reminders and progress count it: a reading saved
    // with no answers or a comprehension-only import is not (final review I2).
    bool assessed(PhilIriRound r) => res.sessions.containsKey(r) && res.status(r) == PhilIriRoundStatus.assessed;
    // The start: under carried the round's counted result (a GST-only BOSY
    // counts), under actual an assessed round only (never the stand-in).
    final startHas = values == PhilIriValues.carried ? res.counted.contains(start) : assessed(start);
    final s = startHas ? res.view(start, values) : null;
    // The latest: an assessed round after the start, whatever the values.
    PhilIriRound? latestRound;
    for (final r in PhilIriRound.values.where((r) => r.index > start.index && (atRound == null || r.name == atRound))) {
      if (assessed(r)) latestRound = r;
    }
    final latest = latestRound == null ? null : res.view(latestRound, values);
    AralProgressNumbers? numbers(PhilIriRoundView? v) => v == null
        ? null
        : AralProgressNumbers(
            // Phil-IRI keeps scores as fractions; the progress row shows %.
            correctWordsPct: v.wordReadingScore == null ? null : v.wordReadingScore! * 100,
            wpm: v.wordsPerMinute,
            comprehension: v.comprehensionScore == null ? null : v.comprehensionScore! * 100);
    return AralLearnerProgress(
      enrollment: e,
      learnerName: name,
      grade: grade,
      instrument: AralLearnerProgress.philIri,
      startRound: start.name,
      startProfile: s?.profile?.label,
      startNumbers: numbers(s),
      latestRound: latestRound?.name,
      latestProfile: latest?.profile?.label,
      latestNumbers: numbers(latest),
      latestAssessedOn: latestRound == null ? null : res.sessions[latestRound]!.assessedAt.substring(0, 10),
      change: _change(_philIriRank(s?.profile), _philIriRank(latest?.profile)),
    );
  }

  // ---- No improvement (spec 2026-11-27 ARAL effectiveness D2-D4) ----

  final AralCheckinViewModel _checkins;

  /// The class's learners active on [asOf] (YYYY-MM-DD, default today) who
  /// are not improving, by name, each with their reasons
  /// (`aralNoImprovementReasons`): same or down since their ARAL start after
  /// the school's first check-in number of sessions attended (present, in any
  /// class, on or before the latest round), or their latest complete check-in
  /// by then below the pass mark. Nothing is stored: a newer round going up,
  /// a passed check-in or an exit clears it.
  Future<List<AralNoImprovement>> noImprovement(int classId, {String? asOf}) async {
    _requireSignIn();
    _log('noImprovement($classId)');
    final c = await _readable(classId);
    final day = asOf ?? calendarDate(DateTime.now());
    final after = (await aralLocalRuleSettings(_localSettings, c.schoolId)).checkinAfterSessions;
    // The class's own sessions in one read; a session of an earlier class (a
    // moved learner) is looked up once when met (final review I2: speed).
    final heldOn = <int, String?>{for (final s in await _sessions.getByClass(classId)) s.id!: s.heldOn};
    final out = <AralNoImprovement>[];
    for (final p in await classProgress(classId, asOf: day)) {
      if (!aralActiveOn(p.enrollment, day)) continue;
      var attended = 0;
      final latestOn = p.latestAssessedOn;
      if (latestOn != null) {
        for (final a in await _sessions.getAttendanceForEnrollment(p.enrollment.id!)) {
          if (a.mark != AralMark.present) continue;
          final held = heldOn.containsKey(a.sessionId)
              ? heldOn[a.sessionId]
              : (heldOn[a.sessionId] = (await _sessions.findSession(a.sessionId))?.heldOn);
          if (held != null && held.compareTo(latestOn) <= 0) attended++;
        }
      }
      final checkins = await _checkins.learnerCheckins(p.enrollment.id!);
      // The latest of the complete ones: an unfinished retake doesn't hide a
      // failed check-in (final review I1).
      final latest = aralLatestCheckin(
          checkins.results.where((r) => r.complete && r.checkin.takenOn.compareTo(day) <= 0));
      final reasons = aralNoImprovementReasons(p,
          attendedBeforeLatest: attended,
          minAttended: after.first,
          latestCheckin: latest == null
              ? null
              : AralCheckinOutcome(
                  afterSession: after[aralCheckinCheckpoints.indexOf(latest.tool.checkpoint)],
                  score: latest.score,
                  passPct: latest.passPct,
                  complete: latest.complete));
      if (reasons.isNotEmpty) out.add(AralNoImprovement(p, reasons));
    }
    return out;
  }

  Future<AralClass> _readable(int classId) async {
    final me = _auth.currentUser!;
    if (me.role != UserRole.tutor) return _require(classId);
    final c = await _classes.findById(classId);
    if (c == null || c.tutorId != me.id) {
      // A tutor's device holds only their own classes; don't tell apart
      // "missing" and "someone else's".
      throw const ViewModelException('This ARAL class is not one of your classes.');
    }
    return c;
  }

  Future<void> _checkName(int schoolId, String schoolYear, String name, int? exceptId) async {
    final key = name.toLowerCase();
    for (final c in await _classes.getBySchool(schoolId, schoolYear: schoolYear)) {
      if (c.id != exceptId && c.className.trim().toLowerCase() == key) {
        throw ViewModelException('A class named "$name" already exists for $schoolYear.');
      }
    }
  }

  Future<void> _checkTutor(String tutorId, int schoolId) async {
    final u = await _users.getById(tutorId);
    if (u == null || u.role != UserRole.tutor || !u.isActive || u.schoolId != schoolId) {
      throw const ViewModelException('The class tutor must be an active tutor of the school.');
    }
  }

  /// With the school's advisers not tutoring their own learners: [tutorId]
  /// must not advise the section of one of [c]'s active learners.
  Future<void> _checkAdviserTutor(AralClass c, String tutorId) async {
    if ((await aralLocalRuleSettings(_localSettings, c.schoolId)).adviserTutorsOwnClass) return;
    for (final e in (await _roster.getByClass(c.id!)).where((e) => e.isActive)) {
      final section = await _sections.getById(e.sectionId);
      if (section?.adviserUserId == tutorId) {
        final (_, name) = await _gradeAndName(e);
        throw ViewModelException('The new tutor is the adviser of $name (${section!.sectionName}): '
            'an adviser does not tutor their own learners at this school.');
      }
    }
  }

  static void _checkGrade(int grade) {
    if (grade < 1 || grade > 10) throw const ViewModelException('ARAL-Reading classes are for Grades 1-10.');
  }

  static String _name(String raw) {
    final name = raw.trim();
    if (name.isEmpty) throw const ViewModelException('A class needs a name.');
    return name;
  }

  static String _year(String raw) {
    try {
      return normalizeSchoolYear(raw);
    } on FormatException catch (e) {
      throw ViewModelException(e.message);
    }
  }

  Future<T> _write<T>(Future<T> Function() write) async {
    try {
      return await write();
    } catch (e) {
      // A record waiting in an upload (sync): say so, whatever else the
      // statement's text happens to contain.
      if ('$e'.contains(pendingLockMessage)) throw const ViewModelException(pendingLockMessage);
      final text = e.toString();
      if (text.contains('aral_classes_name_key')) {
        throw const ViewModelException('A class with that name already exists for that school year.');
      }
      final full = aralClassFullDbRefusal(text);
      if (full != null) throw ViewModelException(full);
      for (final refusal in _dbRefusals) {
        if (text.toLowerCase().contains(refusal.toLowerCase())) throw ViewModelException('$refusal.');
      }
      _log('write failed: $e');
      rethrow;
    }
  }

  static String? _blankToNull(String? s) => s == null || s.trim().isEmpty ? null : s.trim();
}
