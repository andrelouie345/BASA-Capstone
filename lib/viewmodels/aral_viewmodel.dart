// lib/viewmodels/aral_viewmodel.dart
//
// ARAL-Reading roster (pieces A1b, A1c). Offline-first: reads and writes the
// local copy (CRLA and Phil-IRI results, the roster), like the assessment
// ViewModels.
//
// Owner decisions (2026-10-15, revised with the reading coordinator):
//  * BASA proposes who enters ARAL and in which program (aral_rules.dart):
//    every learner below grade level, weakest first (no cap per section since
//    the ARAL classes, 2026-10-24). The coordinator confirms and may change a
//    learner's program; the suggestion is stored beside the choice. Learners
//    with no result yet can be added by hand; learners at or above grade level
//    cannot. A teacher may refer a learner (refer: who and why, the program
//    picked by hand); a referred learner exits only grade-level ready.
//  * Admins and coordinators manage the roster; tutors only read it.
//  * Grade-level-ready exits come from results (applyResults), never from
//    the coordinator; so do KS1 classroom-support exits (DepEd Memorandum 064,
//    owner 2026-10-23); transfers, drop-outs and classroom support are also
//    recorded by hand.
//  * applyResults (A4): a learner's latest finished result updates the
//    program when it suggests a different one than the stored suggestion,
//    and exits a learner who reads at grade level. The UI runs it when an
//    admin/coordinator opens the roster (owner, 2026-10-16).
//  * ARAL classes (spec docs/superpowers/specs/2026-10-23-aral-classes-design.md):
//    a learner sits in at most one class; their tutor is the class's tutor.
//    Enrolling and placing are two steps: a full or unsuitable class never
//    blocks an enrolment, the learner waits for a class (lastWarning says so).
//    Placing and moving learners is AralClassViewModel's.
import '../core/console/logger.dart';
import '../core/models/aral_class.dart';
import '../core/models/aral_enrollment.dart';
import '../core/models/crla_result.dart';
import '../core/models/phil_iri_assessment.dart' show PhilIriRound;
import '../core/models/section.dart';
import '../core/models/student.dart';
import '../core/models/user.dart';
import '../core/models/user_role.dart';
import '../core/repositories/aral_class_repository.dart';
import '../core/repositories/aral_enrollment_repository.dart';
import '../core/repositories/aral_setting_repository.dart';
import '../core/repositories/crla_result_repository.dart';
import '../core/repositories/section_repository.dart';
import '../core/repositories/student_repository.dart';
import '../core/repositories/user_repository.dart';
import '../core/services/aral_rules.dart';
import '../core/services/csv.dart';
import '../core/services/crla_rules.dart' show crlaAtGradeLevel;
import '../core/services/phil_iri_results.dart' show philIriNotAssessedResult;
import '../core/services/normalizers.dart';
import '../core/services/sync_upload_rules.dart' show pendingLockMessage;
import 'aral_class_viewmodel.dart' show aralPlacementRefusal, aralPlacementDbRefusals;
import 'auth_viewmodel.dart';
import 'phil_iri_viewmodel.dart';
import '../core/services/auth_messages.dart';
import 'viewmodel_exception.dart';

enum AralCandidateStatus {
  /// Below grade level: BASA proposes it with [AralCandidate.suggestion].
  proposed,
  /// Reads at or above grade level: not ARAL.
  notQualified,
  /// No usable result in the basis round yet (can be added by hand).
  noResult,
  /// Already on the roster for that school year.
  enrolled,
}

/// One learner of a section, as the proposal sees them.
class AralCandidate {
  final Student student;
  final int grade;
  final AralCandidateStatus status;
  final String reason;
  final AralPlacement? suggestion;
  /// Position among the section's qualifying learners (1 = weakest reader);
  /// equal results share a rank. Null when not qualifying or already enrolled.
  final int? rank;
  final AralRankKey? rankKey;
  final AralBasisSource? basisSource;
  final String? basisRound;
  final String? basisLevel;
  final int? basisAssessmentId;
  final AralEnrollment? enrollment;

  const AralCandidate({
    required this.student,
    required this.grade,
    required this.status,
    required this.reason,
    this.suggestion,
    this.rank,
    this.rankKey,
    this.basisSource,
    this.basisRound,
    this.basisLevel,
    this.basisAssessmentId,
    this.enrollment,
  });

  String get name => '${student.lastName}, ${student.firstName}';

  AralCandidate _seated(AralCandidateStatus status, int rank) => AralCandidate(
        student: student,
        grade: grade,
        status: status,
        reason: reason,
        suggestion: suggestion,
        rank: rank,
        rankKey: rankKey,
        basisSource: basisSource,
        basisRound: basisRound,
        basisLevel: basisLevel,
        basisAssessmentId: basisAssessmentId,
      );
}

enum AralUpdateKind {
  /// The result suggests another program: the placement follows it.
  programChanged,
  /// The learner reads at grade level: exited grade-level ready.
  exited,
  /// A newer result with the same suggestion: only its source is recorded.
  refreshed,
  /// Nothing new.
  unchanged,
  /// No finished result yet.
  noResult,
  // Notices for the coordinator (no write; before == after):
  /// The learner's program differs from their (one-program) class's: move them.
  programMismatch,
  /// The learner's grade differs from their class's (placed with other-grade,
  /// or their grade changed since; G4).
  otherGrade,
  /// The learner waits for a class.
  unplaced,
  /// The learner's SF1 section changed inside the school: aral-move.
  otherSection,
  /// The learner has no active enrollment in the school any more: aral-exit.
  leftSchool,
}

/// What applyResults did for one active ARAL learner.
class AralUpdate {
  final AralEnrollment before;
  final AralEnrollment after;
  final AralUpdateKind kind;
  final String reason;
  const AralUpdate(this.before, this.after, this.kind, this.reason);
}

/// A learner's latest finished result, as the roster sees it.
class _LatestResult {
  final String round;
  final String level;             // e.g. 'frustration', 'Low Emerging Reader'
  final int? assessmentId;
  final String date;              // YYYY-MM-DD
  /// Why the learner leaves when [placement] is null.
  final AralExitReason exitReason;
  final AralPlacement? placement; // null = leaves ARAL (at or above grade level, or KS1 classroom support)
  final String label;
  const _LatestResult(this.round, this.level, this.assessmentId, this.date, this.exitReason, this.placement, this.label);

