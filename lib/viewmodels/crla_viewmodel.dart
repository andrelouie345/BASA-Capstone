// lib/viewmodels/crla_viewmodel.dart
import 'dart:async';
import 'dart:math' show min;

import '../core/console/logger.dart';
import '../core/models/crla_assessment.dart';
import '../core/repositories/crla_assessment_repository.dart';
import '../core/models/crla_part1_english.dart';
import '../core/models/crla_part1_standard.dart';
import '../core/repositories/crla_part1_english_repository.dart';
import '../core/repositories/crla_part1_standard_repository.dart';
import '../core/models/crla_part2_fluency.dart';
import '../core/models/crla_result.dart';
import '../core/repositories/crla_part2_fluency_repository.dart';
import '../core/repositories/crla_result_repository.dart';
import '../core/models/crla_story.dart';
import '../core/models/crla_variant.dart';
import '../core/repositories/crla_story_repository.dart';
import '../core/repositories/crla_threshold_repository.dart';
import '../core/models/crla_form.dart';
import '../core/repositories/crla_digitized_repository.dart';
import '../core/services/crla_digitized.dart';
import '../core/services/reading_timer.dart';
import '../core/repositories/school_repository.dart';
import '../core/repositories/section_repository.dart';
import '../core/services/crla_rules.dart';
import '../core/services/normalizers.dart';
import '../core/services/sync_upload_rules.dart' show pendingLockMessage;
import 'auth_viewmodel.dart';
import 'viewmodel_exception.dart';
import '../core/services/auth_messages.dart';

/// [CrlaViewModel.removeAttempt] on an attempt already on the server.
const crlaRemoveUploadedMessage =
    'This attempt is already on the server and cannot be removed. Ask your coordinator.';

/// CRLA assessments, offline-first (local database).
///
/// A typed save on an attempt marked in BASA (digitized CRLA, spec D8).
const crlaTypedRefusal = 'This attempt is marked in BASA; change its marks instead of typing totals.';

/// Digitizing an attempt whose school's region, language and grade have no form (spec D10b).
const crlaNoFormMessage =
    "No digitized CRLA form for this school's region, language and grade: enter the totals instead.";

/// Scoring (v14): an assessment snapshots the school's effective thresholds
/// (defaults <- region <- school, from the local crla_thresholds mirror) when
/// it is started. Its Part 1 level and reading profile are computed here with
/// crla_rules.dart from that snapshot and stored, so a later threshold change
/// never rewrites old results. The cloud does the same with its own triggers.
class CrlaViewModel {

  // RAISE(ABORT, ...) texts of the CRLA triggers in local_database.dart.
  // A write refused by one of them is rethrown as a ViewModelException with
  // just this text, not the raw sqflite exception. Keep in sync.
  static const _dbRefusals = [
    'No such section',
    'CRLA is for Grade 1-3 sections only',
    'Section does not belong to that school',
    'Learner has no active enrollment in this section for that school year',
    'Comprehension score is above the maximum for this grade',
    'Reading time is over the limit for this grade',
    'Standard Part 1 requires an mt or fil assessment',
    'English Part 1 requires an eng assessment',
  ];

  final ScopedLogger _log;
  final AuthViewModel _auth;
  final CrlaAssessmentRepository _assessments;
  final CrlaPart1StandardRepository _part1Standard;
  final CrlaPart1EnglishRepository _part1English;
  final CrlaPart2FluencyRepository _part2Fluency;
  final CrlaResultRepository _results;
  final CrlaStoryRepository _stories;
  final SectionRepository _sections;
  final SchoolRepository _schools;
  final CrlaThresholdRepository _thresholds;
  final CrlaDigitizedRepository _digitized;

  List<CrlaAssessment> assessments = [];
  List<CrlaResult> results = [];
  List<CrlaStory> stories = [];
  // Remembers which query populated `assessments`, so refresh() can repeat it.
  int? _lastSectionId;
  String? _lastSchoolYear;

  CrlaViewModel({
    required CrlaAssessmentRepository assessments,
    required CrlaPart1StandardRepository part1Standard,
    required CrlaPart1EnglishRepository part1English,
    required CrlaPart2FluencyRepository part2Fluency,
    required CrlaResultRepository results,
    required CrlaStoryRepository stories,
    required SectionRepository sections,
    required SchoolRepository schools,
    required CrlaThresholdRepository thresholds,
    required CrlaDigitizedRepository digitized,
    required AuthViewModel auth,
    Logger? logger,
  })  : _auth = auth,
        _assessments = assessments,
        _part1Standard = part1Standard,
        _part1English = part1English,
        _part2Fluency = part2Fluency,
        _results = results,
        _stories = stories,
        _sections = sections,
        _schools = schools,
        _thresholds = thresholds,
        _digitized = digitized,
        _log = ScopedLogger(logger, 'CrlaViewModel');

  /// Every public method starts here: signed in, online or offline. Screens
  /// call this ViewModel directly, so the console's own check is not enough.
  void _requireSignIn() {
    final error = _auth.requireActiveSession();
    if (error != null) throw ViewModelException(error);
  }

  Future<void> loadForSection(int sectionId, {String? schoolYear}) async {
    _requireSignIn();
    _log('loadForSection(sectionId: $sectionId, schoolYear: $schoolYear)');
    if (schoolYear != null) schoolYear = normalizeSchoolYear(schoolYear);
    _lastSectionId = sectionId;
    _lastSchoolYear = schoolYear;
    assessments = await _assessments.getBySection(sectionId, schoolYear: schoolYear);
  }

  Future<void> refresh() async {
    _requireSignIn();
    if (_lastSectionId != null) {
      await loadForSection(_lastSectionId!, schoolYear: _lastSchoolYear);
    }
    // No-op if nothing has been loaded yet.
  }

  /// The thresholds a new assessment in [schoolId] is scored with: the
  /// built-in defaults, then the region row, then the school's override.
  Future<CrlaThresholds> effectiveThresholds(int schoolId) async {
    _requireSignIn();
    final region = await _thresholds.getRegion();
    final school = await _thresholds.getForSchool(schoolId);
    return CrlaThresholds.fromMap({...?region?.settings, ...?school?.settings});
  }

