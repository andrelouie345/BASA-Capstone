// lib/viewmodels/phil_iri_viewmodel.dart
//
// Phil-IRI assessments: GST results, sessions (BOSY, MOSY #1-#3, EOSY), the
// live oral reading (one grade-level passage per session), miscue taps,
// comprehension answers, rubric scores, the session lifecycle, and results.
//
// Like CrlaViewModel it reads and writes the LOCAL database (offline-first;
// the cloud gets the data through sync). Content and thresholds are read from
// the local mirror (pull-cloud). The local triggers enforce the cloud's rules;
// this ViewModel checks the same things first so the user gets a clear message.
//
// Results: an open session is scored live with the school's current
// thresholds; a finalized one keeps the thresholds it was finalized with
// (its snapshot). learnerResults(useCurrentThresholds: true) regenerates every
// round with today's thresholds without changing anything stored.
import 'dart:convert';

import '../core/console/logger.dart';
import '../core/models/phil_iri_answer.dart';
import '../core/models/phil_iri_assessment.dart';
import '../core/models/phil_iri_collection.dart';
import '../core/models/phil_iri_gst_result.dart';
import '../core/models/phil_iri_miscue.dart';
import '../core/models/phil_iri_passage.dart';
import '../core/models/phil_iri_question.dart';
import '../core/models/phil_iri_reading.dart';
import '../core/models/phil_iri_rubric_score.dart';
import '../core/models/section.dart';
import '../core/models/user_role.dart';
import '../core/repositories/phil_iri_assessment_repository.dart';
import '../core/repositories/phil_iri_collection_repository.dart';
import '../core/repositories/phil_iri_gst_repository.dart';
import '../core/repositories/phil_iri_passage_repository.dart';
import '../core/repositories/phil_iri_threshold_repository.dart';
import '../core/repositories/section_repository.dart';
import '../core/services/normalizers.dart';
import '../core/services/phil_iri_results.dart';
import '../core/services/phil_iri_rules.dart';
import '../core/services/sync_upload_rules.dart' show pendingLockMessage;
import 'auth_viewmodel.dart';
import 'viewmodel_exception.dart';

/// One learner's year: every round's result plus the end result.
class PhilIriLearnerResults {
  final int studentId;
  final int learnerGrade;
  final String schoolYear;
  final PhilIriGstResult? gst;
  /// Latest attempt per round (the one that counts).
  final Map<PhilIriRound, PhilIriAssessment> sessions;
  final List<PhilIriRoundResult> rounds;
  final PhilIriRoundResult? end;
  /// True when every round was scored with today's thresholds.
  final bool regenerated;

  const PhilIriLearnerResults({
    required this.studentId,
    required this.learnerGrade,
    required this.schoolYear,
    required this.gst,
    required this.sessions,
    required this.rounds,
    required this.end,
    required this.regenerated,
  });
}

/// A learner's year as reports and ARAL count it ([PhilIriViewModel.reportResults]).
class PhilIriReportResults {
  final int learnerGrade;
  /// Carried round results built from the counted readings only.
  final List<PhilIriRoundResult> rounds;
  /// Rounds that count: those with a finished reading dated by asOf, and
  /// BOSY when only a counted GST stands for it (the GST carries into BOSY).
  final Set<PhilIriRound> counted;
  /// The session that stands for each counted round (none for a GST-only BOSY).
  final Map<PhilIriRound, PhilIriAssessment> sessions;
  /// The GST that counts (taken by asOf, score above 0), if any.
  final PhilIriGstResult? gst;
  /// Nothing counts at all (no reading; no GST, or a GST of 0): reports and
  /// ARAL assume Frustration, 3 levels down ([philIriNotAssessedResult]).
  final bool notAssessed;

  const PhilIriReportResults({
    required this.learnerGrade,
    required this.rounds,
    required this.counted,
    required this.sessions,
    required this.gst,
    required this.notAssessed,
  });

  PhilIriRoundResult round(PhilIriRound r) => rounds.firstWhere((x) => x.round == r);

  /// The carried result of the latest counted round among [among], or null.
  PhilIriRoundResult? latest(Iterable<PhilIriRound> among) {
    PhilIriRoundResult? last;
    for (final r in rounds) {
      if (among.contains(r.round) && counted.contains(r.round)) last = r;
    }
    return last;
  }
}

/// What finalizeRound did.
class PhilIriRoundClosure {
  final List<PhilIriAssessment> finalized;
  final List<PhilIriAssessment> stillInProgress;
  final List<PhilIriAssessment> alreadyFinalized;
  const PhilIriRoundClosure(this.finalized, this.stillInProgress, this.alreadyFinalized);
}

class PhilIriViewModel {
  // RAISE(ABORT, ...) texts of the local triggers (phil_iri_local_schema.dart)
  // and the repository's StateErrors. A refused write is rethrown as a
  // ViewModelException with just this text. Keep in sync.
  static const _dbRefusals = [
    'No such section',
    'Phil-IRI is for Grade 4-10 sections only',
    'Section does not belong to that school',
    'Learner has no active enrollment in this section for that school year',
    'The GST for Grades 4-6 is out of 20, for Grades 7-10 out of 40',
    'GST results are not edited; record a retake instead',
    'A new Phil-IRI session starts in progress',
    'A finalized Phil-IRI assessment cannot be changed',
    'Only the status of a Phil-IRI assessment can change',
    'Only a completed Phil-IRI assessment can be finalized',
    'This Phil-IRI assessment is finalized and cannot be changed',
    'No such passage',
    'This passage or its collection is not active',
    'A learner reads a passage of their own grade',
    'A reading keeps its session, passage and method; delete it and add a new one instead',
    'A silent reading has no miscues',
    'Word position is outside the passage',
    "That question is not a question of this reading's passage",
    'Score is outside the rubric scale',
    'Only an in-progress Phil-IRI assessment can be discarded',
  ];