  /// The same result for a learner who stays in ARAL with [p].
  _LatestResult staying(AralPlacement p) =>
      _LatestResult(round, level, assessmentId, date, exitReason, p, '$label; referred, so they stay');
}

class AralViewModel {
  static const _dbRefusals = [
    'No such section',
    'ARAL-Reading is for Grade 1-10 sections only',
    'Section does not belong to that school',
    'Learner has no active enrollment in this section for that school year',
    'Learner has no enrollment in this section for that school year',
    'A new ARAL enrollment starts active',
    'An ARAL enrollment keeps its learner, school, year and basis; only the placement, class, status and notes change',
    ...aralPlacementDbRefusals,
  ];

  final ScopedLogger _log;
  final AuthViewModel _auth;
  final AralEnrollmentRepository _roster;
  final AralClassRepository _classes;
  final SectionRepository _sections;
  final StudentRepository _students;
  final UserRepository _users;
  final CrlaResultRepository _crlaResults;
  final PhilIriViewModel _philIri;
  final AralSettingRepository _localSettings;

  /// A non-blocking notice from the last write (e.g. learners enrolled
  /// without a class because the class was full). Every roster write clears
  /// it first; reads leave it alone.
  String? lastWarning;

  AralViewModel({
    required AuthViewModel auth,
    required AralEnrollmentRepository roster,
    required AralClassRepository classes,
    required SectionRepository sections,
    required StudentRepository students,
    required UserRepository users,
    required CrlaResultRepository crlaResults,
    required PhilIriViewModel philIri,
    required AralSettingRepository localSettings,
    Logger? logger,
  })  : _auth = auth,
        _roster = roster,
        _classes = classes,
        _sections = sections,
        _students = students,
        _users = users,
        _crlaResults = crlaResults,
        _philIri = philIri,
        _localSettings = localSettings,
        _log = ScopedLogger(logger, 'AralViewModel');

  /// Every public method starts here: signed in, online or offline. Screens
  /// call this ViewModel directly, so the console's own check is not enough.
  void _requireSignIn() {
    final error = _auth.requireActiveSession();
    if (error != null) throw ViewModelException(error);
  }

  // ---- Proposal ----

  /// Every actively enrolled learner of the section with BASA's proposal:
  /// learners below grade level are proposed, ranked weakest first.
  Future<List<AralCandidate>> propose({required int sectionId, required String schoolYear}) async {
    _requireSignIn();
    _log('propose(sectionId: $sectionId, year: $schoolYear)');
    schoolYear = normalizeSchoolYear(schoolYear);
    final (section, grade) = await _aralSection(sectionId, schoolYear);
    final learners = await _students.getBySection(section.id!);
    final sectionRoster = await _roster.getBySection(section.id!, schoolYear: schoolYear);
    final enrolled = {for (final e in sectionRoster) e.studentId: e};
    final crla = grade <= 3 ? await _crlaResults.getBySection(section.id!, schoolYear: schoolYear) : const <CrlaResult>[];
    final program = await programSettings(section.schoolId);

    final out = <AralCandidate>[];
    for (final s in learners) {
      final existing = enrolled[s.id] ?? await _roster.findForStudent(s.id!, schoolYear);
      if (existing != null) {
        out.add(AralCandidate(
          student: s,
          grade: grade,
          status: AralCandidateStatus.enrolled,
          reason: 'In ARAL (${existing.programLabel}, ${existing.status.name})',
          enrollment: existing,
        ));
        continue;
      }
      out.add(grade <= 3
          ? _crlaCandidate(s, grade, crla.where((r) => r.studentId == s.id).toList(), program.ks1Extended)
          : await _philIriCandidate(s, grade, section.id!, schoolYear, program.foundationalProgram));
    }

    // Every qualifying learner is proposed; the ranking says who is weakest.
    final qualifying = [
      for (var i = 0; i < out.length; i++)
        if (out[i].status == AralCandidateStatus.proposed) i,
    ];
    final picks = aralPickSeats([for (final i in qualifying) out[i].rankKey!], qualifying.length);
    for (var q = 0; q < qualifying.length; q++) {
      out[qualifying[q]] = out[qualifying[q]]._seated(AralCandidateStatus.proposed, picks[q].rank);
    }
    return out;
  }

  AralCandidate _crlaCandidate(Student s, int grade, List<CrlaResult> results, bool extended) {
    final round = aralCrlaBasisRound(grade);
    // The grade's CRLA language only (G1 MT else Filipino, G2 Filipino, G3
    // English), its latest attempt with a profile in the basis round.
    final scored = results.where((r) => r.round == round && r.readingProfile != null).toList();
    final variant = aralCrlaBasisVariant(grade, scored.map((r) => r.subjectVariant).toSet());
    CrlaResult? basis;
    for (final r in scored.where((r) => r.subjectVariant == variant)) {
      if (basis == null || r.attemptNo > basis.attemptNo) basis = r;
    }
    if (basis == null) {
      final other = results.any((r) => r.readingProfile != null);
      return AralCandidate(
        student: s,
        grade: grade,
        status: AralCandidateStatus.noResult,
        reason: 'No CRLA ${round.label} result in ${_crlaVariantLabel(variant)} yet'
            '${other ? ' (has results in another round or language)' : ''}',
      );
    }
    final profile = basis.readingProfile!;
    final qualifies = aralCrlaQualifies(profile, extended: extended);
    final key = AralRankKey.crla(
      pctCorrectWordsRead: basis.pctCorrectWordsRead,
      comprehensionCorrect: basis.comprehensionCorrect,
      wpm: basis.wpm,
    );
    return AralCandidate(
      student: s,
      grade: grade,
      status: qualifies ? AralCandidateStatus.proposed : AralCandidateStatus.notQualified,
      reason: 'CRLA ${round.label} ${_crlaVariantLabel(variant)}: $profile${qualifies ? '' : _notAralCrla(profile)} '
          '(${_pct(key.wordRecognition)} words correct, comprehension ${basis.comprehensionCorrect ?? '-'}, '
          '${_wpm(basis.wpm)})',
      suggestion: qualifies ? aralCrlaPlacement : null,
      rankKey: qualifies ? key : null,
      basisSource: AralBasisSource.crla,
      basisRound: round.name,
      basisLevel: profile,
      basisAssessmentId: basis.assessmentId,
    );
  }