  /// Starts a new attempt in [round] (BOSY/MOSY/EOSY). A retake is just
  /// another call with the same student/section/variant/year/round: the DB
  /// assigns the next attempt_no (counted across rounds; the highest in a
  /// round is that round's latest).
  /// The school is taken from the section, which must be Grade 1-3 (CRLA
  /// covers only those). The learner needs an active enrollment in the
  /// section for that year (the DB checks it).
  /// Returns the stored row (with its attempt_no and id).
  Future<CrlaAssessment> startAssessment({
    required int studentId,
    required int sectionId,
    required String schoolYear,
    required String subjectVariant,
    String? language,
    required CrlaRound round,
    String? administeredBy,
    DateTime? assessedAt,
  }) async {
    _requireSignIn();
    _log('startAssessment(studentId: $studentId, sectionId: $sectionId, '
        'variant: $subjectVariant, year: $schoolYear, round: ${round.name})');
    schoolYear = normalizeSchoolYear(schoolYear);

    if (!crlaSubjectVariants.contains(subjectVariant)) {
      throw const ViewModelException('Pick the test: Mother Tongue, Filipino or English.');
    }
    // fil and eng imply their language; mt needs one named.
    final lang = language ?? crlaDefaultLanguage(subjectVariant);
    if (lang == null) throw const ViewModelException('Pick the Mother Tongue language.');
    final section = await _sections.getById(sectionId);
    if (section == null) throw ViewModelException(notOnDeviceMessage('section'));
    if (crlaGradeOf(section.gradeLevel) == null) {
      throw ViewModelException(
          'CRLA is for Grades 1 to 3 only. This section is Grade ${section.gradeLevel}.');
    }

    final snapshot = (await effectiveThresholds(section.schoolId)).toMap();
    final stored = await _write(() => _assessments.insert(
      CrlaAssessment(
        studentId: studentId,
        schoolId: section.schoolId,
        sectionId: sectionId,
        schoolYear: schoolYear,
        subjectVariant: subjectVariant,
        language: lang,
        round: round,
        assessedAt: _localDate(assessedAt ?? DateTime.now()),
        administeredBy: administeredBy,
        thresholdsSnapshot: snapshot,
      ),
    ));
    _log('started assessment ${stored.id} (${round.label}, attempt ${stored.attemptNo})');
    await refresh();
    return stored;
  }

  /// Saves Part 1 for a mt/fil assessment. Inserts, or corrects the existing row.
  /// Returns the stored row with the DB-computed total_score and reading_level.
  Future<CrlaPart1Standard> savePart1Standard({
    required int assessmentId,
    required int task1Score,
    int? task2LowScore,
    int? task2HighScore,
  }) async {
    _requireSignIn();
    _log('savePart1Standard(assessmentId: $assessmentId, task1: $task1Score, '
        'low: $task2LowScore, high: $task2HighScore)');

    final assessment = await _requireVariant(assessmentId, {'mt', 'fil'}, 'Standard Part 1');
    await _requireTyped(assessmentId);
    _checkScore('Task 1', task1Score, 10);
    if (task2LowScore != null) _checkScore('Task 2 low', task2LowScore, 10);
    if (task2HighScore != null) _checkScore('Task 2 high', task2HighScore, 10);

    // Branch rule (same as the DB CHECKs): task 1 below 7 uses the low
    // task 2, 7 or above uses the high one, and never both.
    if (task2LowScore != null && task2HighScore != null) {
      throw const ViewModelException('Enter Task 2 low or Task 2 high, not both.');
    }
    if (task2LowScore != null && task1Score >= 7) {
      throw const ViewModelException('Task 2 low (rhymes and words) is only for a Task 1 score of 0 to 6.');
    }
    if (task2HighScore != null && task1Score < 7) {
      throw const ViewModelException('Task 2 high (sentences) is only for a Task 1 score of 7 or more.');
    }

    return _storeStandard(assessment, task1Score, task2LowScore, task2HighScore);
  }

  /// Writes the standard Part 1 row (typed, or from the marks) and re-scores.
  Future<CrlaPart1Standard> _storeStandard(
      CrlaAssessment assessment, int task1Score, int? task2LowScore, int? task2HighScore) async {
    final assessmentId = assessment.id!;
    final total = task1Score < 7 ? task1Score + (task2LowScore ?? 0) : task1Score + 10 + (task2HighScore ?? 0);
    final part1 = CrlaPart1Standard(
      assessmentId: assessmentId,
      task1Score: task1Score,
      task2LowScore: task2LowScore,
      task2HighScore: task2HighScore,
      readingLevel: crlaPart1StandardLevel(task1Score, total, _thresholdsOf(assessment)),
    );

    final existing = await _part1Standard.findByAssessmentId(assessmentId);
    if (existing != null && existing.task1Score == part1.task1Score && existing.task2LowScore == part1.task2LowScore &&
        existing.task2HighScore == part1.task2HighScore && existing.readingLevel == part1.readingLevel) {
      return existing; // nothing changes (a wrong mark on a task)
    }
    if (existing == null) {
      await _write(() => _part1Standard.insert(part1));
    } else {
      await _write(() => _part1Standard.update(part1));
    }
    await _refreshProfile(assessment);
    return (await _part1Standard.findByAssessmentId(assessmentId))!;
  }

  /// Saves Part 1 for an eng assessment. Inserts, or corrects the existing row.
  Future<CrlaPart1English> savePart1English({
    required int assessmentId,
    required int task1Score,
    int? task2Score,
  }) async {
    _requireSignIn();
    _log('savePart1English(assessmentId: $assessmentId, task1: $task1Score, task2: $task2Score)');

    final assessment = await _requireVariant(assessmentId, {'eng'}, 'English Part 1');
    await _requireTyped(assessmentId);
    _checkScore('Task 1', task1Score, 10);
    if (task2Score != null) {
      _checkScore('Task 2', task2Score, 10);
      if (task1Score < 1) {
        throw const ViewModelException('Task 2 is only for a Task 1 score of 1 or more.');
      }
    }

    return _storeEnglish(assessment, task1Score, task2Score);
  }

  /// Writes the English Part 1 row (typed, or from the marks) and re-scores.
  Future<CrlaPart1English> _storeEnglish(CrlaAssessment assessment, int task1Score, int? task2Score) async {
    final assessmentId = assessment.id!;
    final part1 = CrlaPart1English(
      assessmentId: assessmentId,
      task1Score: task1Score,
      task2Score: task2Score,
      readingLevel: crlaPart1EnglishLevel(task1Score + (task2Score ?? 0), _thresholdsOf(assessment)),
    );

    final existing = await _part1English.findByAssessmentId(assessmentId);
    if (existing != null && existing.task1Score == part1.task1Score && existing.task2Score == part1.task2Score &&
        existing.readingLevel == part1.readingLevel) {
      return existing; // nothing changes (a wrong mark on a task)
    }
    if (existing == null) {
      await _write(() => _part1English.insert(part1));
    } else {
      await _write(() => _part1English.update(part1));
    }
    await _refreshProfile(assessment);
    return (await _part1English.findByAssessmentId(assessmentId))!;
  }