  final ScopedLogger _log;
  final AuthViewModel _auth;
  final PhilIriAssessmentRepository _sessions;
  final PhilIriGstRepository _gst;
  final PhilIriPassageRepository _passages;
  final PhilIriCollectionRepository _collections;
  final PhilIriThresholdRepository _thresholds;
  final SectionRepository _sections;

  List<PhilIriAssessment> assessments = [];
  int? _lastSectionId;
  String? _lastSchoolYear;

  PhilIriViewModel({
    required AuthViewModel auth,
    required PhilIriAssessmentRepository sessions,
    required PhilIriGstRepository gst,
    required PhilIriPassageRepository passages,
    required PhilIriCollectionRepository collections,
    required PhilIriThresholdRepository thresholds,
    required SectionRepository sections,
    Logger? logger,
  })  : _auth = auth,
        _sessions = sessions,
        _gst = gst,
        _passages = passages,
        _collections = collections,
        _thresholds = thresholds,
        _sections = sections,
        _log = ScopedLogger(logger, 'PhilIriViewModel');

  /// Every public method starts here: signed in, online or offline. Screens
  /// call this ViewModel directly, so the console's own check is not enough.
  void _requireSignIn() {
    final error = _auth.requireActiveSession();
    if (error != null) throw ViewModelException(error);
  }

  // ---- Lists ----

  Future<void> loadForSection(int sectionId, {String? schoolYear, PhilIriRound? round}) async {
    _requireSignIn();
    _log('loadForSection(sectionId: $sectionId, schoolYear: $schoolYear, round: ${round?.name})');
    if (schoolYear != null) schoolYear = normalizeSchoolYear(schoolYear);
    _lastSectionId = sectionId;
    _lastSchoolYear = schoolYear;
    assessments = await _sessions.getBySection(sectionId, schoolYear: schoolYear, round: round);
  }

  Future<void> refresh() async {
    _requireSignIn();
    if (_lastSectionId != null) await loadForSection(_lastSectionId!, schoolYear: _lastSchoolYear);
  }

  // ---- Thresholds ----

  /// The values in force for a school: built-in defaults, then the region
  /// row, then the school's override, key by key.
  Future<PhilIriThresholds> effectiveThresholds(int schoolId) async {
    _requireSignIn();
    final region = await _thresholds.getRegion();
    final school = await _thresholds.getForSchool(schoolId);
    return PhilIriThresholds.fromMap({...?region?.settings, ...?school?.settings});
  }

  /// Whether [g] reaches the GST pass mark of its school. The test's size
  /// tells the grade group (40 items = Grades 7-10), which is all the pass
  /// mark needs.
  Future<bool> gstPassed(PhilIriGstResult g) async {
    _requireSignIn();
    return philIriGstPassed(g.maxScore == 40 ? 7 : 4, g.totalScore, await effectiveThresholds(g.schoolId));
  }

  // ---- GST ----

  /// Records a GST (Form 1B). The test is out of 20 for Grades 4-6 and 40 for
  /// Grades 7-10. A correction is a retake: call again; the newest counts.
  Future<PhilIriGstResult> recordGst({
    required int studentId,
    required int sectionId,
    required String schoolYear,
    required int totalScore,
    int? literalCorrect,
    int? inferentialCorrect,
    int? criticalCorrect,
    DateTime? takenAt,
  }) async {
    _requireSignIn();
    _log('recordGst(studentId: $studentId, sectionId: $sectionId, year: $schoolYear, total: $totalScore)');
    schoolYear = normalizeSchoolYear(schoolYear);
    final (section, grade) = await _philIriSection(sectionId);
    final max = philIriGstMaxScore(grade);
    _checkRange('totalScore', totalScore, 0, max);
    final parts = [literalCorrect, inferentialCorrect, criticalCorrect];
    for (final (i, p) in parts.indexed) {
      if (p != null) _checkRange(['literalCorrect', 'inferentialCorrect', 'criticalCorrect'][i], p, 0, max);
    }
    if (parts.every((p) => p != null) && parts.fold<int>(0, (a, p) => a + p!) != totalScore) {
      throw ViewModelException('Literal + inferential + critical must add up to the total ($totalScore).');
    }
    final stored = await _write(() => _gst.insert(PhilIriGstResult(
          studentId: studentId,
          schoolId: section.schoolId,
          sectionId: sectionId,
          schoolYear: schoolYear,
          maxScore: max,
          totalScore: totalScore,
          literalCorrect: literalCorrect,
          inferentialCorrect: inferentialCorrect,
          criticalCorrect: criticalCorrect,
          takenAt: _localDate(takenAt ?? DateTime.now()),
          administeredBy: _auth.currentUser?.id,
        )));
    _log('recorded GST ${stored.id} (attempt ${stored.attemptNo}): ${stored.totalScore}/${stored.maxScore}, '
        '${philIriGstPassed(grade, totalScore, await effectiveThresholds(section.schoolId)) ? "passed" : "below the cut-off"}');
    return stored;
  }