  Future<AralCandidate> _philIriCandidate(
      Student s, int grade, int sectionId, String schoolYear, bool foundationalProgram) async {
    // As reports count it: finished sessions only; the GST carries into BOSY.
    final results = await _philIri.reportResults(studentId: s.id!, sectionId: sectionId, schoolYear: schoolYear);
    if (results.notAssessed) {
      // Not assessed at all (no reading; no GST or a GST of 0): ARAL counts the learner as
      // Frustration, exactly 3 levels down, ranked weakest (reading
      // coordinator 2026-10-16), so assessing them is what moves them out.
      final assumed = philIriNotAssessedResult(PhilIriRound.bosy, grade);
      final placement = aralPhilIriPlacement(
          adjustedLevel: assumed.adjustedLevel!, grade: grade, foundationalProgram: foundationalProgram);
      return AralCandidate(
        student: s,
        grade: grade,
        status: AralCandidateStatus.proposed,
        reason: 'Not assessed: counted as Frustration, 3 levels down (Grade ${assumed.adjustedLevel}); '
            'give the Phil-IRI to place them on a real result',
        suggestion: placement,
        rankKey: const AralRankKey(0, 0, 0),
        basisSource: AralBasisSource.philIri,
        basisRound: PhilIriRound.bosy.name,
        basisLevel: aralNotAssessedLevel,
      );
    }
    final bosy = results.round(PhilIriRound.bosy);
    if (!results.counted.contains(PhilIriRound.bosy) || bosy.profile == null || bosy.adjustedLevel == null) {
      return AralCandidate(
        student: s,
        grade: grade,
        status: AralCandidateStatus.noResult,
        reason: 'No finished Phil-IRI BOSY yet (only later rounds)',
      );
    }
    final gstOnly = results.sessions[PhilIriRound.bosy] == null;
    final adjusted = bosy.adjustedLevel!;
    final placement =
        aralPhilIriPlacement(adjustedLevel: adjusted, grade: grade, foundationalProgram: foundationalProgram);
    final key = AralRankKey.philIri(bosy);
    final level = adjusted == 0 ? 'non-reader' : 'reads at Grade $adjusted';
    final scores = '${gstOnly ? 'no reading' : 'word reading ${_pct(key.wordRecognition)}'}, comprehension '
        '${bosy.comprehensionBlank ? '-' : _pct(key.comprehension)}, ${_wpm(bosy.wordsPerMinute)}';
    return AralCandidate(
      student: s,
      grade: grade,
      status: placement != null ? AralCandidateStatus.proposed : AralCandidateStatus.notQualified,
      reason: 'Phil-IRI BOSY${gstOnly ? ' (GST only)' : ''}: ${bosy.profile!.label}, $level'
          '${placement == null ? ' - ${aralNotAralLabel(adjusted, grade)}' : ''} ($scores)',
      suggestion: placement,
      rankKey: placement != null ? key : null,
      basisSource: AralBasisSource.philIri,
      basisRound: PhilIriRound.bosy.name,
      basisLevel: bosy.profile!.name,
      basisAssessmentId: results.sessions[PhilIriRound.bosy]?.id,
    );
  }

  /// The school's ARAL program settings on this device: defaults <- region <-
  /// school (the local mirror; pull-cloud refreshes it).
  Future<AralProgramSettings> programSettings(int schoolId) async {
    _requireSignIn();
    final region = await _localSettings.getRegion();
    final school = await _localSettings.getForSchool(schoolId);
    return AralProgramSettings.fromMap({...?region?.settings, ...?school?.settings});
  }

  Future<void> _checkFoundational(AralKeyStage keyStage, int schoolId) async {
    if (keyStage == AralKeyStage.foundational && !(await programSettings(schoolId)).foundationalProgram) {
      throw const ViewModelException('This school has no foundational literacy program (SHARP) switched on: '
          'learners reading at levels 0-1 go to KS1. The coordinator can switch the program on.');
    }
  }

  static String _pct(double fraction) => '${(fraction * 100).round()}%';
  static String _crlaVariantLabel(String variant) =>
      switch (variant) { 'mt' => 'Mother Tongue', 'fil' => 'Filipino', 'eng' => 'English', _ => variant };
  static String _notAralCrla(String profile) => profile == crlaAtGradeLevel
      ? ' (not ARAL)'
      : ' (not ARAL: regular class; the school\'s extended KS1 program is off)';
  static String _wpm(double? wpm) => wpm == null ? '- wpm' : '${wpm.round()} wpm';

  // ---- Roster changes (admin / coordinator) ----

  /// Puts one learner on the roster: a proposed learner, or one with no
  /// result yet (by hand, with [keyStage] and, for KS2/KS3, [track]). Without
  /// [keyStage]/[track] the proposal is used; giving them overrides it (the
  /// suggestion is still stored). With [classId] the learner is also placed in
  /// that class when it fits; otherwise they wait for a class (lastWarning).
  Future<AralEnrollment> enroll({
    required int sectionId,
    required String schoolYear,
    required int studentId,
    AralKeyStage? keyStage,
    AralTrack? track,
    int? classId,
    String? notes,
    DateTime? enteredOn,
  }) async {
    _requireSignIn();
    _log('enroll(student: $studentId, section: $sectionId, year: $schoolYear, ks: ${keyStage?.name}, '
        'track: ${track?.name}, class: $classId)');
    _requireManager();
    lastWarning = null;
    schoolYear = normalizeSchoolYear(schoolYear);
    final (section, _) = await _aralSection(sectionId, schoolYear);
    final cls = classId == null ? null : await _classOf(classId);
    final candidate =
        (await propose(sectionId: sectionId, schoolYear: schoolYear)).where((c) => c.student.id == studentId).firstOrNull;
    if (candidate == null) {
      throw ViewModelException('Learner $studentId has no active enrollment in section $sectionId.');
    }
    final (stored, refusal) = await _enrollCandidate(candidate, section, schoolYear, cls,
        keyStage: keyStage, track: track, notes: notes, enteredOn: enteredOn);
    if (refusal != null) _warn('$refusal ${candidate.name} is on the roster without a class.');
    return stored;
  }