  /// Saves Part 2 for any variant. Inserts, or corrects the existing row.
  /// The comprehension maximum and the reading-time limit depend on the
  /// section's grade and the variant (crla_rules.dart).
  /// Returns the stored row with the DB-computed wpm.
  Future<CrlaPart2Fluency> savePart2Fluency({
    required int assessmentId,
    required int storyNo,
    required int miscues,
    int? wordsRead,
    required int timeMinutes,
    required int timeSeconds,
    required int comprehensionCorrect,
    int? learnerExperienceRating,
    int? observationLevel,
    String? remarks,
  }) async {
    _requireSignIn();
    _log('savePart2Fluency(assessmentId: $assessmentId, story: $storyNo, '
        'miscues: $miscues, typed words: $wordsRead, time: $timeMinutes:$timeSeconds)');

    final assessment = await _requireVariant(assessmentId, {'mt', 'fil', 'eng'}, 'Part 2');
    await _requireTyped(assessmentId);
    final section = await _sections.getById(assessment.sectionId);
    final grade = section == null ? null : crlaGradeOf(section.gradeLevel);
    if (grade == null) {
      throw ViewModelException('Assessment $assessmentId is not in a Grade 1-3 section.');
    }
    final variant = assessment.subjectVariant;
    final timeCap = crlaTimeCapSeconds(grade, variant);

    _checkRange('The story number', storyNo, 1, 2);
    _checkRange('Miscues', miscues, 0, 1 << 30);
    _checkRange('Minutes', timeMinutes, 0, 1 << 30);
    _checkRange('Seconds', timeSeconds, 0, 59);
    _checkRange('Comprehension', comprehensionCorrect, 0, crlaComprehensionMax(grade, variant));
    if (timeMinutes * 60 + timeSeconds > timeCap) {
      throw ViewModelException('Reading time ${_mmss(timeMinutes * 60 + timeSeconds)} is over the '
          'time limit for Grade $grade ${_testName(variant)} (${_mmss(timeCap)}).');
    }
    if (learnerExperienceRating != null) {
      _checkRange('The learner experience rating', learnerExperienceRating, 1, 5);
    }
    if (observationLevel != null) {
      _checkRange('The observation level', observationLevel, 1, 4);
    }
    // Words read follow the CRLA2 scoresheet: story words - miscues (F10).
    final story = await _storyFor(assessment, grade, storyNo);
    final int words;
    try {
      words = crlaWordsRead(storyWords: story?.wordCount, miscues: miscues, typed: wordsRead);
    } on CrlaWordsReadException catch (e) {
      throw ViewModelException(e.message);
    }

    final fluency = CrlaPart2Fluency(
      assessmentId: assessmentId,
      storyNo: storyNo,
      miscues: miscues,
      wordsRead: words,
      timeMinutes: timeMinutes,
      timeSeconds: timeSeconds,
      comprehensionCorrect: comprehensionCorrect,
      learnerExperienceRating: learnerExperienceRating,
      observationLevel: observationLevel,
      remarks: remarks,
    );

    return _storePart2(assessment, fluency);
  }

  /// Writes the Part 2 row (typed, or from the marks) and re-scores.
  Future<CrlaPart2Fluency> _storePart2(CrlaAssessment assessment, CrlaPart2Fluency fluency) async {
    final existing = await _part2Fluency.findByAssessmentId(fluency.assessmentId);
    if (existing == null) {
      await _write(() => _part2Fluency.insert(fluency));
    } else {
      await _write(() => _part2Fluency.update(fluency));
    }
    await _refreshProfile(assessment);
    return (await _part2Fluency.findByAssessmentId(fluency.assessmentId))!;
  }

  /// The combined result for one assessment (Part 1 + Part 2 + reading profile),
  /// or null if the assessment doesn't exist.
  ///
  /// The reading profile stays null until Part 1 is saved. If Part 2 is saved
  /// but pctCorrectWordsRead is null, no crla_stories row matched this
  /// school's region, language, grade and story number.
  Future<CrlaResult?> getResult(int assessmentId) async {
    _requireSignIn();
    _log('getResult(assessmentId: $assessmentId)');
    return _results.findByAssessmentId(assessmentId);
  }

  Future<CrlaAssessment?> getAssessment(int assessmentId) async {
    _requireSignIn();
    _log('getAssessment(assessmentId: $assessmentId)');
    return _assessments.findById(assessmentId);
  }

  /// Loads every attempt in a section (Part 1 + Part 2 + reading profile),
  /// ordered by student, variant, then attempt.
  Future<void> loadResultsForSection(int sectionId, {String? schoolYear}) async {
    _requireSignIn();
    _log('loadResultsForSection(sectionId: $sectionId, schoolYear: $schoolYear)');
    if (schoolYear != null) schoolYear = normalizeSchoolYear(schoolYear);
    results = await _results.getBySection(sectionId, schoolYear: schoolYear);
  }

  /// Loads every attempt for one student, newest first.
  Future<void> loadResultsForStudent(int studentId) async {
    _requireSignIn();
    _log('loadResultsForStudent(studentId: $studentId)');
    results = await _results.getByStudent(studentId);
  }

  /// Loads stories for a region, optionally narrowed by language and/or grade.
  Future<void> loadStories(int regionId, {String? language, int? grade}) async {
    _requireSignIn();
    _log('loadStories(regionId: $regionId, language: $language, grade: $grade)');
    stories = await _stories.getByRegion(regionId, language: language, grade: grade);
  }

  /// The stories one attempt's Part 2 can be read from (story 1 first): the
  /// school's region, the attempt's language and the section's grade, the
  /// same match Part 2 is scored with. For the Part 2 form, so the tutor sees
  /// which title is story 1 and which is story 2. Empty when the region has
  /// no stories for them (words read is then typed).
  Future<List<CrlaStory>> storiesForAttempt(int assessmentId) async {
    _requireSignIn();
    _log('storiesForAttempt(assessmentId: $assessmentId)');
    final a = await _assessments.findById(assessmentId);
    if (a == null) throw ViewModelException(notOnDeviceMessage('CRLA attempt'));
    final section = await _sections.getById(a.sectionId);
    final grade = section == null ? null : crlaGradeOf(section.gradeLevel);
    if (grade == null) {
      throw ViewModelException('Assessment $assessmentId is not in a Grade 1-3 section.');
    }
    return _storiesFor(a, grade);
  }