  Future<List<PhilIriGstResult>> gstForSection(int sectionId, {String? schoolYear}) async {
    _requireSignIn();
    _log('gstForSection(sectionId: $sectionId, schoolYear: $schoolYear)');
    return _gst.getBySection(sectionId, schoolYear: schoolYear == null ? null : normalizeSchoolYear(schoolYear));
  }

  // ---- Sessions ----

  /// Starts a session (attempt). A retake is another call with the same
  /// learner/section/round/year; the newest attempt counts.
  Future<PhilIriAssessment> startSession({
    required int studentId,
    required int sectionId,
    required String schoolYear,
    required PhilIriRound round,
    DateTime? assessedAt,
  }) async {
    _requireSignIn();
    _log('startSession(studentId: $studentId, sectionId: $sectionId, year: $schoolYear, round: ${round.name})');
    schoolYear = normalizeSchoolYear(schoolYear);
    final (section, _) = await _philIriSection(sectionId);
    final stored = await _write(() => _sessions.insertAssessment(PhilIriAssessment(
          studentId: studentId,
          schoolId: section.schoolId,
          sectionId: sectionId,
          schoolYear: schoolYear,
          round: round,
          assessedAt: _localDate(assessedAt ?? DateTime.now()),
          administeredBy: _auth.currentUser?.id,
        )));
    _log('started session ${stored.id} (${round.label}, attempt ${stored.attemptNo})');
    await refresh();
    return stored;
  }

  Future<PhilIriAssessment?> getSession(int assessmentId) async {
    _requireSignIn();
    _log('getSession($assessmentId)');
    return _sessions.findAssessment(assessmentId);
  }

  /// Passages this session may use: active passages of the learner's grade in
  /// active grade-leveled collections, plus active passages of active
  /// non-graded collections (e.g. FRB). Either way only passages whose test
  /// type fits the session's round (BOSY 'pre', MOSY 'mosy', EOSY 'post';
  /// untyped passages fit any round), that the learner has never read (same
  /// text = same passage, any collection, any year), each text listed once.
  /// For an oral [method] (the default) a text read silently in another
  /// session of this round and year is offered too, FIRST: the oral follow-up
  /// may re-read it (reading coordinator, 2026-10-16).
  /// An empty list means the coordinator has to add passages.
  Future<List<PhilIriPassage>> availablePassages(int assessmentId,
      {PhilIriReadingMethod method = PhilIriReadingMethod.wholeText}) async {
    _requireSignIn();
    _log('availablePassages($assessmentId, method: ${method.value})');
    final session = await _requireSession(assessmentId);
    final grade = (await _philIriSection(session.sectionId)).$2;
    final graded = await _passages.getForLevel(grade);
    final others = <PhilIriPassage>[];
    for (final c in await _collections.getAll(activeOnly: true)) {
      if (!c.isGradeLeveled) others.addAll(await _passages.getByCollection(c.id!, activeOnly: true));
    }
    final followUps = <String>{};
    final seen = (await _blockedTexts(session, method, followUps: followUps)).keys.toSet();
    final list = [...graded, ...others]
        .where((p) => session.round.allowsPassageTestType(p.testType))
        .where((p) => seen.add(p.textKey)) // false for read texts and for repeats in this list
        .toList();
    return [...list.where((p) => followUps.contains(p.textKey)), ...list.where((p) => !followUps.contains(p.textKey))];
  }

  /// The session's one passage reading. Each session (FLT/BOSY, MOSY, EOSY)
  /// has exactly one grade-level passage: delete the reading to change it.
  /// Whole-text: [readingSeconds] (may be set later with [saveTiming]).
  /// One-minute: [wordsRead] in the minute.
  Future<PhilIriReading> startReading({
    required int assessmentId,
    required int passageId,
    PhilIriReadingMethod method = PhilIriReadingMethod.wholeText,
    int? readingSeconds,
    int? wordsRead,
  }) async {
    _requireSignIn();
    _log('startReading(assessmentId: $assessmentId, passageId: $passageId, method: ${method.value})');
    final session = await _requireOpenSession(assessmentId);
    if ((await _sessions.getReadings(assessmentId)).isNotEmpty) {
      throw const ViewModelException('This session already has its passage reading; delete it to use another passage.');
    }
    final passage = await _requirePassage(passageId);
    final collection = await _collections.findById(passage.collectionId);
    if (collection == null || !passage.isActive || !collection.isActive) {
      throw const ViewModelException('This passage or its collection is not active.');
    }
    if (collection.isGradeLeveled) {
      final grade = (await _philIriSection(session.sectionId)).$2;
      if (passage.level != grade) {
        throw ViewModelException('A Grade $grade learner reads a Grade $grade passage '
            '("${passage.title}" is Grade ${passage.level}).');
      }
    }
    if (!session.round.allowsPassageTestType(passage.testType)) {
      throw ViewModelException('${session.round.label} reads ${session.round.passageTestType} passages '
          '("${passage.title}" is a ${passage.testType} passage).');
    }
    final before = (await _blockedTexts(session, method))[passage.textKey];
    if (before != null) {
      throw ViewModelException('This learner has already read "${before.title}"; a learner never reads the same '
          'passage twice (only an oral follow-up of a silent reading, as another attempt of the same round, may '
          're-read it). Choose another passage (the coordinator can add passages if none are left).');
    }
    _checkTiming(method, readingSeconds, wordsRead);
    return _write(() => _sessions.insertReading(PhilIriReading(
          assessmentId: assessmentId,
          sequenceNo: 1,
          passageId: passageId,
          method: method,
          readingSeconds: method == PhilIriReadingMethod.oneMinute ? null : readingSeconds,
          wordsRead: method == PhilIriReadingMethod.oneMinute ? wordsRead : null,
        )));
  }