  /// Stores the candidate; places them in [cls] when it takes them. Returns
  /// the stored enrollment and, when [cls] did not take them, why.
  Future<(AralEnrollment, String?)> _enrollCandidate(
    AralCandidate candidate,
    Section section,
    String schoolYear,
    AralClass? cls, {
    AralKeyStage? keyStage,
    AralTrack? track,
    String? notes,
    DateTime? enteredOn,
  }) async {
    switch (candidate.status) {
      case AralCandidateStatus.enrolled:
        throw ViewModelException('${candidate.name} is already on the ARAL roster for $schoolYear '
            '(${candidate.enrollment!.programLabel}).');
      case AralCandidateStatus.notQualified:
        throw ViewModelException('${candidate.name} is not for ARAL-Reading: ${candidate.reason}.');
      case AralCandidateStatus.proposed || AralCandidateStatus.noResult:
    }
    final suggestion = candidate.suggestion;
    final ks = keyStage ?? suggestion?.keyStage;
    if (ks == null) {
      throw ViewModelException('${candidate.name} has no result yet (${candidate.reason}); '
          'give the program (and the track for KS2/KS3) to add them by hand.');
    }
    final tr = keyStage == null && track == null ? suggestion?.track : track;
    _checkTrack(ks, tr);
    await _checkFoundational(ks, section.schoolId);

    final draft = AralEnrollment(
      studentId: candidate.student.id!,
      schoolId: section.schoolId,
      sectionId: section.id!,
      schoolYear: schoolYear,
      keyStage: ks,
      track: tr,
      enteredOn: _localDate(enteredOn ?? DateTime.now()),
      basisSource: candidate.basisSource ?? AralBasisSource.manual,
      basisRound: candidate.basisRound,
      basisLevel: candidate.basisLevel,
      basisAssessmentId: candidate.basisAssessmentId,
      suggestedKeyStage: suggestion?.keyStage,
      suggestedTrack: suggestion?.track,
      notes: _blankToNull(notes),
      createdBy: _auth.currentUser?.id,
    );
    return _insertPlaced(draft, cls, grade: candidate.grade, learner: candidate.name);
  }

  /// Inserts [draft], in [cls] when it takes the learner.
  Future<(AralEnrollment, String?)> _insertPlaced(AralEnrollment draft, AralClass? cls,
      {required int grade, required String learner}) async {
    // Another grade is never placed here: only the coordinator's
    // aral-class-place ... other-grade does that (G3).
    final refusal = cls == null ? null : await aralPlacementRefusal(_roster, cls, draft, grade: grade, learner: learner);
    final stored = await _write(() => _roster.insert(
        cls == null || refusal != null ? draft : draft.copyWith(classId: () => cls.id)));
    _log('enrolled ${stored.id} (${stored.programLabel}${stored.classId == null ? '' : ', class ${stored.classId}'})');
    return (stored, refusal?.$2);
  }

  /// Confirms every proposal of the section as suggested. With [classId] the
  /// weakest are placed in that class while it has room (15 active); the
  /// rest wait for a class and are named in lastWarning.
  Future<List<AralEnrollment>> enrollProposed({
    required int sectionId,
    required String schoolYear,
    int? classId,
  }) async {
    _requireSignIn();
    _log('enrollProposed(section: $sectionId, year: $schoolYear, class: $classId)');
    _requireManager();
    lastWarning = null;
    schoolYear = normalizeSchoolYear(schoolYear);
    final (section, _) = await _aralSection(sectionId, schoolYear);
    final cls = classId == null ? null : await _classOf(classId);
    final proposed = (await propose(sectionId: sectionId, schoolYear: schoolYear))
        .where((c) => c.status == AralCandidateStatus.proposed)
        .toList()
      ..sort((a, b) => a.rank!.compareTo(b.rank!)); // weakest first; stable for ties
    final created = <AralEnrollment>[];
    final waiting = <String>[];
    for (final c in proposed) {
      final (stored, refusal) = await _enrollCandidate(c, section, schoolYear, cls);
      created.add(stored);
      if (refusal != null) waiting.add('${c.name} (${c.student.id}): $refusal');
    }
    if (waiting.isNotEmpty) {
      _warn('${waiting.length} learner(s) are on the roster without a class; place them with aral-class-place:\n'
          '${waiting.map((w) => '  $w').join('\n')}');
    }
    return created;
  }

  /// A teacher's referral (spec decision 9): the learner joins ARAL whatever
  /// their results, in the program picked here, with who referred them and
  /// why. A referred learner exits only grade-level ready. With [classId]
  /// they are also placed when the class takes them.
  Future<AralEnrollment> refer({
    required int sectionId,
    required String schoolYear,
    required int studentId,
    required AralKeyStage keyStage,
    AralTrack? track,
    required String referredBy,
    required String reason,
    int? classId,
    String? notes,
    DateTime? enteredOn,
  }) async {
    _requireSignIn();
    _log('refer(student: $studentId, section: $sectionId, year: $schoolYear, ks: ${keyStage.name}, class: $classId)');
    _requireManager();
    lastWarning = null;
    final by = _blankToNull(referredBy), why = _blankToNull(reason);
    if (by == null || why == null) throw const ViewModelException('A referral needs who referred the learner and why.');
    schoolYear = normalizeSchoolYear(schoolYear);
    final (section, grade) = await _aralSection(sectionId, schoolYear);
    final cls = classId == null ? null : await _classOf(classId);
    final student = (await _students.getBySection(sectionId)).where((s) => s.id == studentId).firstOrNull;
    if (student == null) throw ViewModelException('Learner $studentId has no active enrollment in section $sectionId.');
    final name = '${student.lastName}, ${student.firstName}';
    final existing = await _roster.findForStudent(studentId, schoolYear);
    if (existing != null) {
      throw ViewModelException('$name is already on the ARAL roster for $schoolYear (${existing.programLabel}).');
    }
    _checkTrack(keyStage, track);
    await _checkFoundational(keyStage, section.schoolId);
    final (stored, refusal) = await _insertPlaced(
        AralEnrollment(
          studentId: studentId,
          schoolId: section.schoolId,
          sectionId: sectionId,
          schoolYear: schoolYear,
          keyStage: keyStage,
          track: track,
          enteredOn: _localDate(enteredOn ?? DateTime.now()),
          basisSource: AralBasisSource.referral,
          referredBy: by,
          referralReason: why,
          notes: _blankToNull(notes),
          createdBy: _auth.currentUser?.id,
        ),
        cls,
        grade: grade,
        learner: name);
    if (refusal != null) _warn('$refusal $name is on the roster without a class.');
    return stored;
  }