  /// Removes an attempt started by mistake (wrong learner, test, language
  /// or round) with its Part 1 and Part 2. Only an attempt made on this
  /// device and not uploaded yet (owner 2026-11-15), and only the learner's
  /// latest attempt for that test in that section and year, so attempt
  /// numbers never get a gap. Refused while it waits in an upload or while
  /// an ARAL roster entry uses it.
  Future<void> removeAttempt(int assessmentId) async {
    _requireSignIn();
    _log('removeAttempt($assessmentId)');
    final a = await _assessments.findById(assessmentId);
    if (a == null) throw ViewModelException(notOnDeviceMessage('CRLA attempt'));
    if (assessmentId > 0) throw const ViewModelException(crlaRemoveUploadedMessage);
    final latest = await _assessments.getLatestAttempt(
        studentId: a.studentId, sectionId: a.sectionId, subjectVariant: a.subjectVariant, schoolYear: a.schoolYear);
    if (latest != null && latest.id != a.id) {
      throw ViewModelException('Only the latest attempt can be removed: this is attempt ${a.attemptNo}, '
          'attempt ${latest.attemptNo} of this test is newer.');
    }
    if (await _assessments.aralEntriesUsing(assessmentId) > 0) {
      throw const ViewModelException('An ARAL roster entry uses this attempt. Remove or change that entry first.');
    }
    await _write(() => _assessments.deleteNew(assessmentId));
    await refresh();
  }

  // ---- Digitized CRLA (spec 2026-11-27) ----
  //
  // An attempt with any mark or timer tap is marked in BASA: its Part 1 and
  // Part 2 rows are written here from the marks after every change (the
  // server re-checks them at upload, crla_digitized_problem). Rules: Task 1
  // finished before Task 2, Task 2 the one Task 1 leads to, one story, the
  // timer stops itself at the grade's limit, then the tutor taps the last
  // word reached. Part 2 is written once the timer is stopped (and, after a
  // stop at the limit, once the last word is given).

  /// The attempt's form: Part 1 items per task, the stories with their text
  /// and questions (accepted answers as DepEd prints them).
  Future<CrlaForm> form(int assessmentId) async {
    _requireSignIn();
    _log('form($assessmentId)');
    final c = await _digitizedContext(assessmentId);
    _requireForm(c);
    return CrlaForm(
      assessmentId: assessmentId,
      variant: c.a.subjectVariant,
      language: c.a.language,
      grade: c.grade,
      items: c.items,
      stories: c.stories,
      timeLimitSeconds: crlaTimeCapSeconds(c.grade, c.a.subjectVariant),
    );
  }

  /// The attempt's marks and what they add up to, as of [now] (default now).
  /// Read only: a running timer past the limit is stopped by [storyTimer].
  Future<CrlaDigitizedState> digitized(int assessmentId, {DateTime? now}) async {
    _requireSignIn();
    final c = await _digitizedContext(assessmentId);
    return _digitizedState(c, await _digitized.evidence(assessmentId), now ?? DateTime.now());
  }

  /// Marks a Part 1 item right or wrong ([selfCorrected] counts as right). A
  /// Task 1 change that switches the Task 2 given clears the other Task 2's
  /// marks only with [confirm].
  Future<CrlaDigitizedState> markItem(int assessmentId, CrlaTask task, int itemNo,
          {required bool correct, bool selfCorrected = false, bool confirm = false}) =>
      _marking(assessmentId, 'markItem($assessmentId, ${task.value}, $itemNo, $correct)', 1, (c, ev) async {
        await _changeItem(
            c,
            ev,
            task,
            itemNo,
            CrlaPart1Mark(
              assessmentId: assessmentId,
              task: task,
              itemNo: itemNo,
              correct: correct && !selfCorrected,
              selfCorrected: selfCorrected,
              createdBy: _auth.currentUser?.id,
            ),
            confirm);
      });

  /// Removes an item's mark.
  Future<CrlaDigitizedState> unmarkItem(int assessmentId, CrlaTask task, int itemNo, {bool confirm = false}) =>
      _marking(assessmentId, 'unmarkItem($assessmentId, ${task.value}, $itemNo)', 1,
          (c, ev) => _changeItem(c, ev, task, itemNo, null, confirm));

  /// The tutor is done with [task]: every item not marked yet is wrong, as on paper.
  Future<CrlaDigitizedState> closeTask(int assessmentId, CrlaTask task) =>
      _marking(assessmentId, 'closeTask($assessmentId, ${task.value})', 1, (c, ev) async {
        if (task != CrlaTask.task1) _requireTask2(c, ev, task);
        final marked = {for (final m in ev.part1) if (m.task == task) m.itemNo};
        for (final i in c.items[task] ?? const <CrlaPart1Item>[]) {
          if (marked.contains(i.itemNo)) continue;
          await _write(() => _digitized.setPart1Mark(CrlaPart1Mark(
              assessmentId: assessmentId,
              task: task,
              itemNo: i.itemNo,
              correct: false,
              createdBy: _auth.currentUser?.id)));
        }
      });

  /// Marks a story word (0-based in CrlaFormStory.words) as a miscue or
  /// self-corrected; the same mark again removes it, the other kind changes it.
  Future<CrlaDigitizedState> toggleWord(int assessmentId, int wordIndex,
          {CrlaWordMarkKind kind = CrlaWordMarkKind.miscue}) =>
      _marking(assessmentId, 'toggleWord($assessmentId, $wordIndex, ${kind.value})', 2, (c, ev) async {
        final story = _requireStory(c, ev);
        _requireWord(story, wordIndex);
        final existing = ev.words.where((w) => w.wordIndex == wordIndex).firstOrNull;
        if (existing != null && existing.kind == kind) {
          await _write(() => _digitized.deleteWordMark(assessmentId, wordIndex));
          return;
        }
        final last = c.part2?.lastWordReached;
        if (last != null && wordIndex > last) {
          throw const ViewModelException('That word is after the last word reached.');
        }
        await _write(() => _digitized.setWordMark(CrlaWordMark(
            assessmentId: assessmentId,
            storyNo: story.storyNo,
            wordIndex: wordIndex,
            kind: kind,
            createdBy: _auth.currentUser?.id)));
      });

