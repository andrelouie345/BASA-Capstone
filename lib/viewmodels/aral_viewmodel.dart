// lib/viewmodels/aral_viewmodel.dart
//
// ARAL-Reading roster (piece A1b). Offline-first: reads and writes the local
// copy (CRLA and Phil-IRI results, the roster), like the assessment ViewModels.
//
// Owner decisions (2026-10-15):
//  * BASA proposes who enters ARAL and in which program (aral_rules.dart); the
//    coordinator confirms or changes it. The suggestion is stored beside the
//    choice. Learners without a qualifying result can still be added by hand.
//  * Admins and coordinators manage the roster; tutors only read it.
//  * Exits are recorded by the coordinator (suggestions come in a later piece).
//  * A tutor's "special 15": more than 15 active ARAL learners is allowed but
//    warned about (lastWarning).
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
import '../core/services/normalizers.dart';
import 'auth_viewmodel.dart';
import 'phil_iri_viewmodel.dart';
import 'viewmodel_exception.dart';

/// Recommended maximum of active ARAL learners per tutor (DepEd 1:15).
const aralTutorLoad = 15;

enum AralCandidateStatus {
  /// Qualifies on its result: BASA proposes it with [AralCandidate.suggestion].
  proposed,
  /// Has a result, but it doesn't qualify (can still be added by hand).
  notQualified,
  /// No usable result in the basis round yet.
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
    this.basisSource,
    this.basisRound,
    this.basisLevel,
    this.basisAssessmentId,
    this.enrollment,
  });

  String get name => '${student.lastName}, ${student.firstName}';
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
  ];

  final ScopedLogger _log;
  final AuthViewModel _auth;
  final AralEnrollmentRepository _roster;
  final SectionRepository _sections;
  final StudentRepository _students;
  final UserRepository _users;
  final CrlaResultRepository _crlaResults;
  final PhilIriViewModel _philIri;

  /// A non-blocking notice from the last write (e.g. a tutor over 15 learners).
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

  /// Every actively enrolled learner of the section with BASA's proposal.
  /// [includeOptional] extends the program to KS1 Developing/Transitioning and
  /// KS2-3 Instructional readers (schools with enough tutors).
  Future<List<AralCandidate>> propose({
    required int sectionId,
    required String schoolYear,
    bool includeOptional = false,
  }) async {
    _log('propose(sectionId: $sectionId, year: $schoolYear, optional: $includeOptional)');
    schoolYear = normalizeSchoolYear(schoolYear);
    final (section, grade) = await _aralSection(sectionId, schoolYear);
    final learners = await _students.getBySection(section.id!);
    final enrolled = {for (final e in await _roster.getBySection(section.id!, schoolYear: schoolYear)) e.studentId: e};
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
          ? _crlaCandidate(s, grade, crla.where((r) => r.studentId == s.id).toList(), includeOptional)
          : await _philIriCandidate(s, grade, section.id!, schoolYear, includeOptional));
    }
    return out;
  }

  AralCandidate _crlaCandidate(Student s, int grade, List<CrlaResult> results, bool includeOptional) {
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
    final qualifies = aralCrlaQualifies(profile, includeOptional: includeOptional);
    return AralCandidate(
      student: s,
      grade: grade,
      status: qualifies ? AralCandidateStatus.proposed : AralCandidateStatus.notQualified,
      reason: 'CRLA ${round.label}: $profile',
      suggestion: qualifies ? aralCrlaPlacement : null,
      basisSource: AralBasisSource.crla,
      basisRound: round.name,
      basisLevel: profile,
      basisAssessmentId: basis.assessmentId,
    );
  }

  Future<AralCandidate> _philIriCandidate(
      Student s, int grade, int sectionId, String schoolYear, bool includeOptional) async {
    final results = await _philIri.learnerResults(studentId: s.id!, sectionId: sectionId, schoolYear: schoolYear);
    final bosy = results.rounds.where((r) => r.round == PhilIriRound.bosy).firstOrNull;
    if (bosy == null || !bosy.given || bosy.profile == null) {
      return AralCandidate(
        student: s,
        grade: grade,
        status: AralCandidateStatus.noResult,
        reason: 'No Phil-IRI BOSY reading yet${results.gst != null ? ' (GST only)' : ''}',
      );
    }
    final profile = bosy.profile!;
    final qualifies = aralPhilIriQualifies(profile, includeOptional: includeOptional);
    final placement = aralPhilIriPlacement(
      profile: profile,
      wordReadingLevel: bosy.wordReadingLevel,
      adjustedLevel: bosy.adjustedLevel,
      grade: grade,
    );
    final level = bosy.adjustedLevel == null || bosy.adjustedLevel == 0 ? '' : ', reads at Grade ${bosy.adjustedLevel}';
    return AralCandidate(
      student: s,
      grade: grade,
      status: qualifies ? AralCandidateStatus.proposed : AralCandidateStatus.notQualified,
      reason: 'Phil-IRI BOSY: ${profile.label} (word reading ${bosy.wordReadingLevel?.label ?? '-'}$level)',
      suggestion: qualifies ? placement : null,
      basisSource: AralBasisSource.philIri,
      basisRound: PhilIriRound.bosy.name,
      basisLevel: profile.name,
      basisAssessmentId: results.sessions[PhilIriRound.bosy]?.id,
    );
  }

  // ---- Roster changes (admin / coordinator) ----

  /// Puts one learner on the roster. Without [keyStage]/[track] the proposal
  /// is used; giving them overrides it (the suggestion is still stored). A
  /// learner without a qualifying result needs an explicit [keyStage] (and
  /// [track] for KS2/KS3).
  Future<AralEnrollment> enroll({
    required int sectionId,
    required String schoolYear,
    required int studentId,
    AralKeyStage? keyStage,
    AralTrack? track,
    String? tutorId,
    String? notes,
    bool includeOptional = false,
    DateTime? enteredOn,
  }) async {
    _log('enroll(student: $studentId, section: $sectionId, year: $schoolYear, ks: ${keyStage?.name}, '
        'track: ${track?.name}, tutor: $tutorId)');
    _requireManager();
    lastWarning = null;
    schoolYear = normalizeSchoolYear(schoolYear);
    final (section, _) = await _aralSection(sectionId, schoolYear);
    final candidate = (await propose(sectionId: sectionId, schoolYear: schoolYear, includeOptional: includeOptional))
        .where((c) => c.student.id == studentId)
        .firstOrNull;
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
    if (candidate.status == AralCandidateStatus.enrolled) {
      throw ViewModelException('${candidate.name} is already on the ARAL roster for $schoolYear '
          '(${candidate.enrollment!.programLabel}).');
    }
    final suggestion = candidate.suggestion;
    final ks = keyStage ?? suggestion?.keyStage;
    if (ks == null) {
      throw ViewModelException('${candidate.name} has no qualifying result (${candidate.reason}); '
          'give the key stage (and the track for KS2/KS3) to add them by hand.');
    }
    final tr = keyStage == null && track == null ? suggestion?.track : track;
    _checkTrack(ks, tr);
    if (tutorId != null) await _checkTutor(tutorId, section.schoolId);

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
  /// tutor for all of them). Learners already on the roster are skipped.
  Future<List<AralEnrollment>> enrollProposed({
    required int sectionId,
    required String schoolYear,
    bool includeOptional = false,
    String? tutorId,
  }) async {
    _log('enrollProposed(section: $sectionId, year: $schoolYear, optional: $includeOptional, tutor: $tutorId)');
    _requireManager();
    lastWarning = null;
    schoolYear = normalizeSchoolYear(schoolYear);
    final (section, _) = await _aralSection(sectionId, schoolYear);
    if (tutorId != null) await _checkTutor(tutorId, section.schoolId);
    final candidates = await propose(sectionId: sectionId, schoolYear: schoolYear, includeOptional: includeOptional);
    final created = <AralEnrollment>[];
    for (final c in candidates.where((c) => c.status == AralCandidateStatus.proposed)) {
      created.add(await _enrollCandidate(c, section, schoolYear, tutorId: tutorId));
    }
    if (tutorId != null && created.isNotEmpty) await _warnTutorLoad(tutorId, schoolYear);
    return created;
  }

  /// Changes the program (KS1 has no track; KS2/KS3 need one).
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

  /// Records that the learner left ARAL (the reason is required).
  Future<AralEnrollment> exit(int enrollmentId, AralExitReason reason, {DateTime? on}) async {
    _log('exit($enrollmentId, ${reason.value})');
    _requireManager();
    final e = await _require(enrollmentId);
    if (!e.isActive) throw ViewModelException('This learner already left ARAL on ${e.exitedOn}.');
    final date = _localDate(on ?? DateTime.now());
    if (date.compareTo(e.enteredOn) < 0) {
      throw ViewModelException('The exit date $date is before the learner entered ARAL (${e.enteredOn}).');
    }
    return _write(() => _roster.update(
        e.copyWith(status: AralStatus.exited, exitedOn: () => date, exitReason: () => reason)));
  }

  /// Undoes an exit (e.g. recorded by mistake).
  Future<AralEnrollment> reactivate(int enrollmentId) async {
    _log('reactivate($enrollmentId)');
    _requireManager();
    final e = await _require(enrollmentId);
    if (e.isActive) throw const ViewModelException('This learner is already active in ARAL.');
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
    if (ks == AralKeyStage.ks1 && track != null) {
      throw const ViewModelException('KS1 has no Basic/Plus track.');
    }
    if (ks != AralKeyStage.ks1 && track == null) {
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
        if (text.contains(refusal)) throw ViewModelException(refusal.endsWith('.') ? refusal : '$refusal.');
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
