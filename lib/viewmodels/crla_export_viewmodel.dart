// lib/viewmodels/crla_export_viewmodel.dart
//
// Exports a section's CRLA results into the DepEd CRLA2 scoresheet template
// of its grade (piece IE3). Owner decision (2026-10-16): fill the official
// template so the school submits the DepEd format; Excel recalculates the
// Class Record and Class Summary on open.
//  * One row per active learner of the section (by name), learners with no
//    result too, as a class list.
//  * For each learner and variant: the latest attempt of the chosen round.
//  * Excel's own formulas compute totals, levels and profiles with DepEd's
//    default bands; BASA's adjustable thresholds aren't in the template, so a
//    school that changed them may see different levels in Excel (noted).
// Reads the local copy (offline).
import '../core/console/logger.dart';
import '../core/models/crla_assessment.dart';
import '../core/models/crla_part2_fluency.dart';
import '../core/models/section.dart';
import '../core/models/user_role.dart';
import '../core/repositories/crla_assessment_repository.dart';
import '../core/repositories/crla_part1_english_repository.dart';
import '../core/repositories/crla_part1_standard_repository.dart';
import '../core/repositories/crla_part2_fluency_repository.dart';
import '../core/repositories/crla_story_repository.dart';
import '../core/repositories/crla_threshold_repository.dart';
import '../core/repositories/school_repository.dart';
import '../core/repositories/section_repository.dart';
import '../core/repositories/student_repository.dart';
import '../core/services/crla_rules.dart';
import '../core/services/crla_scoresheet.dart';
import 'auth_viewmodel.dart';
import 'viewmodel_exception.dart';

class CrlaScoresheetExport {
  final List<int> bytes;
  final Section section;
  final CrlaRound round;
  final int learners;
  final Map<String, int> resultsByVariant; // variant -> learners with a result
  final List<String> notes;
  const CrlaScoresheetExport(this.bytes, this.section, this.round, this.learners, this.resultsByVariant, this.notes);
}

class CrlaExportViewModel {
  final ScopedLogger _log;
  final AuthViewModel _auth;
  final SectionRepository _sections;
  final SchoolRepository _schools;
  final StudentRepository _students;
  final CrlaAssessmentRepository _assessments;
  final CrlaPart1StandardRepository _part1Standard;
  final CrlaPart1EnglishRepository _part1English;
  final CrlaPart2FluencyRepository _part2;
  final CrlaStoryRepository _stories;
  final CrlaThresholdRepository _thresholds;

  CrlaExportViewModel({
    required AuthViewModel auth,
    required SectionRepository sections,
    required SchoolRepository schools,
    required StudentRepository students,
    required CrlaAssessmentRepository assessments,
    required CrlaPart1StandardRepository part1Standard,
    required CrlaPart1EnglishRepository part1English,
    required CrlaPart2FluencyRepository part2Fluency,
    required CrlaStoryRepository stories,
    required CrlaThresholdRepository thresholds,
    Logger? logger,
  })  : _auth = auth,
        _sections = sections,
        _schools = schools,
        _students = students,
        _assessments = assessments,
        _part1Standard = part1Standard,
        _part1English = part1English,
        _part2 = part2Fluency,
        _stories = stories,
        _thresholds = thresholds,
        _log = ScopedLogger(logger, 'CrlaExportViewModel');