  /// The time taken (whole-text) or words read in the minute (one-minute).
  Future<PhilIriReading> saveTiming(int readingId, {int? readingSeconds, int? wordsRead}) async {
    _requireSignIn();
    _log('saveTiming(readingId: $readingId, seconds: $readingSeconds, wordsRead: $wordsRead)');
    final r = await _requireOpenReading(readingId);
    _checkTiming(r.reading.method, readingSeconds, wordsRead, required: true);
    return _write(() => _sessions.updateReading(PhilIriReading(
          id: readingId,
          assessmentId: r.reading.assessmentId,
          sequenceNo: r.reading.sequenceNo,
          passageId: r.reading.passageId,
          method: r.reading.method,
          readingSeconds: r.reading.method == PhilIriReadingMethod.oneMinute ? null : readingSeconds,
          wordsRead: r.reading.method == PhilIriReadingMethod.oneMinute ? wordsRead : null,
          observation: r.reading.observation,
        )));
  }

  /// Form 4 Oral Reading Observation Checklist for the reading.
  Future<PhilIriReading> saveObservation(int readingId, PhilIriObservation observation) async {
    _requireSignIn();
    _log('saveObservation(readingId: $readingId)');
    final r = await _requireOpenReading(readingId);
    return _write(() => _sessions.updateReading(PhilIriReading(
          id: readingId,
          assessmentId: r.reading.assessmentId,
          sequenceNo: r.reading.sequenceNo,
          passageId: r.reading.passageId,
          method: r.reading.method,
          readingSeconds: r.reading.readingSeconds,
          wordsRead: r.reading.wordsRead,
          observation: observation,
        )));
  }

  /// Removes the reading with its miscues and answers (to pick another passage).
  Future<void> deleteReading(int readingId) async {
    _requireSignIn();
    _log('deleteReading($readingId)');
    await _requireOpenReading(readingId);
    await _write(() => _sessions.deleteReading(readingId));
  }

  // ---- Miscues (the tapped words) ----

  /// [wordIndex] is a position in PhilIriPassage.words. An insertion goes
  /// BEFORE that word (words.length = after the last word).
  Future<PhilIriMiscue> markMiscue({
    required int readingId,
    required int wordIndex,
    required PhilIriMiscueType type,
    String? spokenText,
    bool selfCorrected = false,
  }) async {
    _requireSignIn();
    _log('markMiscue(readingId: $readingId, word: $wordIndex, type: ${type.name}, sc: $selfCorrected)');
    final r = await _requireOpenReading(readingId);
    _requireOral(r.reading);
    _checkWordIndex(r.passage, wordIndex, type);
    return _write(() => _sessions.insertMiscue(PhilIriMiscue(
          readingId: readingId,
          wordIndex: wordIndex,
          type: type,
          spokenText: _blankToNull(spokenText),
          selfCorrected: selfCorrected,
        )));
  }

  /// Changes a miscue's type, text or self-correction flag (same word).
  Future<PhilIriMiscue> updateMiscue(PhilIriMiscue miscue) async {
    _requireSignIn();
    _log('updateMiscue(${miscue.id})');
    if (miscue.id == null) throw const ViewModelException('Miscue has no id.');
    final r = await _requireOpenReading(miscue.readingId);
    _requireOral(r.reading);
    _checkWordIndex(r.passage, miscue.wordIndex, miscue.type);
    return _write(() => _sessions.updateMiscue(miscue));
  }

  Future<void> removeMiscue(int miscueId) async {
    _requireSignIn();
    _log('removeMiscue($miscueId)');
    await _write(() => _sessions.deleteMiscue(miscueId));
  }

  Future<List<PhilIriMiscue>> miscues(int readingId) async {
    _requireSignIn();
    return _sessions.getMiscues(readingId);
  }

  // ---- Comprehension ----

  /// [chosen] is the choice letter (a, b, ...); null records "I don't know"
  /// (wrong). Answering the same question again replaces the answer.
  Future<PhilIriAnswer> answer({
    required int readingId,
    required int questionId,
    String? chosen,
    bool lookedBack = false,
  }) async {
    _requireSignIn();
    _log('answer(readingId: $readingId, questionId: $questionId, chosen: $chosen, lb: $lookedBack)');
    final r = await _requireOpenReading(readingId);
    final questions = await _passages.getQuestions(r.passage.id!);
    final q = questions.where((x) => x.id == questionId).firstOrNull;
    if (q == null) {
      throw ViewModelException('Question $questionId is not a question of "${r.passage.title}".');
    }
    final letter = chosen?.trim().toLowerCase();
    if (letter != null) {
      final valid = [for (var i = 0; i < q.choices.length; i++) PhilIriQuestion.letterOf(i)];
      if (!valid.contains(letter)) {
        throw ViewModelException('Choose one of ${valid.join(', ')} (got "$chosen").');
      }
    }
    return _write(() => _sessions.saveAnswer(PhilIriAnswer(
          readingId: readingId,
          questionId: questionId,
          chosen: letter,
          isCorrect: false, // computed by the database from the key
          lookedBack: lookedBack,
        )));
  }