  /// Marks a comprehension question correct, incorrect or not asked.
  Future<CrlaDigitizedState> answerQuestion(int assessmentId, int questionNo, CrlaAnswerMark mark) =>
      _marking(assessmentId, 'answerQuestion($assessmentId, $questionNo, ${mark.value})', 2, (c, ev) async {
        final story = _requireStory(c, ev);
        if (!story.questions.any((q) => q.questionNo == questionNo)) {
          throw ViewModelException('This story has no question $questionNo.');
        }
        await _write(() => _digitized.setAnswer(CrlaAnswer(
            assessmentId: assessmentId,
            storyNo: story.storyNo,
            questionNo: questionNo,
            mark: mark,
            createdBy: _auth.currentUser?.id)));
      });

  /// Starts timing story [storyNo] (1 or 2) at [at] (default now). The
  /// attempt's Part 2 is then read from that story.
  Future<CrlaDigitizedState> startStoryTimer(int assessmentId, int storyNo, {DateTime? at}) =>
      _storyTap(assessmentId, TimerTapKind.start, at, storyNo: storyNo);

  Future<CrlaDigitizedState> pauseStoryTimer(int assessmentId, {DateTime? at}) =>
      _storyTap(assessmentId, TimerTapKind.pause, at);

  Future<CrlaDigitizedState> resumeStoryTimer(int assessmentId, {DateTime? at}) =>
      _storyTap(assessmentId, TimerTapKind.resume, at);

  /// The learner finished: stops the timer and saves Part 2 from the marks. A
  /// stop after the grade's limit is dated at the limit (then the tutor taps
  /// the last word reached).
  Future<CrlaDigitizedState> stopStoryTimer(int assessmentId, {DateTime? at}) =>
      _storyTap(assessmentId, TimerTapKind.stop, at);

  /// Restarts the timing after a mistake: the earlier taps stay in the log;
  /// the last word reached is cleared and the story is timed again.
  Future<CrlaDigitizedState> resetStoryTimer(int assessmentId, {DateTime? at}) =>
      _storyTap(assessmentId, TimerTapKind.reset, at);

  /// The story's timer as of [now] (default now). A running timer past the
  /// grade's limit is stopped here, dated at the limit (the app may have
  /// been closed when the time ran out).
  Future<CrlaDigitizedState> storyTimer(int assessmentId, {DateTime? now}) async {
    _requireSignIn();
    final when = now ?? DateTime.now();
    return _oneAtATime(assessmentId, () async {
      var c = await _digitizedContext(assessmentId);
      var ev = await _digitized.evidence(assessmentId);
      final story = _storyNoOf(ev);
      if (story != null && await _closeAtLimit(c, ev, story, when)) {
        ev = await _digitized.evidence(assessmentId);
        await _recompute(c, ev, part1: false);
        c = c.withPart2(await _part2Fluency.findByAssessmentId(assessmentId));
      }
      return _digitizedState(c, ev, when);
    });
  }

  /// After the timer stopped: the last word the learner reached (0-based);
  /// words read count up to it. Words marked after it must be unmarked first.
  Future<CrlaDigitizedState> setLastWordReached(int assessmentId, int wordIndex) =>
      _marking(assessmentId, 'setLastWordReached($assessmentId, $wordIndex)', null, (c, ev) async {
        final story = _requireStory(c, ev);
        _requireWord(story, wordIndex);
        final taps = _taps(ev);
        if (timerStatus(taps) != TimerStatus.stopped) {
          throw const ViewModelException('Stop the timer first.');
        }
        if (timedSeconds(taps)! < crlaTimeCapSeconds(c.grade, c.a.subjectVariant)) {
          throw const ViewModelException('The learner finished before the time limit: the whole story counts.');
        }
        if (ev.words.any((w) => w.wordIndex > wordIndex)) {
          throw const ViewModelException('A word after the last word reached is marked; remove that mark first.');
        }
        await _recompute(c, ev, lastWord: wordIndex, part1: false);
      });

  /// The typed fields of a Part 2 (marked or typed): learner experience
  /// (1-5), observation level (1-4) and remarks; a null keeps the saved value.
  Future<CrlaPart2Fluency> saveObservation(int assessmentId,
      {int? learnerExperienceRating, int? observationLevel, String? remarks}) async {
    _requireSignIn();
    _log('saveObservation($assessmentId)');
    if (learnerExperienceRating != null) _checkRange('The learner experience rating', learnerExperienceRating, 1, 5);
    if (observationLevel != null) _checkRange('The observation level', observationLevel, 1, 4);
    return _oneAtATime(assessmentId, () async {
      final a = await _assessments.findById(assessmentId);
      if (a == null) throw ViewModelException(notOnDeviceMessage('CRLA attempt'));
      final p = await _part2Fluency.findByAssessmentId(assessmentId);
      if (p == null) throw const ViewModelException('Time the story first.');
      return _storePart2(
          a,
          _part2With(p,
              learnerExperienceRating: learnerExperienceRating, observationLevel: observationLevel, remarks: remarks));
    });
  }

  /// Before sending (SyncViewModel.uploadChecks, final review I2): the
  /// learners whose story timing isn't finished on this device (the timer
  /// still running or paused, or stopped at the limit without the last word).
  /// The server would refuse such an upload, or count the whole story; null
  /// when every timing is finished.
  Future<String?> unfinishedTimingMessage() async {
    _requireSignIn();
    final names = <String>{};
    for (final c in await _digitized.attemptsWithUnsentTimerTaps()) {
      final s = await digitized(c.assessmentId);
      if (s.timerStatus != TimerStatus.stopped || s.lastWordNeeded) names.add('${c.lastName}, ${c.firstName}');
    }
    if (names.isEmpty) return null;
    return 'Finish the CRLA story timing of ${names.join('; ')} first (stop the timer, or tap the last word '
        'reached), then send.';
  }

  // ---- Digitized helpers ----

  /// One digitized write at a time per attempt, so a double tap or a tap and
  /// the automatic stop can't both pass the checks (as the Phil-IRI timer).
  final _digitizedChains = <int, Future<void>>{};

  Future<T> _oneAtATime<T>(int assessmentId, Future<T> Function() body) {
    final done = Completer<void>();
    final before = _digitizedChains[assessmentId] ?? Future<void>.value();
    _digitizedChains[assessmentId] = done.future;
    return before.then((_) => body()).whenComplete(() {
      done.complete();
      if (identical(_digitizedChains[assessmentId], done.future)) _digitizedChains.remove(assessmentId);
    });
  }

