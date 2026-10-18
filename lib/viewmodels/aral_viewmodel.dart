// lib/viewmodels/aral_viewmodel.dart
//
// ARAL-Reading roster (pieces A1b, A1c). Offline-first: reads and writes the
// local copy (CRLA and Phil-IRI results, the roster), like the assessment
// ViewModels.
//
// Owner decisions (2026-10-15, revised with the reading coordinator):
//  * BASA proposes who enters ARAL and in which program (aral_rules.dart): the
//    lowest performers below grade level, at most 15 per section. The
//    coordinator confirms, picks among learners tied at the cut-off, and may
//    change a learner's program; the suggestion is stored beside the choice.
//    Learners with no result yet can be added by hand; learners at or above
//    grade level, or outranked by weaker readers, cannot.
//  * Admins and coordinators manage the roster; tutors only read it.
//  * Grade-level-ready exits come from results (applyResults), never from
//    the coordinator; transfers and drop-outs are recorded by hand.
//  * applyResults (A4): a learner's latest finished result updates the
//    program when it suggests a different one than the stored suggestion,
//    and exits a learner who reads at grade level. The UI runs it when an
//    admin/coordinator opens the roster (owner, 2026-10-16).
//  * A tutor's "special 15": more than 15 active ARAL learners is allowed but
//    warned about (lastWarning). A section's 15 is a hard limit.
import '../core/console/logger.dart';
import '../core/models/aral_enrollment.dart';
import '../core/models/crla_result.dart';
import '../core/models/phil_iri_assessment.dart' show PhilIriRound;
import '../core/models/section.dart';
import '../core/models/student.dart';
import '../core/models/user.dart';
import '../core/models/user_role.dart';
import '../core/repositories/aral_enrollment_repository.dart';
import '../core/repositories/crla_result_repository.dart';
import '../core/repositories/section_repository.dart';
import '../core/repositories/student_repository.dart';
import '../core/repositories/user_repository.dart';
import '../core/services/aral_rules.dart';
import '../core/services/csv.dart';
import '../core/services/crla_rules.dart' show crlaAtGradeLevel;
import '../core/services/phil_iri_results.dart' show philIriNotAssessedResult;
import '../core/services/normalizers.dart';
import 'auth_viewmodel.dart';
import 'phil_iri_viewmodel.dart';
import 'viewmodel_exception.dart';

/// Recommended maximum of active ARAL learners per tutor (DepEd 1:15).
const aralTutorLoad = 15;

enum AralCandidateStatus {
  /// Below grade level and within the section's free places: BASA proposes
  /// it with [AralCandidate.suggestion].
  proposed,
  /// Tied with others for the last free place(s): the coordinator picks.
  tied,
  /// Below grade level, but the free places go to weaker readers.
  overCap,
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
  final AralPlacement? placement; // null = at or above grade level
  final String label;
  const _LatestResult(this.round, this.level, this.assessmentId, this.date, this.placement, this.label);
}

class AralViewModel {
  static const _dbRefusals = [
    'No such section',
    'ARAL-Reading is for Grade 1-10 sections only',
    'Section does not belong to that school',
    'Learner has no active enrollment in this section for that school year',
    'Learner has no enrollment in this section for that school year',
    'A new ARAL enrollment starts active',
    "The ARAL tutor must be an active tutor of the learner's school",
    'An ARAL enrollment keeps its learner, school, year and basis; only the placement, tutor, status and notes change',
    'An ARAL section has at most 15 active learners',
  ];

  final ScopedLogger _log;
  final AuthViewModel _auth;
  final AralEnrollmentRepository _roster;
  final SectionRepository _sections;
  final StudentRepository _students;
  final UserRepository _users;
  final CrlaResultRepository _crlaResults;
  final PhilIriViewModel _philIri;

  /// A non-blocking notice from the last write (e.g. a tutor over 15 learners,
  /// or learners tied at the cut-off).
  String? lastWarning;

  AralViewModel({
    required AuthViewModel auth,
    required AralEnrollmentRepository roster,
    required SectionRepository sections,
    required StudentRepository students,
    required UserRepository users,
    required CrlaResultRepository crlaResults,
    required PhilIriViewModel philIri,
    Logger? logger,
  })  : _auth = auth,
        _roster = roster,
        _sections = sections,
        _students = students,
        _users = users,
        _crlaResults = crlaResults,
        _philIri = philIri,
        _log = ScopedLogger(logger, 'AralViewModel');