  Future<List<PhilIriAnswer>> answers(int readingId) async {
    _requireSignIn();
    return _sessions.getAnswers(readingId);
  }

  // ---- Reads for showing a session (local data) ----

  /// The session's readings (one per session today), by sequence_no.
  Future<List<PhilIriReading>> readings(int assessmentId) async {
    _requireSignIn();
    return _sessions.getReadings(assessmentId);
  }

  /// A passage from the local mirror, or null when it isn't there.
  Future<PhilIriPassage?> passage(int passageId) async {
    _requireSignIn();
    return _passages.findById(passageId);
  }

  /// A passage's comprehension questions, by question_no.
  Future<List<PhilIriQuestion>> questions(int passageId) async {
    _requireSignIn();
    return _passages.getQuestions(passageId);
  }

  /// A collection from the local mirror, or null when it isn't there.
  Future<PhilIriCollection?> collection(int collectionId) async {
    _requireSignIn();
    return _collections.findById(collectionId);
  }

  /// A collection's rubric criteria, by criterion_no.
  Future<List<PhilIriRubricCriterion>> rubricCriteria(int collectionId) async {
    _requireSignIn();
    return _collections.getCriteria(collectionId);
  }

  Future<List<PhilIriRubricScore>> rubricScores(int assessmentId) async {
    _requireSignIn();
    return _sessions.getRubricScores(assessmentId);
  }

  // ---- Rubric ----

  Future<PhilIriRubricScore> scoreRubric({
    required int assessmentId,
    required int criterionId,
    required int score,
  }) async {
    _requireSignIn();
    _log('scoreRubric(assessmentId: $assessmentId, criterionId: $criterionId, score: $score)');
    await _requireOpenSession(assessmentId);
    PhilIriRubricCriterion? criterion;
    for (final c in await _collections.getAll()) {
      criterion ??= (await _collections.getCriteria(c.id!)).where((k) => k.id == criterionId).firstOrNull;
    }
    if (criterion == null) throw ViewModelException('No rubric criterion with id $criterionId.');
    _checkRange(criterion.name, score, criterion.scaleMin, criterion.scaleMax);
    return _write(() => _sessions.saveRubricScore(
        PhilIriRubricScore(assessmentId: assessmentId, criterionId: criterionId, score: score)));
  }

  // ---- Lifecycle ----

  /// Tutor/coordinator: the session is done. Needs the reading, timed.
  Future<PhilIriAssessment> complete(int assessmentId) async {
    _requireSignIn();
    _log('complete($assessmentId)');
    await _requireOpenSession(assessmentId);
    final readings = await _sessions.getReadings(assessmentId);
    if (readings.isEmpty) throw const ViewModelException('Record the passage reading before completing the session.');
    final r = readings.first;
    if (r.method != PhilIriReadingMethod.oneMinute && r.readingSeconds == null) {
      throw const ViewModelException('Record the reading time before completing the session.');
    }
    if (r.method == PhilIriReadingMethod.oneMinute && r.wordsRead == null) {
      throw const ViewModelException('Record the words read in the minute before completing the session.');
    }
    final stored = await _write(() => _sessions.setStatus(assessmentId, PhilIriStatus.completed));
    await refresh();
    return stored;
  }

  /// Back to in progress (not once finalized).
  Future<PhilIriAssessment> reopen(int assessmentId) async {
    _requireSignIn();
    _log('reopen($assessmentId)');
    await _requireOpenSession(assessmentId);
    final stored = await _write(() => _sessions.setStatus(assessmentId, PhilIriStatus.inProgress));
    await refresh();
    return stored;
  }

  /// Discards an in-progress session and everything under it.
  Future<void> discard(int assessmentId) async {
    _requireSignIn();
    _log('discard($assessmentId)');
    final s = await _requireSession(assessmentId);
    if (s.status != PhilIriStatus.inProgress) {
      throw ViewModelException('Only an in-progress session can be discarded (this one is ${s.status.value}).');
    }
    await _write(() => _sessions.deleteAssessment(assessmentId));
    await refresh();
  }

  /// Admin/coordinator (or superadmin): freezes a completed session with the
  /// school's current thresholds. A finalized session never changes.
  Future<PhilIriAssessment> finalize(int assessmentId) async {
    _requireSignIn();
    _log('finalize($assessmentId)');
    _requireFinalizer();
    final s = await _requireSession(assessmentId);
    if (s.status != PhilIriStatus.completed) {
      throw ViewModelException('Only a completed session can be finalized (this one is ${s.status.value}).');
    }
    final t = await effectiveThresholds(s.schoolId);
    final frozen = <PhilIriReading>[];
    for (final r in await _sessions.getReadings(assessmentId)) {
      final result = await _scoreReading(r, t);
      frozen.add(PhilIriReading(
        id: r.id,
        assessmentId: r.assessmentId,
        sequenceNo: r.sequenceNo,
        passageId: r.passageId,
        method: r.method,
        wordReadingScore: result.wordReadingScore,
        wordsPerMinute: result.wordsPerMinute,
        accuracyLevel: result.accuracyLevel,
        speed: result.speed,
        wordReadingLevel: result.wordReadingLevel,
        comprehensionScore: result.comprehensionScore,
        comprehensionLevel: result.comprehensionLevel,
        profile: result.profile,
      ));
    }
    final stored = await _write(() => _sessions.finalize(
        assessmentId: assessmentId, thresholdsSnapshot: t.toMap(), readingResults: frozen));
    _log('finalized session $assessmentId');
    await refresh();
    return stored;
  }