  /// A mark: signed in, one at a time, a form, not typed; then the totals.
  /// [part] is the Part a call changes (1 or 2; null = the call writes the
  /// totals itself): only that Part is written again.
  Future<CrlaDigitizedState> _marking(
      int assessmentId, String what, int? part, Future<void> Function(_CrlaDigitizedContext c, CrlaEvidence ev) body,
      {DateTime? now}) async {
    _requireSignIn(); // async: a refusal is a failed Future, as every other call
    _log(what);
    return _oneAtATime(assessmentId, () async {
      var c = await _digitizedContext(assessmentId);
      await _requireDigitizable(c);
      await body(c, await _digitized.evidence(assessmentId));
      final ev = await _digitized.evidence(assessmentId);
      if (part != null) await _recompute(c, ev, part1: part == 1, part2: part == 2);
      c = c.withPart2(await _part2Fluency.findByAssessmentId(assessmentId));
      return _digitizedState(c, ev, now ?? DateTime.now());
    });
  }

  Future<CrlaDigitizedState> _storyTap(int assessmentId, TimerTapKind kind, DateTime? at, {int? storyNo}) =>
      _marking(assessmentId, 'storyTimer ${kind.value}($assessmentId)', 2, now: at, (c, ev) async {
        final when = at ?? DateTime.now();
        final current = _storyNoOf(ev);
        if (storyNo != null && current != null && storyNo != current) {
          throw const ViewModelException('This attempt is marked on its other story.');
        }
        final story = storyNo ?? current;
        if (story == null) throw const ViewModelException('Start the timer on a story first.');
        if (!c.stories.any((s) => s.storyNo == story)) {
          throw ViewModelException('This form has no story $story.');
        }
        if (await _closeAtLimit(c, ev, story, when)) {
          if (kind == TimerTapKind.stop) return; // the time ran out first: stopped at the limit
          ev = await _digitized.evidence(assessmentId);
        }
        final problem = timerProblem(_taps(ev), kind, when);
        if (problem != null) throw ViewModelException(problem);
        if (kind == TimerTapKind.reset) await _clearLastWord(c);
        await _addStoryTap(assessmentId, story, ev, kind, when);
      });

  /// A running timer past the grade's limit gets its stop, dated at the limit.
  Future<bool> _closeAtLimit(_CrlaDigitizedContext c, CrlaEvidence ev, int story, DateTime now) async {
    final taps = _taps(ev);
    if (timerStatus(taps) != TimerStatus.running) return false;
    final limit = Duration(seconds: crlaTimeCapSeconds(c.grade, c.a.subjectVariant));
    if (timerElapsed(taps, now) < limit) return false;
    await _addStoryTap(c.a.id!, story, ev, TimerTapKind.stop, limitMark(taps, limit));
    return true;
  }

  Future<void> _addStoryTap(int assessmentId, int story, CrlaEvidence ev, TimerTapKind kind, DateTime at) =>
      _write(() => _digitized.insertTimerEvent(CrlaTimerEvent(
            assessmentId: assessmentId,
            storyNo: story,
            seq: ev.timer.length + 1,
            kind: kind,
            at: at,
            createdBy: _auth.currentUser?.id,
          )));

  /// A restart: the Part 2 row keeps its numbers until the new timing stops,
  /// without the old timing's last word.
  Future<void> _clearLastWord(_CrlaDigitizedContext c) async {
    final p = c.part2;
    if (p == null || p.lastWordReached == null) return;
    await _write(() => _part2Fluency.update(_part2With(p, clearLastWord: true)));
  }

  /// [p] with the typed fields or the last word replaced.
  static CrlaPart2Fluency _part2With(CrlaPart2Fluency p,
          {int? learnerExperienceRating, int? observationLevel, String? remarks, bool clearLastWord = false}) =>
      CrlaPart2Fluency(
        assessmentId: p.assessmentId,
        storyNo: p.storyNo,
        miscues: p.miscues,
        wordsRead: p.wordsRead,
        timeMinutes: p.timeMinutes,
        timeSeconds: p.timeSeconds,
        comprehensionCorrect: p.comprehensionCorrect,
        learnerExperienceRating: learnerExperienceRating ?? p.learnerExperienceRating,
        observationLevel: observationLevel ?? p.observationLevel,
        remarks: remarks ?? p.remarks,
        lastWordReached: clearLastWord ? null : p.lastWordReached,
      );

  Future<void> _changeItem(_CrlaDigitizedContext c, CrlaEvidence ev, CrlaTask task, int itemNo, CrlaPart1Mark? mark,
      bool confirm) async {
    final id = c.a.id!;
    if (task != CrlaTask.task1) _requireTask2(c, ev, task);
    if (!(c.items[task] ?? const <CrlaPart1Item>[]).any((i) => i.itemNo == itemNo)) {
      throw ViewModelException('This task has no item $itemNo.');
    }
    if (task == CrlaTask.task1) {
      final after = [
        for (final m in ev.part1)
          if (!(m.task == task && m.itemNo == itemNo)) m,
        if (mark != null) mark,
      ];
      final before = crlaTask2For(c.a.subjectVariant, _score(ev.part1, CrlaTask.task1));
      final now = crlaTask2For(c.a.subjectVariant, _score(after, CrlaTask.task1));
      if (before != null && before != now && ev.part1.any((m) => m.task == before)) {
        if (!confirm) throw const ViewModelException('This changes which Task 2 is given; confirm to clear its marks.');
        await _write(() => _digitized.deletePart1Marks(id, before));
      }
    }
    if (mark == null) {
      final last = ev.part1.length == 1 && ev.part1.single.task == task && ev.part1.single.itemNo == itemNo;
      if (last && id > 0 && await _part1Row(c.a) != null) {
        throw const ViewModelException(
            'This attempt is already on the server: change its last Part 1 mark instead of removing it.');
      }
      await _write(() => _digitized.deletePart1Mark(id, task, itemNo));
    } else {
      await _write(() => _digitized.setPart1Mark(mark));
    }
  }

  /// A Task 2 is marked only after Task 1, and only the one Task 1 leads to.
  void _requireTask2(_CrlaDigitizedContext c, CrlaEvidence ev, CrlaTask task) {
    final task1Items = c.items[CrlaTask.task1]?.length ?? 0;
    if (ev.part1.where((m) => m.task == CrlaTask.task1).length < task1Items) {
      throw const ViewModelException('Finish Task 1 first.');
    }
    final leads = crlaTask2For(c.a.subjectVariant, _score(ev.part1, CrlaTask.task1));
    if (leads == null) throw const ViewModelException('Task 1 is 0: the test ends here.');
    if (task != leads) throw const ViewModelException('This Task 2 is not the one Task 1 leads to.');
  }