  /// Changes the program (Foundational and KS1 have no track; KS2/KS3 need
  /// one). Foundational only when the school runs a foundational literacy
  /// program (AralProgramSettings). The learner stays in their class (spec
  /// decision 7); aral-update then flags a class of another program.
  Future<AralEnrollment> setPlacement(int enrollmentId, AralKeyStage keyStage, AralTrack? track) async {
    _requireSignIn();
    _log('setPlacement($enrollmentId, ${keyStage.name}, ${track?.name})');
    _requireManager();
    lastWarning = null;
    final e = await _require(enrollmentId);
    _checkTrack(keyStage, track);
    await _checkFoundational(keyStage, e.schoolId);
    return _write(() => _roster.update(e.copyWith(keyStage: keyStage, track: () => track)));
  }

  /// Follows an SF1 section move inside the school (F9b): the roster entry
  /// takes the learner's current section. The class always stays (G4); when
  /// the new grade differs from the class's, lastWarning says so. A learner
  /// who left the school is exited as transferred out instead.
  Future<AralEnrollment> moveToSection(int enrollmentId) async {
    _requireSignIn();
    _log('moveToSection($enrollmentId)');
    _requireManager();
    lastWarning = null;
    final e = await _require(enrollmentId);
    final name = await _learnerName(e.studentId, e.sectionId);
    final now = await _students.activeSectionId(e.studentId, e.schoolYear);
    final section = now == null ? null : await _sections.getById(now);
    if (section == null || section.schoolId != e.schoolId) {
      throw ViewModelException('$name has left the school: exit them as transferred out '
          '(aral-exit ${e.id} transferred_out).');
    }
    if (section.id == e.sectionId) throw ViewModelException('$name is already in section ${e.sectionId}.');
    final (_, grade) = await _aralSection(section.id!, e.schoolYear);
    final moved = await _write(() => _roster.update(e.copyWith(sectionId: section.id)));
    final cls = e.classId == null ? null : await _classes.findById(e.classId!);
    if (cls != null && cls.gradeLevel != grade) {
      _warn('Grade $grade is now in class "${cls.className}" (Grade ${cls.gradeLevel}); '
          'move them if needed (aral-class-place).');
    }
    return moved;
  }

  /// Records that the learner left ARAL for an administrative reason
  /// (transferred out, dropped out, other) or for classroom-based remediation
  /// (classroom support). Grade-level-ready exits come from the learner's
  /// results, not from here. The learner stays linked to their class.
  Future<AralEnrollment> exit(int enrollmentId, AralExitReason reason, {DateTime? on}) async {
    _requireSignIn();
    _log('exit($enrollmentId, ${reason.value})');
    _requireManager();
    lastWarning = null;
    if (reason == AralExitReason.gradeLevelReady) {
      throw const ViewModelException(
          "A grade-level-ready exit is set by BASA from the learner's assessment results, not by hand.");
    }
    final e = await _require(enrollmentId);
    if (!e.isActive) throw ViewModelException('This learner already left ARAL on ${e.exitedOn}.');
    final date = _localDate(on ?? DateTime.now());
    if (date.compareTo(e.enteredOn) < 0) {
      throw ViewModelException('The exit date $date is before the learner entered ARAL (${e.enteredOn}).');
    }
    return _write(() => _roster.update(
        e.copyWith(status: AralStatus.exited, exitedOn: () => date, exitReason: () => reason)));
  }

  /// Undoes an administrative exit (e.g. recorded by mistake). A
  /// grade-level-ready exit stands: it follows the results. When their class
  /// can't take them back (full, or now of another program), the learner
  /// returns without a class (lastWarning). The grade is not re-checked: the
  /// learner was in that class already.
  Future<AralEnrollment> reactivate(int enrollmentId) async {
    _requireSignIn();
    _log('reactivate($enrollmentId)');
    _requireManager();
    lastWarning = null;
    final e = await _require(enrollmentId);
    if (e.isActive) throw const ViewModelException('This learner is already active in ARAL.');
    if (e.exitReason == AralExitReason.gradeLevelReady) {
      throw const ViewModelException(
          'This learner left ARAL grade-level ready, per their results; that exit is not undone by hand.');
    }
    var back = e.copyWith(status: AralStatus.active, exitedOn: () => null, exitReason: () => null);
    final cls = e.classId == null ? null : await _classes.findById(e.classId!);
    if (cls != null) {
      final section = await _sections.getById(e.sectionId);
      final grade = int.tryParse(section?.gradeLevel ?? '') ?? 0;
      final refusal = await aralPlacementRefusal(_roster, cls, back,
          grade: grade, learner: await _learnerName(e.studentId, e.sectionId), otherGradeOk: true);
      if (refusal != null) {
        back = back.copyWith(classId: () => null);
        _warn(refusal.$1 == AralPlacementProblem.full
            ? 'Class "${cls.className}" is full, so this learner is back without a class. '
                'Place them in a class (aral-class-place).'
            : '${refusal.$2} This learner is back without a class. Place them in a class (aral-class-place).');
      }
    }
    return _write(() => _roster.update(back));
  }

  Future<AralEnrollment> setNotes(int enrollmentId, String? notes) async {
    _requireSignIn();
    _log('setNotes($enrollmentId)');
    _requireManager();
    lastWarning = null;
    final e = await _require(enrollmentId);
    return _write(() => _roster.update(e.copyWith(notes: () => _blankToNull(notes))));
  }

  /// Removes a learner added by mistake. (Leaving ARAL is an exit instead.)
  Future<void> remove(int enrollmentId) async {
    _requireSignIn();
    _log('remove($enrollmentId)');
    _requireManager();
    lastWarning = null;
    await _require(enrollmentId);
    await _write(() => _roster.delete(enrollmentId));
  }

  // ---- Automatic updates from results (A4) ----

  /// Applies every active learner's latest finished result in the section:
  /// program changes and grade-level-ready exits. Safe to run any time
  /// (nothing changes when nothing new came in).
  Future<List<AralUpdate>> applyResults({required int sectionId, required String schoolYear}) async {
    _requireSignIn();
    _log('applyResults(section: $sectionId, year: $schoolYear)');
    _requireManager();
    lastWarning = null;
    schoolYear = normalizeSchoolYear(schoolYear);
    final (section, grade) = await _aralSection(sectionId, schoolYear);
    final active = (await _roster.getBySection(section.id!, schoolYear: schoolYear)).where((e) => e.isActive).toList();
    final crla = grade <= 3 ? await _crlaResults.getBySection(section.id!, schoolYear: schoolYear) : const <CrlaResult>[];
    final program = await programSettings(section.schoolId);
    final out = <AralUpdate>[];
    for (final e in active) {
      var latest = grade <= 3
          ? _latestCrla(crla.where((r) => r.studentId == e.studentId).toList(), grade, program.ks1Extended)
          : await _latestPhilIri(e, grade);
      // A referred learner exits only grade-level ready (spec decision 9).
      if (e.basisSource == AralBasisSource.referral &&
          latest != null &&
          latest.placement == null &&
          latest.exitReason == AralExitReason.classroomSupport) {
        latest = latest.staying(aralCrlaPlacement);
      }
      final update = await _apply(e, latest, program.foundationalProgram);
      out
        ..add(update)
        ..addAll(await _notices(update.after));
    }
    final changed = out.where((u) => u.kind == AralUpdateKind.programChanged || u.kind == AralUpdateKind.exited);
    _log('applyResults: ${changed.length} change(s) in section $sectionId');
    return out;
  }