  /// Admin/coordinator closes a round for a section: finalizes the latest
  /// attempt of every learner that is completed. In-progress ones are left
  /// as they are and listed so they can be finished first.
  Future<PhilIriRoundClosure> finalizeRound({
    required int sectionId,
    required String schoolYear,
    required PhilIriRound round,
  }) async {
    _requireSignIn();
    _log('finalizeRound(sectionId: $sectionId, year: $schoolYear, round: ${round.name})');
    _requireFinalizer();
    schoolYear = normalizeSchoolYear(schoolYear);
    final all = await _sessions.getBySection(sectionId, schoolYear: schoolYear, round: round);
    final latest = <int, PhilIriAssessment>{};
    for (final s in all) {
      final prev = latest[s.studentId];
      if (prev == null || (s.attemptNo ?? 0) > (prev.attemptNo ?? 0)) latest[s.studentId] = s;
    }
    final done = <PhilIriAssessment>[], open = <PhilIriAssessment>[], already = <PhilIriAssessment>[];
    for (final s in latest.values) {
      switch (s.status) {
        case PhilIriStatus.completed:
          done.add(await finalize(s.id!));
        case PhilIriStatus.inProgress:
          open.add(s);
        case PhilIriStatus.finalized:
          already.add(s);
      }
    }
    return PhilIriRoundClosure(done, open, already);
  }

  // ---- Results ----

  /// One reading scored now: with the snapshot if its session is finalized,
  /// otherwise with the school's current thresholds (or [thresholds]).
  /// The silent reading an oral reading follows up (same learner, round,
  /// year and text, another session), or null. Its answers count when the
  /// follow-up records none.
  Future<PhilIriReading?> silentReadingFollowedUp(int readingId) async {
    _requireSignIn();
    final r = await _findReading(readingId);
    if (!r.method.isOral) return null;
    return _silentReadingFollowedUp(r, await _requirePassage(r.passageId));
  }

  Future<PhilIriPassageResult> scoreReading(int readingId, {PhilIriThresholds? thresholds}) async {
    _requireSignIn();
    _log('scoreReading($readingId)');
    final r = await _findReading(readingId);
    final session = (await _sessions.findAssessment(r.assessmentId))!;
    return _scoreReading(r, thresholds ?? await _thresholdsFor(session));
  }

  /// A learner's year: GST, the latest attempt of each round, round results
  /// with carry-up/carry-forward, and the end result. Finalized rounds use
  /// their snapshot; [useCurrentThresholds] regenerates everything with
  /// today's values instead (nothing stored changes).
  Future<PhilIriLearnerResults> learnerResults({
    required int studentId,
    required int sectionId,
    required String schoolYear,
    bool useCurrentThresholds = false,
  }) async {
    _requireSignIn();
    _log('learnerResults(studentId: $studentId, sectionId: $sectionId, year: $schoolYear, current: $useCurrentThresholds)');
    schoolYear = normalizeSchoolYear(schoolYear);
    final (section, grade) = await _philIriSection(sectionId);
    final current = await effectiveThresholds(section.schoolId);
    final gst = await _gst.getLatest(studentId: studentId, schoolYear: schoolYear);

    final sessions = <PhilIriRound, PhilIriAssessment>{};
    for (final s in await _sessions.getByStudent(studentId, schoolYear: schoolYear)) {
      if (s.sectionId != sectionId) continue;
      final prev = sessions[s.round];
      if (prev == null || (s.attemptNo ?? 0) > (prev.attemptNo ?? 0)) sessions[s.round] = s;
    }

    final readings = <PhilIriRound, PhilIriPassageResult>{};
    final roundThresholds = <PhilIriRound, PhilIriThresholds>{};
    for (final e in sessions.entries) {
      final t = useCurrentThresholds ? current : await _thresholdsFor(e.value, current: current);
      roundThresholds[e.key] = t;
      final rs = await _sessions.getReadings(e.value.id!);
      if (rs.isEmpty) continue;
      final r = rs.first;
      if (r.method != PhilIriReadingMethod.oneMinute && r.readingSeconds == null) continue; // not timed yet
      if (r.method == PhilIriReadingMethod.oneMinute && r.wordsRead == null) continue;
      readings[e.key] = await _scoreReading(r, t);
    }

    final rounds = philIriRoundResults(
      learnerGrade: grade,
      gstScore: gst?.percent,
      readings: readings,
      t: current,
      roundThresholds: roundThresholds,
    );
    return PhilIriLearnerResults(
      studentId: studentId,
      learnerGrade: grade,
      schoolYear: schoolYear,
      gst: gst,
      sessions: sessions,
      rounds: rounds,
      end: philIriEndResult(rounds),
      regenerated: useCurrentThresholds,
    );
  }

