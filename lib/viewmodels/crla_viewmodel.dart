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


class CrlaViewModel {
  static const _variants = {'mt', 'fil', 'eng'};

  final ScopedLogger _log;
  final CrlaAssessmentRepository _assessments;
  final CrlaPart1StandardRepository _part1Standard;
  final CrlaPart1EnglishRepository _part1English;
  final CrlaPart2FluencyRepository _part2Fluency;
  final CrlaResultRepository _results;


  List<CrlaAssessment> assessments = [];
  List<CrlaResult> results = [];
  // Remembers which query populated `assessments`, so refresh() can repeat it.
  int? _lastSectionId;
  String? _lastSchoolYear;

  CrlaViewModel({
    required CrlaAssessmentRepository assessments,
    required CrlaPart1StandardRepository part1Standard,
    required CrlaPart1EnglishRepository part1English,
    required CrlaPart2FluencyRepository part2Fluency,
    required CrlaResultRepository results,
    Logger? logger,
  })  : _assessments = assessments,
        _part1Standard = part1Standard,
        _part1English = part1English,
        _part2Fluency = part2Fluency,
        _results = results,
        _log = ScopedLogger(logger, 'CrlaViewModel');

  Future<void> loadForSection(int sectionId, {String? schoolYear}) async {
    _log('loadForSection(sectionId: $sectionId, schoolYear: $schoolYear)');
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

  /// Starts a new attempt. A retake is just another call with the same
  /// student/section/variant/year: the DB assigns the next attempt_no.
  /// Returns the stored row (with its attempt_no and id).
  Future<CrlaAssessment> startAssessment({
    required int studentId,
    required int schoolId,
    required int sectionId,
    required String schoolYear,
    required String subjectVariant,
    required String language,
    String? administeredBy,
    DateTime? assessedAt,
  }) async {
    _log('startAssessment(studentId: $studentId, sectionId: $sectionId, '
        'variant: $subjectVariant, year: $schoolYear)');

    if (!_variants.contains(subjectVariant)) {
      throw ArgumentError("subjectVariant must be one of mt, fil, eng (got '$subjectVariant')");
    }

    final stored = await _assessments.insert(
      CrlaAssessment(
        studentId: studentId,
        schoolId: schoolId,
        sectionId: sectionId,
        schoolYear: schoolYear,
        subjectVariant: subjectVariant,
        language: language,
        assessedAt: (assessedAt ?? DateTime.now()).toUtc().toIso8601String(),
        administeredBy: administeredBy,
      ),
    );
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

    await _requireVariant(assessmentId, {'mt', 'fil'}, 'Standard Part 1');
    _checkScore('task1Score', task1Score, 10);
    if (task2LowScore != null) _checkScore('task2LowScore', task2LowScore, 10);
    if (task2HighScore != null) _checkScore('task2HighScore', task2HighScore, 10);

    // Branch rule (same as the DB CHECKs): task 1 below 7 uses the low
    // task 2, 7 or above uses the high one, and never both.
    if (task2LowScore != null && task2HighScore != null) {
      throw ArgumentError('Provide task2LowScore or task2HighScore, not both');
    }
    if (task2LowScore != null && task1Score >= 7) {
      throw ArgumentError('task2LowScore only applies when task1Score is below 7');
    }
    if (task2HighScore != null && task1Score < 7) {
      throw ArgumentError('task2HighScore only applies when task1Score is 7 or above');
    }

    final part1 = CrlaPart1Standard(
      assessmentId: assessmentId,
      task1Score: task1Score,
      task2LowScore: task2LowScore,
      task2HighScore: task2HighScore,
    );

    final existing = await _part1Standard.findByAssessmentId(assessmentId);
    if (existing == null) {
      return _part1Standard.insert(part1);
    }
    await _part1Standard.update(part1);
    return (await _part1Standard.findByAssessmentId(assessmentId))!;
  }

  /// Saves Part 1 for an eng assessment. Inserts, or corrects the existing row.
  Future<CrlaPart1English> savePart1English({
    required int assessmentId,
    required int task1Score,
    int? task2Score,
  }) async {
    _log('savePart1English(assessmentId: $assessmentId, task1: $task1Score, task2: $task2Score)');

    await _requireVariant(assessmentId, {'eng'}, 'English Part 1');
    _checkScore('task1Score', task1Score, 10);
    if (task2Score != null) {
      _checkScore('task2Score', task2Score, 10);
      if (task1Score < 1) {
        throw ArgumentError('task2Score only applies when task1Score is 1 or above');
      }
    }

    final part1 = CrlaPart1English(
      assessmentId: assessmentId,
      task1Score: task1Score,
      task2Score: task2Score,
    );

    final existing = await _part1English.findByAssessmentId(assessmentId);
    if (existing == null) {
      return _part1English.insert(part1);
    }
    await _part1English.update(part1);
    return (await _part1English.findByAssessmentId(assessmentId))!;
  }

  /// Saves Part 2 for any variant. Inserts, or corrects the existing row.
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

    await _requireVariant(assessmentId, {'mt', 'fil', 'eng'}, 'Part 2');
    _checkRange('storyNo', storyNo, 1, 2);
    _checkRange('miscues', miscues, 0, 1 << 30);
    _checkRange('wordsRead', wordsRead, 0, 1 << 30);
    _checkRange('timeMinutes', timeMinutes, 0, 1 << 30);
    _checkRange('timeSeconds', timeSeconds, 0, 59);
    _checkRange('comprehensionCorrect', comprehensionCorrect, 0, 5);
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
      return _part2Fluency.insert(fluency);
    }
    await _part2Fluency.update(fluency);
    return (await _part2Fluency.findByAssessmentId(assessmentId))!;
  }

  /// The combined result for one assessment (Part 1 + Part 2 + reading profile),
  /// or null if the assessment doesn't exist.
  ///
  /// If Part 2 is saved but pctCorrectWordsRead is null, no crla_stories row
  /// matched this school's region, language, grade and story number.
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
    results = await _results.getBySection(sectionId, schoolYear: schoolYear);
  }

  /// Loads every attempt for one student, newest first.
  Future<void> loadResultsForStudent(int studentId) async {
    _log('loadResultsForStudent(studentId: $studentId)');
    results = await _results.getByStudent(studentId);
  }

  // ---- helpers ----

  Future<CrlaAssessment> _requireVariant(
    int assessmentId,
    Set<String> allowed,
    String what,
  ) async {
    final a = await _assessments.findById(assessmentId);
    if (a == null) {
      throw StateError('No assessment with id $assessmentId');
    }
    if (!allowed.contains(a.subjectVariant)) {
      throw ArgumentError(
        '$what needs a ${allowed.join('/')} assessment, but assessment '
        '$assessmentId is "${a.subjectVariant}"',
      );
    }
    return a;
  }

  void _checkScore(String name, int value, int max) {
    if (value < 0 || value > max) {
      throw ArgumentError('$name must be between 0 and $max (got $value)');
    }
  }
    void _checkRange(String name, int value, int min, int max) {
    if (value < min || value > max) {
      throw ArgumentError('$name must be between $min and $max (got $value)');
    }
  }
}