  /// [applyResults] for every section of the school with active ARAL learners.
  Future<List<AralUpdate>> applySchoolResults({required int schoolId, required String schoolYear}) async {
    _requireSignIn();
    _log('applySchoolResults(school: $schoolId, year: $schoolYear)');
    _requireManager();
    final school = _auth.currentUser?.schoolId;
    if (school != null && school != schoolId) throw const ViewModelException('Forbidden: that school is not yours.');
    schoolYear = normalizeSchoolYear(schoolYear);
    final sections = (await _roster.getBySchool(schoolId, schoolYear: schoolYear))
        .where((e) => e.isActive)
        .map((e) => e.sectionId)
        .toSet();
    final out = <AralUpdate>[];
    for (final s in sections) {
      out.addAll(await applyResults(sectionId: s, schoolYear: schoolYear));
    }
    return out;
  }

  /// What the coordinator should look at for an active learner (no write):
  /// left the school, moved to another section, waiting for a class, or in a
  /// class of another program (one-program classes) or another grade.
  Future<List<AralUpdate>> _notices(AralEnrollment e) async {
    if (!e.isActive) return const [];
    AralUpdate notice(AralUpdateKind kind, String reason) => AralUpdate(e, e, kind, reason);
    final now = await _students.activeSectionId(e.studentId, e.schoolYear);
    final section = now == null ? null : await _sections.getById(now);
    final out = <AralUpdate>[];
    if (section == null || section.schoolId != e.schoolId) {
      out.add(notice(AralUpdateKind.leftSchool, 'left the school: aral-exit ${e.id} transferred_out'));
    } else if (section.id != e.sectionId) {
      out.add(notice(AralUpdateKind.otherSection,
          'now in section ${section.id} (G${section.gradeLevel} ${section.sectionName}): aral-move ${e.id}'));
    }
    if (e.classId == null) {
      out.add(notice(AralUpdateKind.unplaced, 'waiting for a class'));
    } else {
      final cls = await _classes.findById(e.classId!);
      final program = AralClassProgram.of(e.keyStage, e.track);
      if (cls != null && cls.program != null && cls.program != program) {
        out.add(notice(AralUpdateKind.programMismatch,
            'program now ${program.label}: move to a ${program.label} class '
            '(class "${cls.className}" is ${cls.program!.label})'));
      }
      final grade = int.tryParse((await _sections.getById(e.sectionId))?.gradeLevel ?? '');
      if (cls != null && grade != null && grade != cls.gradeLevel) {
        out.add(notice(AralUpdateKind.otherGrade, 'Grade $grade in class "${cls.className}" (Grade ${cls.gradeLevel})'));
      }
    }
    return out;
  }

  Future<AralUpdate> _apply(AralEnrollment e, _LatestResult? latest, bool foundationalOn) async {
    if (latest == null) {
      // Without a foundational literacy program there is no Foundational
      // program: such learners go to KS1 (reading coordinator 2026-10-18).
      if (!foundationalOn && e.keyStage == AralKeyStage.foundational) {
        final after = await _write(() => _roster.update(e.copyWith(keyStage: AralKeyStage.ks1, track: () => null)));
        return AralUpdate(e, after, AralUpdateKind.programChanged,
            'no finished result yet; the foundational literacy program is off: Foundational -> KS1');
      }
      return AralUpdate(e, e, AralUpdateKind.noResult, 'no finished result yet');
    }
    final sourceId = e.suggestionAssessmentId ?? e.basisAssessmentId;
    final sourceRound = e.suggestionRound ?? e.basisRound;
    final isNew = latest.assessmentId != sourceId || latest.round != sourceRound ||
        latest.level != (e.suggestionLevel ?? e.basisLevel);
    AralEnrollment withSource(AralEnrollment x) => x.copyWith(
          suggestionRound: () => latest.round,
          suggestionLevel: () => latest.level,
          suggestionAssessmentId: () => latest.assessmentId,
          suggestedOn: () => latest.date,
        );

    final p = latest.placement;
    if (p == null) {
      // Exit on the result's date (not before the learner entered): grade-level
      // ready, or (KS1 outside the extended program) with classroom support.
      final date = latest.date.compareTo(e.enteredOn) < 0 ? e.enteredOn : latest.date;
      final reason = latest.exitReason;
      final after = await _write(() => _roster.update(withSource(e).copyWith(
          status: AralStatus.exited, exitedOn: () => date, exitReason: () => reason)));
      final why = reason == AralExitReason.classroomSupport
          ? 'leaves ARAL with classroom support (the extended KS1 program is off)'
          : 'grade-level ready';
      return AralUpdate(e, after, AralUpdateKind.exited, '${latest.label}: $why, exited on $date');
    }
    final sameAsNow = p.keyStage == e.keyStage && p.track == e.track;
    if (!sameAsNow && (p.keyStage != e.suggestedKeyStage || p.track != e.suggestedTrack)) {
      final after = await _write(() => _roster.update(withSource(e).copyWith(
            keyStage: p.keyStage,
            track: () => p.track,
            suggestedKeyStage: () => p.keyStage,
            suggestedTrack: () => p.track,
          )));
      return AralUpdate(e, after, AralUpdateKind.programChanged, '${latest.label}: ${e.programLabel} -> ${p.label}');
    }
    if (sameAsNow && (p.keyStage != e.suggestedKeyStage || p.track != e.suggestedTrack)) {
      // Already in that program (e.g. placed by hand): only the suggestion is recorded.
      final after = await _write(() => _roster.update(withSource(e).copyWith(
            suggestedKeyStage: () => p.keyStage,
            suggestedTrack: () => p.track,
          )));
      return AralUpdate(e, after, AralUpdateKind.refreshed, '${latest.label}: suggests ${p.label}, already there');
    }
    if (isNew) {
      final after = await _write(() => _roster.update(withSource(e)));
      return AralUpdate(e, after, AralUpdateKind.refreshed, '${latest.label}: still suggests ${p.label}');
    }
    return AralUpdate(e, e, AralUpdateKind.unchanged, '${latest.label}: nothing new');
  }