  /// The year as reports and ARAL count it: only finished sessions (completed
  /// or finalized) assessed by [asOf] (YYYY-MM-DD, default: all) and a GST
  /// taken by then; carried round to round with the school's current
  /// thresholds (each reading keeps the score its round gave it). The GST
  /// carries into BOSY, so a GST alone is a BOSY result. A GST of 0 counts as
  /// no assessment, like no GST at all (the workbook's 0.2 / 0.1 markers).
  /// notAssessed when nothing counts (reading coordinator 2026-10-16/18).
  Future<PhilIriReportResults> reportResults({
    required int studentId,
    required int sectionId,
    required String schoolYear,
    String? asOf,
  }) async {
    _requireSignIn();
    final res = await learnerResults(studentId: studentId, sectionId: sectionId, schoolYear: schoolYear);
    bool byDate(String date) => asOf == null || date.substring(0, 10).compareTo(asOf) <= 0;
    final readings = <PhilIriRound, PhilIriPassageResult>{};
    final sessions = <PhilIriRound, PhilIriAssessment>{};
    for (final r in res.rounds) {
      final s = res.sessions[r.round];
      if (r.actual != null && s != null && s.status != PhilIriStatus.inProgress && byDate(s.assessedAt)) {
        readings[r.round] = r.actual!;
        sessions[r.round] = s;
      }
    }
    final gst = res.gst != null && res.gst!.totalScore > 0 && byDate(res.gst!.takenAt) ? res.gst : null;
    final section = (await _philIriSection(sectionId)).$1;
    final rounds = philIriRoundResults(
      learnerGrade: res.learnerGrade,
      gstScore: gst?.percent,
      readings: readings,
      t: await effectiveThresholds(section.schoolId),
    );
    return PhilIriReportResults(
      learnerGrade: res.learnerGrade,
      rounds: rounds,
      counted: {...readings.keys, if (gst != null) PhilIriRound.bosy},
      sessions: sessions,
      gst: gst,
      notAssessed: philIriNothingAssessed(rounds),
    );
  }

  // ---- helpers ----

  Future<PhilIriThresholds> _thresholdsFor(PhilIriAssessment s, {PhilIriThresholds? current}) async {
    if (s.isFinalized && s.thresholdsSnapshot != null) {
      return PhilIriThresholds.fromMap((jsonDecode(s.thresholdsSnapshot!) as Map).cast<String, Object?>());
    }
    return current ?? await effectiveThresholds(s.schoolId);
  }

  Future<PhilIriPassageResult> _scoreReading(PhilIriReading r, PhilIriThresholds t) async {
    final passage = await _requirePassage(r.passageId);
    final collection = await _collections.findById(passage.collectionId);
    final miscues = await _sessions.getMiscues(r.id!);
    int? correct, total;
    if (collection?.hasComprehension ?? true) {
      final questions = await _passages.getQuestions(passage.id!);
      if (questions.isNotEmpty) {
        total = questions.length;
        var answers = await _sessions.getAnswers(r.id!);
        // Oral follow-up of a silent reading with no questions asked again:
        // its comprehension is the silent reading's (reading coordinator,
        // 2026-10-16: the follow-up is for word recognition).
        if (answers.isEmpty && r.method.isOral) {
          final silent = await _silentReadingFollowedUp(r, passage);
          if (silent != null) {
            answers = await _sessions.getAnswers(silent.id!);
            // A copy of the text in another collection may have other questions.
            if (silent.passageId != passage.id) {
              final n = (await _passages.getQuestions(silent.passageId)).length;
              if (n > 0) total = n;
            }
          }
        }
        correct = answers.where((a) => a.isCorrect).length;
      }
    }
    try {
      return philIriScorePassage(
        wordCount: passage.wordCount,
        method: r.method,
        readingSeconds: r.readingSeconds,
        wordsRead: r.wordsRead,
        countedMiscues: philIriCountedMiscues(miscues),
        comprehensionCorrect: correct,
        comprehensionTotal: total,
        t: t,
      );
    } on ArgumentError catch (e) {
      throw ViewModelException('Reading ${r.id} cannot be scored yet: ${e.message}');
    }
  }

  void _requireFinalizer() {
    final role = _auth.currentUser?.role;
    if (role != UserRole.admin && role != UserRole.coordinator) {
      throw const ViewModelException('Forbidden: only an admin or coordinator can finalize Phil-IRI sessions.');
    }
  }

  /// The section and its grade; refuses anything outside Grades 4-10.
  Future<(Section, int)> _philIriSection(int sectionId) async {
    final section = await _sections.getById(sectionId);
    if (section == null) throw ViewModelException('No section with id $sectionId.');
    final grade = philIriGradeOf(section.gradeLevel);
    if (grade == null) {
      throw ViewModelException('Phil-IRI is for Grade 4-10 sections only (section $sectionId is Grade ${section.gradeLevel}).');
    }
    return (section, grade);
  }

  Future<PhilIriAssessment> _requireSession(int id) async {
    final s = await _sessions.findAssessment(id);
    if (s == null) throw ViewModelException('No Phil-IRI session with id $id.');
    return s;
  }

  Future<PhilIriAssessment> _requireOpenSession(int id) async {
    final s = await _requireSession(id);
    if (s.isFinalized) throw const ViewModelException('This Phil-IRI session is finalized and cannot be changed.');
    return s;
  }