  /// Fills [template] (the blank CRLA2 scoresheet of the section's grade)
  /// with the section's [round] results. [teacher] goes in the header.
  Future<CrlaScoresheetExport> exportScoresheet(int sectionId, List<int> template,
      {required CrlaRound round, String? teacher}) async {
    _log('exportScoresheet(section: $sectionId, round: ${round.name})');
    final me = _auth.currentUser;
    if (me == null) throw const ViewModelException('Not signed in.');
    final section = await _sections.getById(sectionId);
    if (section == null) throw ViewModelException('No section with id $sectionId.');
    if ((me.role == UserRole.admin || me.role == UserRole.coordinator) &&
        me.schoolId != null &&
        me.schoolId != section.schoolId) {
      throw const ViewModelException('Forbidden: that section is in another school.');
    }
    final grade = crlaGradeOf(section.gradeLevel);
    if (grade == null) {
      throw ViewModelException('CRLA is for Grade 1-3 sections only (section $sectionId is Grade ${section.gradeLevel}).');
    }
    final school = await _schools.getById(section.schoolId);

    // Latest attempt per learner and variant in this round.
    final latest = <(int, String), CrlaAssessment>{};
    for (final a in await _assessments.getBySection(sectionId, schoolYear: section.schoolYear)) {
      if (a.round != round) continue;
      final key = (a.studentId, a.subjectVariant);
      if ((latest[key]?.attemptNo ?? -1) < (a.attemptNo ?? 0)) latest[key] = a;
    }

    final notes = <String>[];
    final students = await _students.getBySection(sectionId);
    final active = students.map((s) => s.id).toSet();
    final orphans = latest.keys.where((k) => !active.contains(k.$1)).map((k) => k.$1).toSet();
    if (orphans.isNotEmpty) {
      notes.add('${orphans.length} learner(s) with ${round.label} results are no longer active in the section; left out.');
    }

    // The MT language: the most common among this round's mt results.
    final mtLanguages = <String, int>{};
    for (final a in latest.values.where((a) => a.subjectVariant == 'mt')) {
      mtLanguages[a.language] = (mtLanguages[a.language] ?? 0) + 1;
    }
    String? mtLanguage;
    if (mtLanguages.isNotEmpty) {
      mtLanguage = (mtLanguages.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).first.key;
      if (mtLanguages.length > 1) {
        notes.add('Mother-tongue results use ${mtLanguages.length} languages; the sheet says $mtLanguage '
            '(its story word counts apply to every MT row).');
      }
    }
    // Story word counts from BASA's stories (the template's own list is used
    // first by its formulas; these cover a language it doesn't list).
    Future<int?> words(String? language, int storyNo) async => language == null || school?.regionId == null
        ? null
        : (await _stories.findByKey(regionId: school!.regionId!, language: language, grade: grade, storyNo: storyNo))
            ?.wordCount;

    final learners = <CrlaScoresheetLearner>[];
    final counts = <String, int>{};
    for (final s in students) {
      final entries = <String, CrlaScoresheetEntry>{};
      final middle = (s.middleName ?? '').trim();
      for (final variant in const ['mt', 'fil', 'eng']) {
        final a = latest[(s.id!, variant)];
        if (a == null) continue;
        entries[variant] = await _entry(a);
        counts[variant] = (counts[variant] ?? 0) + 1;
        // The sheet computes words read from its own story (F10): warn when it
        // can't show BASA's value (owner 2026-10-23: a warning, no round trip).
        final p2 = await _part2.findByAssessmentId(a.id!);
        if (p2 != null) {
          final sheetWords = switch (variant) {
            'eng' => 100,
            'fil' => await words('Tagalog', p2.storyNo),
            _ => a.language == mtLanguage ? await words(mtLanguage, p2.storyNo) : null,
          };
          final note = crlaWordsReadExportNote('${s.lastName}, ${s.firstName}', variant,
              sheetStoryWords: sheetWords, miscues: p2.miscues, wordsRead: p2.wordsRead);
          if (note != null) notes.add(note);
        }
      }
      learners.add(CrlaScoresheetLearner(
        s.lrn,
        '${s.lastName}, ${s.firstName}${middle.isEmpty ? '' : ' ${middle[0]}.'}',
        switch ((s.sex ?? '').toUpperCase()) { 'M' || 'MALE' => 'Male', 'F' || 'FEMALE' => 'Female', _ => null },
        entries,
      ));
    }
    if (learners.isEmpty) throw ViewModelException('Section $sectionId has no active learners.');

    final region = await _thresholds.getRegion();
    final override = await _thresholds.getForSchool(section.schoolId);
    if ((region?.settings.isNotEmpty ?? false) || (override?.settings.isNotEmpty ?? false)) {
      notes.add('This school uses adjusted CRLA thresholds; Excel computes levels and profiles with DepEd\'s default '
          'bands, so they can differ from BASA\'s.');
    }

    final mt1 = await words(mtLanguage, 1), mt2 = await words(mtLanguage, 2);
    final fil1 = await words('Tagalog', 1), fil2 = await words('Tagalog', 2);
    final (bytes, fillNotes) = () {
      try {
        return fillCrlaScoresheet(
          template,
          grade: grade,
          assessmentType: switch (round) { CrlaRound.bosy => 'BoSY', CrlaRound.mosy => 'MoSY', CrlaRound.eosy => 'EoSY' },
          schoolCode: school?.schoolId,
          schoolName: school?.schoolName,
          teacher: teacher,
          sectionName: section.sectionName,
          mtLanguage: mtLanguage,
          male: learners.where((l) => l.sex == 'Male').length,
          female: learners.where((l) => l.sex == 'Female').length,
          story1Words: mt1,
          story2Words: mt2,
          filStory1Words: fil1,
          filStory2Words: fil2,
          learners: learners,
        );
      } on CrlaScoresheetException catch (e) {
        throw ViewModelException(e.message);
      }
    }();
    return CrlaScoresheetExport(bytes, section, round, learners.length, counts, [...notes, ...fillNotes]);
  }

  Future<CrlaScoresheetEntry> _entry(CrlaAssessment a) async {
    final p2 = await _part2.findByAssessmentId(a.id!);
    if (a.subjectVariant == 'eng') {
      final p1 = await _part1English.findByAssessmentId(a.id!);
      return _make(a, p2, task1: p1?.task1Score, task2: p1?.task2Score);
    }
    final p1 = await _part1Standard.findByAssessmentId(a.id!);
    return _make(a, p2, task1: p1?.task1Score, low: p1?.task2LowScore, high: p1?.task2HighScore);
  }

  CrlaScoresheetEntry _make(CrlaAssessment a, CrlaPart2Fluency? p2, {int? task1, int? low, int? high, int? task2}) =>
      CrlaScoresheetEntry(
        assessedOn: a.assessedAt,
        task1: task1,
        task2Low: low,
        task2High: high,
        task2: task2,
        storyNo: p2?.storyNo,
        miscues: p2?.miscues,
        minutes: p2?.timeMinutes,
        seconds: p2?.timeSeconds,
        comprehension: p2?.comprehensionCorrect,
        experienceRating: p2?.learnerExperienceRating,
        observationLevel: p2?.observationLevel,
        remarks: p2?.remarks,
      );
}