  /// The latest finished Phil-IRI round (a session still in progress doesn't count).
  Future<_LatestResult?> _latestPhilIri(AralEnrollment e, int grade) async {
    // Carried result of the latest finished round (reports count the same);
    // a learner with nothing yet stays as placed.
    final res = await _philIri.reportResults(studentId: e.studentId, sectionId: e.sectionId, schoolYear: e.schoolYear);
    final r = res.latest(PhilIriRound.values);
    if (r == null || r.profile == null || r.adjustedLevel == null) return null;
    // A BOSY that only the GST stands for has no session: the GST's date.
    final session = res.sessions[r.round];
    final date = (session?.assessedAt ?? res.gst!.takenAt).substring(0, 10);
    final adjusted = r.adjustedLevel!;
    final level = adjusted == 0 ? 'non-reader' : 'reads at Grade $adjusted';
    return _LatestResult(r.round.name, r.profile!.name, session?.id, date,
        AralExitReason.gradeLevelReady,
        aralPhilIriPlacement(
            adjustedLevel: adjusted,
            grade: grade,
            foundationalProgram: (await programSettings(e.schoolId)).foundationalProgram),
        'Phil-IRI ${r.round.label}${session == null ? ' (GST)' : ''} ($level)');
  }

  /// The latest CRLA round with a profile in the grade's language
  /// (aralCrlaBasisVariant); within it the latest attempt. At grade level:
  /// exit grade-level ready. Developing/Transitioning outside the school's
  /// extended KS1 program: exit with classroom support (DepEd Memorandum 064,
  /// any round after entry, owner 2026-10-23). Otherwise KS1.
  _LatestResult? _latestCrla(List<CrlaResult> results, int grade, bool extended) {
    final scored = results.where((r) => r.readingProfile != null).toList();
    final variant = aralCrlaBasisVariant(grade, scored.map((r) => r.subjectVariant).toSet());
    final inLanguage = scored.where((r) => r.subjectVariant == variant).toList();
    if (inLanguage.isEmpty) return null;
    final round = inLanguage.map((r) => r.round).reduce((a, b) => a.index >= b.index ? a : b);
    CrlaResult? basis;
    for (final r in inLanguage.where((r) => r.round == round)) {
      if (basis == null || r.attemptNo > basis.attemptNo) basis = r;
    }
    final profile = basis!.readingProfile!;
    final stays = aralCrlaQualifies(profile, extended: extended);
    return _LatestResult(
        round.name,
        profile,
        basis.assessmentId,
        basis.assessedAt.substring(0, 10),
        profile == crlaAtGradeLevel ? AralExitReason.gradeLevelReady : AralExitReason.classroomSupport,
        stays ? aralCrlaPlacement : null,
        'CRLA ${round.label} ${_crlaVariantLabel(variant)} ($profile)');
  }

  // ---- Reading the roster ----

  Future<List<AralEnrollment>> roster({required int sectionId, String? schoolYear}) async {
    _requireSignIn();
    _log('roster(section: $sectionId, year: $schoolYear)');
    return _roster.getBySection(sectionId, schoolYear: schoolYear == null ? null : normalizeSchoolYear(schoolYear));
  }

  Future<List<AralEnrollment>> schoolRoster({required int schoolId, String? schoolYear}) async {
    _requireSignIn();
    _log('schoolRoster(school: $schoolId, year: $schoolYear)');
    return _roster.getBySchool(schoolId, schoolYear: schoolYear == null ? null : normalizeSchoolYear(schoolYear));
  }

  /// The signed-in tutor's ARAL learners (or [tutorId]'s, for a coordinator).
  Future<List<AralEnrollment>> tutorRoster({String? tutorId, String? schoolYear}) async {
    _requireSignIn();
    final id = tutorId ?? _auth.currentUser?.id;
    _log('tutorRoster(tutor: $id, year: $schoolYear)');
    if (id == null) throw const ViewModelException(notSignedInMessage);
    return _roster.getByTutor(id, schoolYear: schoolYear == null ? null : normalizeSchoolYear(schoolYear));
  }

  Future<AralEnrollment?> getEnrollment(int id) async {
    _requireSignIn();
    return _roster.findById(id);
  }

  /// The school's ARAL roster for [schoolYear] as CSV ([sectionId] narrows it
  /// to one section): one line per learner. Admins/coordinators only.
  Future<String> rosterCsv({required int schoolId, required String schoolYear, int? sectionId}) async {
    _requireSignIn();
    _log('rosterCsv(school: $schoolId, year: $schoolYear, section: $sectionId)');
    _requireManager();
    final mine = _auth.currentUser?.schoolId;
    if (mine != null && mine != schoolId) throw const ViewModelException('Forbidden: that school is not yours.');
    schoolYear = normalizeSchoolYear(schoolYear);
    final roster = (await _roster.getBySchool(schoolId, schoolYear: schoolYear))
        .where((e) => sectionId == null || e.sectionId == sectionId)
        .toList();
    final sections = <int, Section?>{};
    final students = <int, Student>{};
    final classes = {for (final c in await _classes.getBySchool(schoolId, schoolYear: schoolYear)) c.id!: c};
    final tutors = <String, User?>{};
    for (final c in classes.values) {
      if (c.tutorId != null && !tutors.containsKey(c.tutorId)) tutors[c.tutorId!] = await _users.getById(c.tutorId!);
    }
    for (final e in roster) {
      if (!sections.containsKey(e.sectionId)) {
        sections[e.sectionId] = await _sections.getById(e.sectionId);
        for (final s in await _students.getBySection(e.sectionId)) {
          students[s.id!] = s;
        }
      }
    }
    AralClass? cls(AralEnrollment e) => classes[e.classId];
    int grade(AralEnrollment e) => int.tryParse(sections[e.sectionId]?.gradeLevel ?? '') ?? 0;
    String name(AralEnrollment e) {
      final s = students[e.studentId];
      return s == null ? 'student ${e.studentId}' : '${s.lastName}, ${s.firstName}';
    }

    roster.sort((a, b) {
      final g = grade(a).compareTo(grade(b));
      if (g != 0) return g;
      final s = (sections[a.sectionId]?.sectionName ?? '').compareTo(sections[b.sectionId]?.sectionName ?? '');
      return s != 0 ? s : name(a).compareTo(name(b));
    });
    return csvTable([
      [
        'Grade', 'Section', 'LRN', 'Learner', 'Program', 'Status', 'Entered', 'Exited', 'Exit reason',
        'Class', 'Tutor', 'Basis', 'Basis round', 'Basis level', 'Referred by', 'Referral reason', 'BASA suggestion',
        'Notes', 'ARAL id',
      ],
      for (final e in roster)
        [
          grade(e), sections[e.sectionId]?.sectionName, students[e.studentId]?.lrn, name(e), e.programLabel,
          e.status.name, e.enteredOn, e.exitedOn, e.exitReason?.value,
          cls(e)?.className, tutors[cls(e)?.tutorId]?.fullName, e.basisSource.value, e.basisRound, e.basisLevel,
          e.referredBy, e.referralReason,
          e.suggestedKeyStage == null
              ? null
              : '${e.suggestedKeyStage!.label}${e.suggestedTrack == null ? '' : ' ${e.suggestedTrack!.label}'}',
          e.notes, e.id,
        ],
    ]);
  }