  /// Text keys the learner may not read with [method] in [session], with a
  /// passage for each: every text read in any session, any school year
  /// (no-repeat rule, owner 2026-10-15). Exception (reading coordinator,
  /// 2026-10-16): an oral reading may re-read a text read only SILENTLY, in
  /// another session of the same round and school year, once (a second
  /// reading of it blocks it again). [followUps] receives the texts that
  /// exception opens. Same rule as the local and cloud reading triggers.
  /// Discarded sessions have no readings left, so they don't count.
  Future<Map<String, PhilIriPassage>> _blockedTexts(PhilIriAssessment session, PhilIriReadingMethod method,
      {Set<String>? followUps}) async {
    final blocked = <String, PhilIriPassage>{};
    final open = <String>{};
    for (final s in await _sessions.getByStudent(session.studentId)) {
      for (final r in await _sessions.getReadings(s.id!)) {
        final p = await _passages.findById(r.passageId);
        if (p == null) continue;
        final followUp = method.isOral && !r.method.isOral && s.id != session.id &&
            s.round == session.round && s.schoolYear == session.schoolYear;
        if (followUp) {
          open.add(p.textKey);
        } else {
          blocked[p.textKey] = p;
        }
      }
    }
    followUps?.addAll(open.where((k) => !blocked.containsKey(k)));
    return blocked;
  }

  /// The silent reading an oral [reading] follows up: same learner, round and
  /// school year, another session, same text. Null when there is none.
  Future<PhilIriReading?> _silentReadingFollowedUp(PhilIriReading reading, PhilIriPassage passage) async {
    final session = await _sessions.findAssessment(reading.assessmentId);
    if (session == null) return null;
    PhilIriReading? found;
    for (final s in await _sessions.getByStudent(session.studentId, schoolYear: session.schoolYear)) {
      if (s.id == session.id || s.round != session.round) continue;
      for (final r in await _sessions.getReadings(s.id!)) {
        if (r.method.isOral) continue;
        final p = r.passageId == passage.id ? passage : await _passages.findById(r.passageId);
        if (p != null && p.textKey == passage.textKey) found = r;
      }
    }
    return found;
  }

  Future<PhilIriPassage> _requirePassage(int id) async {
    final p = await _passages.findById(id);
    if (p == null) throw ViewModelException('No passage with id $id (run pull-cloud to get the latest passages).');
    return p;
  }

  Future<PhilIriReading> _findReading(int readingId) async {
    final hit = await _sessions.findReading(readingId);
    if (hit == null) throw ViewModelException('No reading with id $readingId.');
    return hit;
  }

  Future<({PhilIriReading reading, PhilIriPassage passage, PhilIriAssessment session})> _requireOpenReading(
      int readingId) async {
    final reading = await _findReading(readingId);
    final session = await _requireOpenSession(reading.assessmentId);
    return (reading: reading, passage: await _requirePassage(reading.passageId), session: session);
  }

  void _requireOral(PhilIriReading reading) {
    if (!reading.method.isOral) {
      throw const ViewModelException('A silent reading has no miscues (word reading counts as 100%); '
          'for word recognition, give an oral follow-up as another attempt of this round.');
    }
  }

  void _checkWordIndex(PhilIriPassage passage, int wordIndex, PhilIriMiscueType type) {
    final n = passage.words.length;
    final max = type == PhilIriMiscueType.insertion ? n : n - 1;
    if (wordIndex < 0 || wordIndex > max) {
      throw ViewModelException('Word position must be 0..$max for "${passage.title}" ($n words; got $wordIndex).');
    }
  }

  void _checkTiming(PhilIriReadingMethod method, int? seconds, int? wordsRead, {bool required = false}) {
    if (method != PhilIriReadingMethod.oneMinute) {
      if (wordsRead != null) throw const ViewModelException('Words read only applies to one-minute reading.');
      if (seconds == null && required) throw const ViewModelException('Give the reading time in seconds.');
      if (seconds != null) _checkRange('readingSeconds', seconds, 1, 1 << 30);
    } else {
      if (seconds != null) throw const ViewModelException('One-minute reading has no reading time; give the words read.');
      if (wordsRead == null && required) throw const ViewModelException('Give the words read in the minute.');
      if (wordsRead != null) _checkRange('wordsRead', wordsRead, 1, 1 << 30);
    }
  }

  void _checkRange(String name, int value, int min, int max) {
    if (value < min || value > max) {
      throw ViewModelException('$name must be between $min and $max (got $value).');
    }
  }

  static String? _blankToNull(String? s) => (s == null || s.trim().isEmpty) ? null : s.trim();

  /// Runs a repository write; a refusal from a local trigger or the
  /// repository becomes a ViewModelException carrying only its message.
  Future<T> _write<T>(Future<T> Function() write) async {
    try {
      return await write();
    } catch (e) {
      // A record waiting in an upload (sync): say so, whatever else the
      // statement's text happens to contain.
      if ('$e'.contains(pendingLockMessage)) throw const ViewModelException(pendingLockMessage);
      final text = e.toString();
      for (final refusal in _dbRefusals) {
        if (text.contains(refusal)) throw ViewModelException(refusal.endsWith('.') ? refusal : '$refusal.');
      }
      rethrow;
    }
  }

  /// assessed_at / taken_at are DATEs: the tutor's local calendar day.
  static String _localDate(DateTime t) {
    final d = t.toLocal();
    return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
  }
}