  /// A task's score as the form counts it: at most 10 (the server's least(10, ...)).
  static int _score(List<CrlaPart1Mark> marks, CrlaTask task) => min(10, crlaTaskScore(marks, task));

  /// Writes the Part 1 / Part 2 rows from the marks (spec D8).
  Future<void> _recompute(_CrlaDigitizedContext c, CrlaEvidence ev,
      {int? lastWord, bool part1 = true, bool part2 = true}) async {
    final a = c.a;
    if (part1 && ev.part1.isEmpty && a.id! < 0 && await _part1Row(a) != null) {
      await _write(() => _digitized.deletePart1(a.id!));
      await _refreshProfile(a);
    }
    if (part1 && ev.part1.isNotEmpty) {
      final t1 = _score(ev.part1, CrlaTask.task1);
      final leads = crlaTask2For(a.subjectVariant, t1);
      final t2 = leads == null || !ev.part1.any((m) => m.task == leads) ? null : _score(ev.part1, leads);
      if (a.subjectVariant == 'eng') {
        await _storeEnglish(a, t1, t2);
      } else {
        await _storeStandard(a, t1, leads == CrlaTask.task2Low ? t2 : null, leads == CrlaTask.task2High ? t2 : null);
      }
    }
    final storyNo = _storyNoOf(ev);
    if (!part2 || storyNo == null) return;
    final story = c.stories.where((s) => s.storyNo == storyNo).firstOrNull;
    final seconds = timedSeconds(_taps(ev));
    if (story == null || seconds == null) return; // not stopped yet
    final existing = c.part2;
    final last = lastWord ?? existing?.lastWordReached;
    if (seconds >= crlaTimeCapSeconds(c.grade, a.subjectVariant) && last == null) return; // last word first
    await _storePart2(
        a,
        CrlaPart2Fluency(
          assessmentId: a.id!,
          storyNo: storyNo,
          miscues: ev.words.where((w) => w.kind == CrlaWordMarkKind.miscue).length,
          wordsRead: crlaDigitizedWordsRead(wordCount: story.wordCount, lastWordReached: last, marks: ev.words),
          timeMinutes: seconds ~/ 60,
          timeSeconds: seconds % 60,
          comprehensionCorrect: crlaComprehensionFromAnswers(ev.answers),
          learnerExperienceRating: existing?.learnerExperienceRating,
          observationLevel: existing?.observationLevel,
          remarks: existing?.remarks,
          lastWordReached: last,
        ));
  }

  CrlaDigitizedState _digitizedState(_CrlaDigitizedContext c, CrlaEvidence ev, DateTime now) {
    final taps = _taps(ev);
    final seconds = timedSeconds(taps);
    final limit = crlaTimeCapSeconds(c.grade, c.a.subjectVariant);
    final t1 = _score(ev.part1, CrlaTask.task1);
    final leads = crlaTask2For(c.a.subjectVariant, t1);
    final task1Items = c.items[CrlaTask.task1]?.length ?? 0;
    final part2 = ev.isEmpty ? null : c.part2;
    final last = part2?.lastWordReached;
    return CrlaDigitizedState(
      assessmentId: c.a.id!,
      evidence: ev,
      isDigitized: !ev.isEmpty,
      task1Score: t1,
      task1Done: task1Items > 0 && ev.part1.where((m) => m.task == CrlaTask.task1).length >= task1Items,
      task2: leads,
      task2Score: leads == null || !ev.part1.any((m) => m.task == leads) ? null : _score(ev.part1, leads),
      storyNo: _storyNoOf(ev),
      timerStatus: timerStatus(taps),
      elapsed: timerElapsed(taps, now),
      timedSeconds: seconds,
      timeLimitSeconds: limit,
      lastWordNeeded: seconds != null && seconds >= limit && last == null,
      lastWordReached: last,
      miscues: ev.words.where((w) => w.kind == CrlaWordMarkKind.miscue).length,
      wordsRead: part2?.wordsRead,
      comprehension: crlaComprehensionFromAnswers(ev.answers),
    );
  }

  static List<TimerTap> _taps(CrlaEvidence ev) => [for (final e in ev.timer) e.tap];

  /// The story the attempt's Part 2 evidence is on; null before any.
  static int? _storyNoOf(CrlaEvidence ev) =>
      ev.timer.firstOrNull?.storyNo ?? ev.words.firstOrNull?.storyNo ?? ev.answers.firstOrNull?.storyNo;

  CrlaFormStory _requireStory(_CrlaDigitizedContext c, CrlaEvidence ev) {
    final no = _storyNoOf(ev);
    final story = no == null ? null : c.stories.where((s) => s.storyNo == no).firstOrNull;
    if (story == null) throw const ViewModelException('Start the timer on a story first.');
    return story;
  }

  static void _requireWord(CrlaFormStory story, int wordIndex) {
    if (wordIndex < 0 || wordIndex >= story.words.length) {
      throw ViewModelException('Word position is outside the story (${story.words.length} words).');
    }
  }

  void _requireForm(_CrlaDigitizedContext c) {
    if (c.items.isEmpty || c.stories.isEmpty) throw const ViewModelException(crlaNoFormMessage);
  }

  /// A form exists, and the attempt isn't one whose totals were typed in.
  Future<void> _requireDigitizable(_CrlaDigitizedContext c) async {
    _requireForm(c);
    final id = c.a.id!;
    if (await _digitized.hasEvidence(id)) return;
    final typedPart1 = c.a.subjectVariant == 'eng'
        ? await _part1English.findByAssessmentId(id) != null
        : await _part1Standard.findByAssessmentId(id) != null;
    if (typedPart1 || c.part2 != null) {
      throw const ViewModelException(
          "This attempt's totals were typed in; keep typing them, or remove the attempt and start again.");
    }
  }

  /// The attempt's Part 1 row (standard or English), or null.
  Future<Object?> _part1Row(CrlaAssessment a) async => a.subjectVariant == 'eng'
      ? await _part1English.findByAssessmentId(a.id!)
      : await _part1Standard.findByAssessmentId(a.id!);

  /// Typed saves are for attempts without marks (spec D8).
  Future<void> _requireTyped(int assessmentId) async {
    if (await _digitized.hasEvidence(assessmentId)) throw const ViewModelException(crlaTypedRefusal);
  }