  /// The school's active tutors with how many ARAL classes each teaches in
  /// [schoolYear] and how many active learners those classes hold.
  Future<List<(User, int, int)>> tutors({required int schoolId, required String schoolYear}) async {
    _requireSignIn();
    _log('tutors(school: $schoolId, year: $schoolYear)');
    schoolYear = normalizeSchoolYear(schoolYear);
    final classes = await _classes.getBySchool(schoolId, schoolYear: schoolYear);
    final out = <(User, int, int)>[];
    for (final u in await _users.getAll()) {
      if (u.role != UserRole.tutor || !u.isActive || u.schoolId != schoolId) continue;
      final learners = (await _roster.getByTutor(u.id, schoolYear: schoolYear)).where((e) => e.isActive).length;
      out.add((u, classes.where((c) => c.tutorId == u.id).length, learners));
    }
    out.sort((a, b) => a.$1.fullName.compareTo(b.$1.fullName));
    return out;
  }

  /// The names of the school's ARAL classes on this device (every year), by id.
  Future<Map<int, String>> classNames(int schoolId) async {
    _requireSignIn();
    return {for (final c in await _classes.getBySchool(schoolId)) c.id!: c.className};
  }

  /// "Last, First" of the section's actively enrolled learners, by id.
  Future<Map<int, String>> learnerNames(int sectionId) async {
    _requireSignIn();
    return {
      for (final s in await _students.getBySection(sectionId)) s.id!: '${s.lastName}, ${s.firstName}',
    };
  }

  // ---- helpers ----

  void _requireManager() {
    final role = _auth.currentUser?.role;
    if (role != UserRole.admin && role != UserRole.coordinator) {
      throw const ViewModelException('Forbidden: only an admin or coordinator can change the ARAL roster.');
    }
  }

  Future<AralEnrollment> _require(int id) async {
    final e = await _roster.findById(id);
    if (e == null) throw ViewModelException('No ARAL enrollment with id $id.');
    final school = _auth.currentUser?.schoolId;
    if (school != null && school != e.schoolId) {
      throw const ViewModelException('Forbidden: that learner is in another school.');
    }
    return e;
  }

  /// The section and its grade; refuses anything outside Grades 1-10 or
  /// another school (for school-bound users).
  Future<(Section, int)> _aralSection(int sectionId, String schoolYear) async {
    final section = await _sections.getById(sectionId);
    if (section == null) throw ViewModelException('No section with id $sectionId.');
    final grade = int.tryParse(section.gradeLevel);
    if (grade == null || grade < 1 || grade > 10) {
      throw ViewModelException('ARAL-Reading is for Grade 1-10 sections only (section $sectionId is Grade ${section.gradeLevel}).');
    }
    if (section.schoolYear != schoolYear) {
      throw ViewModelException('Section $sectionId is for ${section.schoolYear}, not $schoolYear.');
    }
    final school = _auth.currentUser?.schoolId;
    if (school != null && school != section.schoolId) {
      throw const ViewModelException('Forbidden: that section is in another school.');
    }
    return (section, grade);
  }

  static void _checkTrack(AralKeyStage ks, AralTrack? track) {
    if (!ks.hasTrack && track != null) {
      throw ViewModelException('${ks.label} has no Basic/Plus track.');
    }
    if (ks.hasTrack && track == null) {
      throw ViewModelException('${ks.label} needs a track: basic (decoding) or plus (fluency and comprehension).');
    }
  }

  /// The class, if it is in the caller's school.
  Future<AralClass> _classOf(int classId) async {
    final c = await _classes.findById(classId);
    if (c == null) throw ViewModelException('No ARAL class with id $classId.');
    final school = _auth.currentUser?.schoolId;
    if (school != null && school != c.schoolId) throw const ViewModelException('Forbidden: that class is in another school.');
    return c;
  }

  Future<String> _learnerName(int studentId, int sectionId) async {
    final s = (await _students.getBySection(sectionId)).where((s) => s.id == studentId).firstOrNull;
    return s == null ? 'Learner $studentId' : '${s.lastName}, ${s.firstName}';
  }

  void _warn(String note) {
    lastWarning = lastWarning == null ? note : '$lastWarning\n$note';
    _log(note);
  }

  Future<T> _write<T>(Future<T> Function() write) async {
    try {
      return await write();
    } catch (e) {
      // A record waiting in an upload (sync): say so, whatever else the
      // statement's text happens to contain.
      if ('$e'.contains(pendingLockMessage)) throw const ViewModelException(pendingLockMessage);
      final text = e.toString();
      if (text.contains('UNIQUE constraint failed: aral_enrollments.student_id') ||
          text.contains('aral_enrollments_one_per_year')) {
        throw const ViewModelException('This learner is already on the ARAL roster for that school year.');
      }
      for (final refusal in _dbRefusals) {
        if (text.toLowerCase().contains(refusal.toLowerCase())) {
          throw ViewModelException(refusal.endsWith('.') ? refusal : '$refusal.');
        }
      }
      rethrow;
    }
  }

  static String? _blankToNull(String? s) => s == null || s.trim().isEmpty ? null : s.trim();

  static String _localDate(DateTime t) {
    final d = t.toLocal();
    return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
  }
}