  // ---- Proposal ----

  /// Every actively enrolled learner of the section with BASA's proposal:
  /// learners below grade level are ranked weakest first, and the section's
  /// free places (15 minus its active ARAL learners) go down the ranking.
  Future<List<AralCandidate>> propose({required int sectionId, required String schoolYear}) async {
    _log('propose(sectionId: $sectionId, year: $schoolYear)');
    schoolYear = normalizeSchoolYear(schoolYear);
    final (section, grade) = await _aralSection(sectionId, schoolYear);
    final learners = await _students.getBySection(section.id!);
    final sectionRoster = await _roster.getBySection(section.id!, schoolYear: schoolYear);
    final enrolled = {for (final e in sectionRoster) e.studentId: e};
    final crla = grade <= 3 ? await _crlaResults.getBySection(section.id!, schoolYear: schoolYear) : const <CrlaResult>[];

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
          ? _crlaCandidate(s, grade, crla.where((r) => r.studentId == s.id).toList())
          : await _philIriCandidate(s, grade, section.id!, schoolYear));
    }

    // The qualifying learners (drafted as `proposed`) are ranked into the
    // free places.
    final seats = aralSectionCap - sectionRoster.where((e) => e.isActive).length;
    final qualifying = [
      for (var i = 0; i < out.length; i++)
        if (out[i].status == AralCandidateStatus.proposed) i,
    ];
    final picks = aralPickSeats([for (final i in qualifying) out[i].rankKey!], seats);
    for (var q = 0; q < qualifying.length; q++) {
      final pick = picks[q];
      out[qualifying[q]] = out[qualifying[q]]._seated(
        switch (pick.seat) {
          AralSeat.inside => AralCandidateStatus.proposed,
          AralSeat.tie => AralCandidateStatus.tied,
          AralSeat.out => AralCandidateStatus.overCap,
        },
        pick.rank,
      );
    }
    return out;
  }

  /// The section's free ARAL places in [schoolYear].
  Future<int> freePlaces({required int sectionId, required String schoolYear}) async {
    final active = (await _roster.getBySection(sectionId, schoolYear: normalizeSchoolYear(schoolYear)))
        .where((e) => e.isActive)
        .length;
    return active >= aralSectionCap ? 0 : aralSectionCap - active;
  }

  AralCandidate _crlaCandidate(Student s, int grade, List<CrlaResult> results) {
    final round = aralCrlaBasisRound(grade);
    // Latest attempt per variant in the basis round, then the weakest profile.
    final latest = <String, CrlaResult>{};
    for (final r in results.where((r) => r.round == round && r.readingProfile != null)) {
      final prev = latest[r.subjectVariant];
      if (prev == null || r.attemptNo > prev.attemptNo) latest[r.subjectVariant] = r;
    }
    if (latest.isEmpty) {
      final other = results.any((r) => r.readingProfile != null);
      return AralCandidate(
        student: s,
        grade: grade,
        status: AralCandidateStatus.noResult,
        reason: 'No CRLA ${round.label} result yet${other ? ' (has results in another round)' : ''}',
      );
    }
    CrlaResult? basis;
    for (final r in latest.values) {
      if (basis == null || aralWeakerCrlaProfile(r.readingProfile, basis.readingProfile) == r.readingProfile) basis = r;
    }
    final profile = basis!.readingProfile!;
    final qualifies = aralCrlaQualifies(profile);
    final key = AralRankKey.crla(
      pctCorrectWordsRead: basis.pctCorrectWordsRead,
      comprehensionCorrect: basis.comprehensionCorrect,
      wpm: basis.wpm,
    );
    return AralCandidate(
      student: s,
      grade: grade,
      status: qualifies ? AralCandidateStatus.proposed : AralCandidateStatus.notQualified,
      reason: 'CRLA ${round.label}: $profile${qualifies ? '' : ' (not ARAL)'} '
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

  Future<AralCandidate> _philIriCandidate(Student s, int grade, int sectionId, String schoolYear) async {
    // As reports count it: finished sessions only; the GST carries into BOSY.
    final results = await _philIri.reportResults(studentId: s.id!, sectionId: sectionId, schoolYear: schoolYear);
    if (results.notAssessed) {
      // Not assessed at all (no reading; no GST or a GST of 0): ARAL counts the learner as
      // Frustration, exactly 3 levels down, ranked weakest (reading
      // coordinator 2026-10-16), so assessing them is what moves them out.
      final assumed = philIriNotAssessedResult(PhilIriRound.bosy, grade);
      final placement = aralPhilIriPlacement(adjustedLevel: assumed.adjustedLevel!, grade: grade);
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
    final placement = aralPhilIriPlacement(adjustedLevel: adjusted, grade: grade);
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

  static String _pct(double fraction) => '${(fraction * 100).round()}%';
  static String _wpm(double? wpm) => wpm == null ? '- wpm' : '${wpm.round()} wpm';

  // ---- Roster changes (admin / coordinator) ----

  /// Puts one learner on the roster: a proposed learner, one tied at the
  /// cut-off (the coordinator's pick), or one with no result yet (by hand,
  /// with [keyStage] and, for KS2/KS3, [track]). Without [keyStage]/[track]
  /// the proposal is used; giving them overrides it (the suggestion is still
  /// stored).
  Future<AralEnrollment> enroll({
    required int sectionId,
    required String schoolYear,
    required int studentId,
    AralKeyStage? keyStage,
    AralTrack? track,
    String? tutorId,
    String? notes,
    DateTime? enteredOn,
  }) async {
    _log('enroll(student: $studentId, section: $sectionId, year: $schoolYear, ks: ${keyStage?.name}, '
        'track: ${track?.name}, tutor: $tutorId)');
    _requireManager();
    lastWarning = null;
    schoolYear = normalizeSchoolYear(schoolYear);
    final (section, _) = await _aralSection(sectionId, schoolYear);
    final candidate =
        (await propose(sectionId: sectionId, schoolYear: schoolYear)).where((c) => c.student.id == studentId).firstOrNull;
    if (candidate == null) {
      throw ViewModelException('Learner $studentId has no active enrollment in section $sectionId.');
    }
    final stored = await _enrollCandidate(candidate, section, schoolYear,
        keyStage: keyStage, track: track, tutorId: tutorId, notes: notes, enteredOn: enteredOn);
    if (tutorId != null) await _warnTutorLoad(tutorId, schoolYear);
    return stored;
  }

  Future<AralEnrollment> _enrollCandidate(
    AralCandidate candidate,
    Section section,
    String schoolYear, {
    AralKeyStage? keyStage,
    AralTrack? track,
    String? tutorId,
    String? notes,
    DateTime? enteredOn,
  }) async {
    switch (candidate.status) {
      case AralCandidateStatus.enrolled:
        throw ViewModelException('${candidate.name} is already on the ARAL roster for $schoolYear '
            '(${candidate.enrollment!.programLabel}).');
      case AralCandidateStatus.notQualified:
        throw ViewModelException('${candidate.name} is not for ARAL-Reading: ${candidate.reason}.');
      case AralCandidateStatus.overCap:
        throw ViewModelException("${candidate.name} is ranked #${candidate.rank}; the section's free ARAL places "
            'go to weaker readers first (at most $aralSectionCap per section).');
      case AralCandidateStatus.proposed || AralCandidateStatus.tied || AralCandidateStatus.noResult:
    }
    final suggestion = candidate.suggestion;
    final ks = keyStage ?? suggestion?.keyStage;
    if (ks == null) {
      throw ViewModelException('${candidate.name} has no result yet (${candidate.reason}); '
          'give the program (and the track for KS2/KS3) to add them by hand.');
    }
    final tr = keyStage == null && track == null ? suggestion?.track : track;
    _checkTrack(ks, tr);
    if (tutorId != null) await _checkTutor(tutorId, section.schoolId);
    if (await freePlaces(sectionId: section.id!, schoolYear: schoolYear) == 0) {
      throw ViewModelException('Section ${section.id} already has $aralSectionCap active ARAL learners.');
    }

    final stored = await _write(() => _roster.insert(AralEnrollment(
          studentId: candidate.student.id!,
          schoolId: section.schoolId,
          sectionId: section.id!,
          schoolYear: schoolYear,
          keyStage: ks,
          track: tr,
          tutorId: tutorId,
          enteredOn: _localDate(enteredOn ?? DateTime.now()),
          basisSource: candidate.basisSource ?? AralBasisSource.manual,
          basisRound: candidate.basisRound,
          basisLevel: candidate.basisLevel,
          basisAssessmentId: candidate.basisAssessmentId,
          suggestedKeyStage: suggestion?.keyStage,
          suggestedTrack: suggestion?.track,
          notes: _blankToNull(notes),
          createdBy: _auth.currentUser?.id,
        )));
    _log('enrolled ${stored.id} (${stored.programLabel})');
    return stored;
  }

  /// Confirms every proposal of the section as suggested (optionally with one
  /// tutor for all of them). Learners tied for the last place(s) are left for
  /// the coordinator to pick with [enroll] (named in lastWarning).
  Future<List<AralEnrollment>> enrollProposed({
    required int sectionId,
    required String schoolYear,
    String? tutorId,
  }) async {
    _log('enrollProposed(section: $sectionId, year: $schoolYear, tutor: $tutorId)');
    _requireManager();
    lastWarning = null;
    schoolYear = normalizeSchoolYear(schoolYear);
    final (section, _) = await _aralSection(sectionId, schoolYear);
    if (tutorId != null) await _checkTutor(tutorId, section.schoolId);
    final candidates = await propose(sectionId: sectionId, schoolYear: schoolYear);
    final created = <AralEnrollment>[];
    for (final c in candidates.where((c) => c.status == AralCandidateStatus.proposed)) {
      created.add(await _enrollCandidate(c, section, schoolYear, tutorId: tutorId));
    }
    if (tutorId != null && created.isNotEmpty) await _warnTutorLoad(tutorId, schoolYear);
    final tied = candidates.where((c) => c.status == AralCandidateStatus.tied).toList();
    if (tied.isNotEmpty) {
      final free = await freePlaces(sectionId: sectionId, schoolYear: schoolYear);
      final note = '${tied.length} learners are tied for the last $free place(s): '
          '${tied.map((c) => '${c.name} (${c.student.id})').join(', ')}. The coordinator picks (enroll).';
      lastWarning = lastWarning == null ? note : '$lastWarning\n$note';
      _log(note);
    }
    return created;
  }

  /// Changes the program (Foundational and KS1 have no track; KS2/KS3 need
  /// one). E.g. a school without a foundational literacy program puts its
  /// non-readers on KS1.
  Future<AralEnrollment> setPlacement(int enrollmentId, AralKeyStage keyStage, AralTrack? track) async {
    _log('setPlacement($enrollmentId, ${keyStage.name}, ${track?.name})');
    _requireManager();
    final e = await _require(enrollmentId);
    _checkTrack(keyStage, track);
    return _write(() => _roster.update(e.copyWith(keyStage: keyStage, track: () => track)));
  }

  /// Assigns (or with null removes) the learner's ARAL tutor.
  Future<AralEnrollment> assignTutor(int enrollmentId, String? tutorId) async {
    _log('assignTutor($enrollmentId, $tutorId)');
    _requireManager();
    lastWarning = null;
    final e = await _require(enrollmentId);
    if (tutorId != null) await _checkTutor(tutorId, e.schoolId);
    final stored = await _write(() => _roster.update(e.copyWith(tutorId: () => tutorId)));
    if (tutorId != null) await _warnTutorLoad(tutorId, e.schoolYear);
    return stored;
  }

  /// Records that the learner left ARAL for an administrative reason
  /// (transferred out, dropped out, other). Grade-level-ready exits come from
  /// the learner's results, not from here.
  Future<AralEnrollment> exit(int enrollmentId, AralExitReason reason, {DateTime? on}) async {
    _log('exit($enrollmentId, ${reason.value})');
    _requireManager();
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
  /// grade-level-ready exit stands: it follows the results.
  Future<AralEnrollment> reactivate(int enrollmentId) async {
    _log('reactivate($enrollmentId)');
    _requireManager();
    final e = await _require(enrollmentId);
    if (e.isActive) throw const ViewModelException('This learner is already active in ARAL.');
    if (e.exitReason == AralExitReason.gradeLevelReady) {
      throw const ViewModelException(
          'This learner left ARAL grade-level ready, per their results; that exit is not undone by hand.');
    }
    if (await freePlaces(sectionId: e.sectionId, schoolYear: e.schoolYear) == 0) {
      throw ViewModelException('Section ${e.sectionId} already has $aralSectionCap active ARAL learners.');
    }
    return _write(
        () => _roster.update(e.copyWith(status: AralStatus.active, exitedOn: () => null, exitReason: () => null)));
  }

  Future<AralEnrollment> setNotes(int enrollmentId, String? notes) async {
    _log('setNotes($enrollmentId)');
    _requireManager();
    final e = await _require(enrollmentId);
    return _write(() => _roster.update(e.copyWith(notes: () => _blankToNull(notes))));
  }

  /// Removes a learner added by mistake. (Leaving ARAL is an exit instead.)
  Future<void> remove(int enrollmentId) async {
    _log('remove($enrollmentId)');
    _requireManager();
    await _require(enrollmentId);
    await _write(() => _roster.delete(enrollmentId));
  }

  // ---- Automatic updates from results (A4) ----

  /// Applies every active learner's latest finished result in the section:
  /// program changes and grade-level-ready exits. Safe to run any time
  /// (nothing changes when nothing new came in).
  Future<List<AralUpdate>> applyResults({required int sectionId, required String schoolYear}) async {
    _log('applyResults(section: $sectionId, year: $schoolYear)');
    _requireManager();
    schoolYear = normalizeSchoolYear(schoolYear);
    final (section, grade) = await _aralSection(sectionId, schoolYear);
    final active = (await _roster.getBySection(section.id!, schoolYear: schoolYear)).where((e) => e.isActive).toList();
    final crla = grade <= 3 ? await _crlaResults.getBySection(section.id!, schoolYear: schoolYear) : const <CrlaResult>[];
    final out = <AralUpdate>[];
    for (final e in active) {
      final latest = grade <= 3
          ? _latestCrla(crla.where((r) => r.studentId == e.studentId).toList())
          : await _latestPhilIri(e, grade);
      out.add(await _apply(e, latest));
    }
    final changed = out.where((u) => u.kind == AralUpdateKind.programChanged || u.kind == AralUpdateKind.exited);
    _log('applyResults: ${changed.length} change(s) in section $sectionId');
    return out;
  }

  /// [applyResults] for every section of the school with active ARAL learners.
  Future<List<AralUpdate>> applySchoolResults({required int schoolId, required String schoolYear}) async {
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

  Future<AralUpdate> _apply(AralEnrollment e, _LatestResult? latest) async {
    if (latest == null) return AralUpdate(e, e, AralUpdateKind.noResult, 'no finished result yet');
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
      // Exit on the result's date (not before the learner entered).
      final date = latest.date.compareTo(e.enteredOn) < 0 ? e.enteredOn : latest.date;
      final after = await _write(() => _roster.update(withSource(e).copyWith(
          status: AralStatus.exited, exitedOn: () => date, exitReason: () => AralExitReason.gradeLevelReady)));
      return AralUpdate(e, after, AralUpdateKind.exited, '${latest.label}: grade-level ready, exited on $date');
    }
    if (p.keyStage != e.suggestedKeyStage || p.track != e.suggestedTrack) {
      final after = await _write(() => _roster.update(withSource(e).copyWith(
            keyStage: p.keyStage,
            track: () => p.track,
            suggestedKeyStage: () => p.keyStage,
            suggestedTrack: () => p.track,
          )));
      return AralUpdate(e, after, AralUpdateKind.programChanged, '${latest.label}: ${e.programLabel} -> ${p.label}');
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
        aralPhilIriPlacement(adjustedLevel: adjusted, grade: grade),
        'Phil-IRI ${r.round.label}${session == null ? ' (GST)' : ''} ($level)');
  }

  /// The latest CRLA round with a profile; within it the latest attempt per
  /// variant, then the weakest profile.
  _LatestResult? _latestCrla(List<CrlaResult> results) {
    final scored = results.where((r) => r.readingProfile != null).toList();
    if (scored.isEmpty) return null;
    final round = scored.map((r) => r.round).reduce((a, b) => a.index >= b.index ? a : b);
    final latest = <String, CrlaResult>{};
    for (final r in scored.where((r) => r.round == round)) {
      final prev = latest[r.subjectVariant];
      if (prev == null || r.attemptNo > prev.attemptNo) latest[r.subjectVariant] = r;
    }
    CrlaResult? basis;
    for (final r in latest.values) {
      if (basis == null || aralWeakerCrlaProfile(r.readingProfile, basis.readingProfile) == r.readingProfile) basis = r;
    }
    final profile = basis!.readingProfile!;
    return _LatestResult(round.name, profile, basis.assessmentId, basis.assessedAt.substring(0, 10),
        profile == crlaAtGradeLevel ? null : aralCrlaPlacement, 'CRLA ${round.label} ($profile)');
  }

  // ---- Reading the roster ----

  Future<List<AralEnrollment>> roster({required int sectionId, String? schoolYear}) async {
    _log('roster(section: $sectionId, year: $schoolYear)');
    return _roster.getBySection(sectionId, schoolYear: schoolYear == null ? null : normalizeSchoolYear(schoolYear));
  }

  Future<List<AralEnrollment>> schoolRoster({required int schoolId, String? schoolYear}) async {
    _log('schoolRoster(school: $schoolId, year: $schoolYear)');
    return _roster.getBySchool(schoolId, schoolYear: schoolYear == null ? null : normalizeSchoolYear(schoolYear));
  }

  /// The signed-in tutor's ARAL learners (or [tutorId]'s, for a coordinator).
  Future<List<AralEnrollment>> tutorRoster({String? tutorId, String? schoolYear}) async {
    final id = tutorId ?? _auth.currentUser?.id;
    _log('tutorRoster(tutor: $id, year: $schoolYear)');
    if (id == null) throw const ViewModelException('Not signed in.');
    return _roster.getByTutor(id, schoolYear: schoolYear == null ? null : normalizeSchoolYear(schoolYear));
  }

  Future<AralEnrollment?> getEnrollment(int id) => _roster.findById(id);

  /// The school's ARAL roster for [schoolYear] as CSV ([sectionId] narrows it
  /// to one section): one line per learner. Admins/coordinators only.
  Future<String> rosterCsv({required int schoolId, required String schoolYear, int? sectionId}) async {
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
    final tutors = <String, User?>{};
    for (final e in roster) {
      if (!sections.containsKey(e.sectionId)) {
        sections[e.sectionId] = await _sections.getById(e.sectionId);
        for (final s in await _students.getBySection(e.sectionId)) {
          students[s.id!] = s;
        }
      }
      if (e.tutorId != null && !tutors.containsKey(e.tutorId)) tutors[e.tutorId!] = await _users.getById(e.tutorId!);
    }
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
        'Tutor', 'Tutor email', 'Basis', 'Basis round', 'Basis level', 'BASA suggestion', 'Notes', 'ARAL id',
      ],
      for (final e in roster)
        [
          grade(e), sections[e.sectionId]?.sectionName, students[e.studentId]?.lrn, name(e), e.programLabel,
          e.status.name, e.enteredOn, e.exitedOn, e.exitReason?.value,
          tutors[e.tutorId]?.fullName, tutors[e.tutorId]?.email, e.basisSource.value, e.basisRound, e.basisLevel,
          e.suggestedKeyStage == null
              ? null
              : '${e.suggestedKeyStage!.label}${e.suggestedTrack == null ? '' : ' ${e.suggestedTrack!.label}'}',
          e.notes, e.id,
        ],
    ]);
  }

  /// The school's active tutors (who can be assigned) with how many active
  /// ARAL learners each has in [schoolYear].
  Future<List<(User, int)>> tutors({required int schoolId, required String schoolYear}) async {
    _log('tutors(school: $schoolId, year: $schoolYear)');
    schoolYear = normalizeSchoolYear(schoolYear);
    final out = <(User, int)>[];
    for (final u in await _users.getAll()) {
      if (u.role != UserRole.tutor || !u.isActive || u.schoolId != schoolId) continue;
      final load = (await _roster.getByTutor(u.id, schoolYear: schoolYear)).where((e) => e.isActive).length;
      out.add((u, load));
    }
    out.sort((a, b) => a.$1.fullName.compareTo(b.$1.fullName));
    return out;
  }

  /// "Last, First" of the section's actively enrolled learners, by id.
  Future<Map<int, String>> learnerNames(int sectionId) async => {
        for (final s in await _students.getBySection(sectionId)) s.id!: '${s.lastName}, ${s.firstName}',
      };

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

  Future<void> _checkTutor(String tutorId, int schoolId) async {
    final User? u = await _users.getById(tutorId);
    if (u == null || u.role != UserRole.tutor || !u.isActive || u.schoolId != schoolId) {
      throw const ViewModelException("The ARAL tutor must be an active tutor of the learner's school.");
    }
  }

  Future<void> _warnTutorLoad(String tutorId, String schoolYear) async {
    final load = (await _roster.getByTutor(tutorId, schoolYear: schoolYear)).where((e) => e.isActive).length;
    if (load > aralTutorLoad) {
      lastWarning = 'This tutor now has $load active ARAL learners (recommended: at most $aralTutorLoad).';
      _log(lastWarning!);
    }
  }

  Future<T> _write<T>(Future<T> Function() write) async {
    try {
      return await write();
    } catch (e) {
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