  Future<_CrlaDigitizedContext> _digitizedContext(int assessmentId) async {
    final a = await _assessments.findById(assessmentId);
    if (a == null) throw ViewModelException(notOnDeviceMessage('CRLA attempt'));
    final section = await _sections.getById(a.sectionId);
    final grade = section == null ? null : crlaGradeOf(section.gradeLevel);
    if (grade == null) throw ViewModelException('Assessment $assessmentId is not in a Grade 1-3 section.');
    final regionId = (await _schools.getById(a.schoolId))?.regionId;
    // Read every call, not cached: content can reach the device later (a pull
    // after the update, a seed correction), and reads cost little (final
    // review I1).
    final content = regionId == null
        ? (items: const <CrlaTask, List<CrlaPart1Item>>{}, stories: const <CrlaFormStory>[])
        : await _loadFormContent(a, regionId, grade);
    return _CrlaDigitizedContext(
        a, grade, content.items, content.stories, await _part2Fluency.findByAssessmentId(assessmentId));
  }

  Future<({Map<CrlaTask, List<CrlaPart1Item>> items, List<CrlaFormStory> stories})> _loadFormContent(
      CrlaAssessment a, int regionId, int grade) async {
    final items = <CrlaTask, List<CrlaPart1Item>>{};
    final stories = <CrlaFormStory>[];
    {
      for (final i in await _digitized.part1Items(regionId: regionId, language: a.language, grade: grade)) {
        (items[i.task] ??= []).add(i);
      }
      for (final s in await _storiesFor(a, grade)) {
        final body = await _digitized.storyBody(s.id!);
        if (body == null || body.trim().isEmpty) continue;
        stories.add(CrlaFormStory(
          storyNo: s.storyNo,
          title: s.title,
          wordCount: s.wordCount,
          sentences: crlaStorySentences(body),
          words: crlaStoryWords(body),
          questions: await _digitized.questions(s.id!),
        ));
      }
    }
    return (items: items, stories: stories);
  }

  // ---- helpers ----

  /// The assessment's snapshot; rows from before v14 have none (defaults).
  CrlaThresholds _thresholdsOf(CrlaAssessment a) =>
      CrlaThresholds.fromMap(a.thresholdsSnapshot ?? const {});

  /// The stories an assessment's Part 2 is read from (school's region, the
  /// assessment's language, the section's grade), story 1 first; empty when
  /// the region has none. The one match rule for scoring and the Part 2 list.
  Future<List<CrlaStory>> _storiesFor(CrlaAssessment a, int grade) async {
    final regionId = (await _schools.getById(a.schoolId))?.regionId;
    if (regionId == null) return const [];
    return [...await _stories.getByRegion(regionId, language: a.language, grade: grade)]
      ..sort((x, y) => x.storyNo.compareTo(y.storyNo));
  }

  /// The story an assessment's Part 2 was read from, or null when the region
  /// has no such story.
  Future<CrlaStory?> _storyFor(CrlaAssessment a, int grade, int storyNo) async =>
      (await _storiesFor(a, grade)).where((s) => s.storyNo == storyNo).firstOrNull;

  /// Re-scores the stored reading profile from Part 1 + Part 2 and the
  /// story's exact word count (same match as crla_results: the school's
  /// region, the assessment's language, the section's grade, the story no).
  Future<void> _refreshProfile(CrlaAssessment a) async {
    final section = await _sections.getById(a.sectionId);
    final grade = section == null ? null : crlaGradeOf(section.gradeLevel);
    if (grade == null) return; // not a CRLA section; nothing to score
    final level = a.subjectVariant == 'eng'
        ? (await _part1English.findByAssessmentId(a.id!))?.readingLevel
        : (await _part1Standard.findByAssessmentId(a.id!))?.readingLevel;
    final part2 = await _part2Fluency.findByAssessmentId(a.id!);

    double? pct;
    if (part2 != null) {
      final story = await _storyFor(a, grade, part2.storyNo);
      if (story != null && story.wordCount > 0) pct = part2.wordsRead / story.wordCount;
    }

    final profile = crlaReadingProfile(
      part1Level: level,
      pct: pct,
      comprehension: part2?.comprehensionCorrect,
      grade: grade,
      variant: a.subjectVariant,
      t: _thresholdsOf(a),
    );
    if ((await _assessments.findById(a.id!))?.readingProfile == profile) return;
    await _write(() => _assessments.setReadingProfile(a.id!, profile));
  }

  Future<CrlaAssessment> _requireVariant(
    int assessmentId,
    Set<String> allowed,
    String what,
  ) async {
    final a = await _assessments.findById(assessmentId);
    if (a == null) {
      throw ViewModelException(notOnDeviceMessage('CRLA attempt'));
    }
    if (!allowed.contains(a.subjectVariant)) {
      throw ViewModelException(
        '$what is not for this attempt: it is a ${_testName(a.subjectVariant)} attempt.',
      );
    }
    return a;
  }

  void _checkScore(String name, int value, int max) => _checkRange(name, value, 0, max);

  void _checkRange(String name, int value, int min, int max) {
    if (value < min || value > max) {
      throw ViewModelException('$name must be from $min to $max. You entered $value.');
    }
  }

  /// Runs a repository write; a refusal from one of our DB triggers becomes a
  /// ViewModelException carrying only the trigger's message.
  Future<T> _write<T>(Future<T> Function() write) async {
    try {
      return await write();
    } catch (e) {
      // A record waiting in an upload (sync): say so, whatever else the
      // statement's text happens to contain.
      if ('$e'.contains(pendingLockMessage)) throw const ViewModelException(pendingLockMessage);
      final text = e.toString();
      for (final refusal in _dbRefusals) {
        if (text.contains(refusal)) throw ViewModelException('$refusal.');
      }
      rethrow;
    }
  }

  /// The test's name for a refusal ("Mother Tongue"), never the code.
  static String _testName(String variant) =>
      const {'mt': 'Mother Tongue', 'fil': 'Filipino', 'eng': 'English'}[variant] ?? variant;

  static String _mmss(int seconds) =>
      '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';

  /// assessed_at is a DATE in Postgres: the tutor's local calendar day, not
  /// the UTC one (before 08:00 in the Philippines those differ).
  static String _localDate(DateTime t) {
    final d = t.toLocal();
    return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
  }
}

/// What a digitized call reads about its attempt (loaded once per call).
class _CrlaDigitizedContext {
  final CrlaAssessment a;
  final int grade;
  final Map<CrlaTask, List<CrlaPart1Item>> items;
  final List<CrlaFormStory> stories;
  final CrlaPart2Fluency? part2;
  const _CrlaDigitizedContext(this.a, this.grade, this.items, this.stories, this.part2);

  _CrlaDigitizedContext withPart2(CrlaPart2Fluency? p) => _CrlaDigitizedContext(a, grade, items, stories, p);
}
