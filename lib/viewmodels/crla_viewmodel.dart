// lib/viewmodels/crla_viewmodel.dart
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
import '../core/repositories/crla_story_repository.dart';
import '../core/repositories/crla_threshold_repository.dart';
import '../core/repositories/school_repository.dart';
import '../core/repositories/section_repository.dart';
import '../core/services/crla_rules.dart';
import '../core/services/normalizers.dart';
import 'viewmodel_exception.dart';

/// CRLA assessments, offline-first (local database).
///
/// Scoring (v14): an assessment snapshots the school's effective thresholds
/// (defaults <- region <- school, from the local crla_thresholds mirror) when
/// it is started. Its Part 1 level and reading profile are computed here with
/// crla_rules.dart from that snapshot and stored, so a later threshold change
/// never rewrites old results. The cloud does the same with its own triggers.
class CrlaViewModel {
  static const _variants = {'mt', 'fil', 'eng'};

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
  final CrlaAssessmentRepository _assessments;
  final CrlaPart1StandardRepository _part1Standard;
  final CrlaPart1EnglishRepository _part1English;
  final CrlaPart2FluencyRepository _part2Fluency;
  final CrlaResultRepository _results;
  final CrlaStoryRepository _stories;
  final SectionRepository _sections;
  final SchoolRepository _schools;
  final CrlaThresholdRepository _thresholds;

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
    Logger? logger,
  })  : _assessments = assessments,
        _part1Standard = part1Standard,
        _part1English = part1English,
        _part2Fluency = part2Fluency,
        _results = results,
        _stories = stories,
        _sections = sections,
        _schools = schools,
        _thresholds = thresholds,
        _log = ScopedLogger(logger, 'CrlaViewModel');

  Future<void> loadForSection(int sectionId, {String? schoolYear}) async {
    _log('loadForSection(sectionId: $sectionId, schoolYear: $schoolYear)');
    if (schoolYear != null) schoolYear = normalizeSchoolYear(schoolYear);
    _lastSectionId = sectionId;
    _lastSchoolYear = schoolYear;
    assessments = await _assessments.getBySection(sectionId, schoolYear: schoolYear);
  }

  Future<void> refresh() async {
    if (_lastSectionId != null) {
      await loadForSection(_lastSectionId!, schoolYear: _lastSchoolYear);
    }
    // No-op if nothing has been loaded yet.
  }

  /// The thresholds a new assessment in [schoolId] is scored with: the
  /// built-in defaults, then the region row, then the school's override.
  Future<CrlaThresholds> effectiveThresholds(int schoolId) async {
    final region = await _thresholds.getRegion();
    final school = await _thresholds.getForSchool(schoolId);
    return CrlaThresholds.fromMap({...?region?.settings, ...?school?.settings});
  }

  /// Starts a new attempt. A retake is just another call with the same
  /// student/section/variant/year: the DB assigns the next attempt_no.
  /// The school is taken from the section, which must be Grade 1-3 (CRLA
  /// covers only those). The learner needs an active enrollment in the
  /// section for that year (the DB checks it).
  /// Returns the stored row (with its attempt_no and id).
  Future<CrlaAssessment> startAssessment({
    required int studentId,
    required int sectionId,
    required String schoolYear,
    required String subjectVariant,
    required String language,
    String? administeredBy,
    DateTime? assessedAt,
  }) async {
    _log('startAssessment(studentId: $studentId, sectionId: $sectionId, '
        'variant: $subjectVariant, year: $schoolYear)');
    schoolYear = normalizeSchoolYear(schoolYear);

    if (!_variants.contains(subjectVariant)) {
      throw ViewModelException("Variant must be one of mt, fil, eng (got '$subjectVariant').");
    }
    final section = await _sections.getById(sectionId);
    if (section == null) throw ViewModelException('No section with id $sectionId.');
    if (crlaGradeOf(section.gradeLevel) == null) {
      throw ViewModelException(
          'CRLA is for Grade 1-3 sections only (section $sectionId is Grade ${section.gradeLevel}).');
    }

    final snapshot = (await effectiveThresholds(section.schoolId)).toMap();
    final stored = await _write(() => _assessments.insert(
      CrlaAssessment(
        studentId: studentId,
        schoolId: section.schoolId,
        sectionId: sectionId,
        schoolYear: schoolYear,
        subjectVariant: subjectVariant,
        language: language,
        assessedAt: _localDate(assessedAt ?? DateTime.now()),
        administeredBy: administeredBy,
        thresholdsSnapshot: snapshot,
      ),
    ));
    _log('started assessment ${stored.id} (attempt ${stored.attemptNo})');
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
    _log('savePart1Standard(assessmentId: $assessmentId, task1: $task1Score, '
        'low: $task2LowScore, high: $task2HighScore)');

    final assessment = await _requireVariant(assessmentId, {'mt', 'fil'}, 'Standard Part 1');
    _checkScore('task1Score', task1Score, 10);
    if (task2LowScore != null) _checkScore('task2LowScore', task2LowScore, 10);
    if (task2HighScore != null) _checkScore('task2HighScore', task2HighScore, 10);

    // Branch rule (same as the DB CHECKs): task 1 below 7 uses the low
    // task 2, 7 or above uses the high one, and never both.
    if (task2LowScore != null && task2HighScore != null) {
      throw const ViewModelException('Provide task2LowScore or task2HighScore, not both.');
    }
    if (task2LowScore != null && task1Score >= 7) {
      throw const ViewModelException('task2LowScore only applies when task1Score is below 7.');
    }
    if (task2HighScore != null && task1Score < 7) {
      throw const ViewModelException('task2HighScore only applies when task1Score is 7 or above.');
    }

    final total = task1Score < 7 ? task1Score + (task2LowScore ?? 0) : task1Score + 10 + (task2HighScore ?? 0);
    final part1 = CrlaPart1Standard(
      assessmentId: assessmentId,
      task1Score: task1Score,
      task2LowScore: task2LowScore,
      task2HighScore: task2HighScore,
      readingLevel: crlaPart1StandardLevel(task1Score, total, _thresholdsOf(assessment)),
    );

    final existing = await _part1Standard.findByAssessmentId(assessmentId);
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
    _log('savePart1English(assessmentId: $assessmentId, task1: $task1Score, task2: $task2Score)');

    final assessment = await _requireVariant(assessmentId, {'eng'}, 'English Part 1');
    _checkScore('task1Score', task1Score, 10);
    if (task2Score != null) {
      _checkScore('task2Score', task2Score, 10);
      if (task1Score < 1) {
        throw const ViewModelException('task2Score only applies when task1Score is 1 or above.');
      }
    }

    final part1 = CrlaPart1English(
      assessmentId: assessmentId,
      task1Score: task1Score,
      task2Score: task2Score,
      readingLevel: crlaPart1EnglishLevel(task1Score + (task2Score ?? 0), _thresholdsOf(assessment)),
    );

    final existing = await _part1English.findByAssessmentId(assessmentId);
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
    required int wordsRead,
    required int timeMinutes,
    required int timeSeconds,
    required int comprehensionCorrect,
    int? learnerExperienceRating,
    int? observationLevel,
    String? remarks,
  }) async {
    _log('savePart2Fluency(assessmentId: $assessmentId, story: $storyNo, '
        'words: $wordsRead, miscues: $miscues, time: $timeMinutes:$timeSeconds)');

    final assessment = await _requireVariant(assessmentId, {'mt', 'fil', 'eng'}, 'Part 2');
    final section = await _sections.getById(assessment.sectionId);
    final grade = section == null ? null : crlaGradeOf(section.gradeLevel);
    if (grade == null) {
      throw ViewModelException('Assessment $assessmentId is not in a Grade 1-3 section.');
    }
    final variant = assessment.subjectVariant;
    final timeCap = crlaTimeCapSeconds(grade, variant);

    _checkRange('storyNo', storyNo, 1, 2);
    _checkRange('miscues', miscues, 0, 1 << 30);
    _checkRange('wordsRead', wordsRead, 0, 1 << 30);
    _checkRange('timeMinutes', timeMinutes, 0, 1 << 30);
    _checkRange('timeSeconds', timeSeconds, 0, 59);
    _checkRange('comprehensionCorrect', comprehensionCorrect, 0, crlaComprehensionMax(grade, variant));
    if (timeMinutes * 60 + timeSeconds > timeCap) {
      throw ViewModelException('Reading time ${_mmss(timeMinutes * 60 + timeSeconds)} is over the '
          'Grade $grade $variant limit of ${_mmss(timeCap)}.');
    }
    if (learnerExperienceRating != null) {
      _checkRange('learnerExperienceRating', learnerExperienceRating, 1, 5);
    }
    if (observationLevel != null) {
      _checkRange('observationLevel', observationLevel, 1, 4);
    }

    final fluency = CrlaPart2Fluency(
      assessmentId: assessmentId,
      storyNo: storyNo,
      miscues: miscues,
      wordsRead: wordsRead,
      timeMinutes: timeMinutes,
      timeSeconds: timeSeconds,
      comprehensionCorrect: comprehensionCorrect,
      learnerExperienceRating: learnerExperienceRating,
      observationLevel: observationLevel,
      remarks: remarks,
    );

    final existing = await _part2Fluency.findByAssessmentId(assessmentId);
    if (existing == null) {
      await _write(() => _part2Fluency.insert(fluency));
    } else {
      await _write(() => _part2Fluency.update(fluency));
    }
    await _refreshProfile(assessment);
    return (await _part2Fluency.findByAssessmentId(assessmentId))!;
  }

  /// The combined result for one assessment (Part 1 + Part 2 + reading profile),
  /// or null if the assessment doesn't exist.
  ///
  /// The reading profile stays null until Part 1 is saved. If Part 2 is saved
  /// but pctCorrectWordsRead is null, no crla_stories row matched this
  /// school's region, language, grade and story number.
  Future<CrlaResult?> getResult(int assessmentId) {
    _log('getResult(assessmentId: $assessmentId)');
    return _results.findByAssessmentId(assessmentId);
  }

  Future<CrlaAssessment?> getAssessment(int assessmentId) {
    _log('getAssessment(assessmentId: $assessmentId)');
    return _assessments.findById(assessmentId);
  }

  /// Loads every attempt in a section (Part 1 + Part 2 + reading profile),
  /// ordered by student, variant, then attempt.
  Future<void> loadResultsForSection(int sectionId, {String? schoolYear}) async {
    _log('loadResultsForSection(sectionId: $sectionId, schoolYear: $schoolYear)');
    if (schoolYear != null) schoolYear = normalizeSchoolYear(schoolYear);
    results = await _results.getBySection(sectionId, schoolYear: schoolYear);
  }

  /// Loads every attempt for one student, newest first.
  Future<void> loadResultsForStudent(int studentId) async {
    _log('loadResultsForStudent(studentId: $studentId)');
    results = await _results.getByStudent(studentId);
  }

  /// Loads stories for a region, optionally narrowed by language and/or grade.
  Future<void> loadStories(int regionId, {String? language, int? grade}) async {
    _log('loadStories(regionId: $regionId, language: $language, grade: $grade)');
    stories = await _stories.getByRegion(regionId, language: language, grade: grade);
  }

  // ---- helpers ----

  /// The assessment's snapshot; rows from before v14 have none (defaults).
  CrlaThresholds _thresholdsOf(CrlaAssessment a) =>
      CrlaThresholds.fromMap(a.thresholdsSnapshot ?? const {});

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
      final regionId = (await _schools.getById(a.schoolId))?.regionId;
      if (regionId != null) {
        final story = (await _stories.getByRegion(regionId, language: a.language, grade: grade))
            .where((s) => s.storyNo == part2.storyNo)
            .firstOrNull;
        if (story != null && story.wordCount > 0) pct = part2.wordsRead / story.wordCount;
      }
    }

    final profile = crlaReadingProfile(
      part1Level: level,
      pct: pct,
      comprehension: part2?.comprehensionCorrect,
      grade: grade,
      variant: a.subjectVariant,
      t: _thresholdsOf(a),
    );
    await _assessments.setReadingProfile(a.id!, profile);
  }

  Future<CrlaAssessment> _requireVariant(
    int assessmentId,
    Set<String> allowed,
    String what,
  ) async {
    final a = await _assessments.findById(assessmentId);
    if (a == null) {
      throw ViewModelException('No assessment with id $assessmentId.');
    }
    if (!allowed.contains(a.subjectVariant)) {
      throw ViewModelException(
        '$what needs a ${allowed.join('/')} assessment, but assessment '
        '$assessmentId is "${a.subjectVariant}".',
      );
    }
    return a;
  }

  void _checkScore(String name, int value, int max) => _checkRange(name, value, 0, max);

  void _checkRange(String name, int value, int min, int max) {
    if (value < min || value > max) {
      throw ViewModelException('$name must be between $min and $max (got $value).');
    }
  }

  /// Runs a repository write; a refusal from one of our DB triggers becomes a
  /// ViewModelException carrying only the trigger's message.
  Future<T> _write<T>(Future<T> Function() write) async {
    try {
      return await write();
    } catch (e) {
      final text = e.toString();
      for (final refusal in _dbRefusals) {
        if (text.contains(refusal)) throw ViewModelException('$refusal.');
      }
      rethrow;
    }
  }

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
