// lib/viewmodels/crla_import_viewmodel.dart
//
// Imports a filled DepEd CRLA2 scoresheet workbook into a section's CRLA
// assessments (piece IE2). Owner decisions (2026-10-16):
//  * Learners are matched by LRN among the section's active learners; a row
//    whose LRN isn't in the section is reported, never guessed.
//  * Preview first (nothing written), then import.
//  * Each row becomes an assessment through CrlaViewModel, so the usual CRLA
//    rules, thresholds snapshot and reading profile apply.
// Also: the round comes from the sheet's assessment type (C3) unless given; a
// learner who already has an assessment for that variant and round in the
// section is skipped unless [again] (then it becomes the next attempt).
// Offline-first like CRLA itself: written to the local copy.
import '../core/console/logger.dart';
import '../core/models/crla_assessment.dart';
import '../core/models/section.dart';
import '../core/models/student.dart';
import '../core/models/user_role.dart';
import '../core/repositories/crla_assessment_repository.dart';
import '../core/repositories/section_repository.dart';
import '../core/repositories/student_repository.dart';
import '../core/services/crla_rules.dart';
import '../core/services/crla_scoresheet.dart';
import 'auth_viewmodel.dart';
import 'crla_viewmodel.dart';
import 'viewmodel_exception.dart';

enum CrlaImportOutcome { import, alreadyAssessed, error }

class CrlaImportRow {
  final CrlaScoresheetRow row;
  final Student? student;
  final CrlaImportOutcome outcome;
  final List<String> problems;      // why it can't be imported (outcome error)
  final int? existingAttempt;       // alreadyAssessed: the learner's latest attempt this round

  const CrlaImportRow(this.row, this.student, this.outcome, {this.problems = const [], this.existingAttempt});
}

class CrlaImportPreview {
  final Section section;
  final CrlaScoresheetFile file;
  final CrlaRound round;
  final List<String> warnings;      // file-level notes (section name differs, ...)
  final List<CrlaImportRow> rows;

  const CrlaImportPreview(this.section, this.file, this.round, this.warnings, this.rows);

  int count(CrlaImportOutcome o) => rows.where((r) => r.outcome == o).length;
}

class CrlaImportResult {
  final CrlaImportPreview preview;
  final List<int> assessmentIds;                    // created
  final Map<CrlaImportRow, String> failed;          // rows that failed while writing
  const CrlaImportResult(this.preview, this.assessmentIds, this.failed);
}

class CrlaImportViewModel {
  final ScopedLogger _log;
  final AuthViewModel _auth;
  final CrlaViewModel _crla;
  final CrlaAssessmentRepository _assessments;
  final SectionRepository _sections;
  final StudentRepository _students;

  CrlaImportViewModel({
    required AuthViewModel auth,
    required CrlaViewModel crla,
    required CrlaAssessmentRepository assessments,
    required SectionRepository sections,
    required StudentRepository students,
    Logger? logger,
  })  : _auth = auth,
        _crla = crla,
        _assessments = assessments,
        _sections = sections,
        _students = students,
        _log = ScopedLogger(logger, 'CrlaImportViewModel');

  /// Reads the workbook and decides each row's outcome; writes nothing.
  /// [round] overrides the sheet's assessment type. With [again], learners
  /// already assessed this round are imported as a new attempt.
  Future<CrlaImportPreview> preview(int sectionId, List<int> bytes, {CrlaRound? round, bool again = false}) async {
    _log('preview(section: $sectionId, round: ${round?.name}, again: $again)');
    final section = await _requireSection(sectionId);
    final CrlaScoresheetFile file;
    try {
      file = readCrlaScoresheet(bytes);
    } on CrlaScoresheetException catch (e) {
      throw ViewModelException(e.message);
    }
    final grade = crlaGradeOf(section.gradeLevel);
    if (grade != file.grade) {
      throw ViewModelException('This is a Grade ${file.grade} scoresheet; section $sectionId is Grade ${section.gradeLevel}.');
    }
    final r = round ?? crlaRoundOf(file.assessmentType);
    if (r == null) {
      throw ViewModelException(file.assessmentType == null
          ? 'The scoresheet has no assessment type (C3); give the round (bosy, mosy or eosy).'
          : 'The assessment type "${file.assessmentType}" is not BoSY, MoSY or EoSY; give the round.');
    }

    final warnings = <String>[];
    if (file.sectionName != null && _norm(file.sectionName!) != _norm(section.sectionName)) {
      warnings.add('The scoresheet says section "${file.sectionName}"; importing into "${section.sectionName}".');
    }
    if (round != null && file.assessmentType != null && crlaRoundOf(file.assessmentType) != round) {
      warnings.add('The scoresheet says ${file.assessmentType}; importing as ${round.label}.');
    }

    final byLrn = {for (final s in await _students.getBySection(sectionId)) s.lrn.trim(): s};
    final existing = (await _assessments.getBySection(sectionId, schoolYear: section.schoolYear))
        .where((a) => a.round == r)
        .toList();
    final seen = <String>{};
    final rows = <CrlaImportRow>[];
    for (final row in file.rows) {
      final problems = [...row.problems];
      final student = row.lrn == null ? null : byLrn[row.lrn!.trim()];
      if (row.lrn != null && student == null) problems.add('LRN ${row.lrn} is not an active learner of this section');
      if (row.lrn != null && !seen.add('${row.variant}/${row.lrn}')) {
        problems.add('LRN ${row.lrn} appears twice on the ${row.variant.toUpperCase()} sheet');
      }
      if (file.languages[row.variant] == null) problems.add('the sheet has no language (C9)');
      if (problems.isNotEmpty) {
        rows.add(CrlaImportRow(row, student, CrlaImportOutcome.error, problems: problems));
        continue;
      }
      final mine = existing.where((a) => a.studentId == student!.id && a.subjectVariant == row.variant);
      if (mine.isNotEmpty && !again) {
        final latest = mine.map((a) => a.attemptNo ?? 0).reduce((a, b) => a > b ? a : b);
        rows.add(CrlaImportRow(row, student, CrlaImportOutcome.alreadyAssessed, existingAttempt: latest));
        continue;
      }
      rows.add(CrlaImportRow(row, student, CrlaImportOutcome.import));
    }
    return CrlaImportPreview(section, file, r, warnings, rows);
  }

  /// Imports every importable row (see [preview]). A row that fails while
  /// writing is reported and the others continue; its assessment may then be
  /// left without Part 1 or Part 2 (fix it with the CRLA commands).
  Future<CrlaImportResult> importScoresheet(int sectionId, List<int> bytes, {CrlaRound? round, bool again = false}) async {
    final p = await preview(sectionId, bytes, round: round, again: again);
    _log('importScoresheet(section: $sectionId, round: ${p.round.name}, rows: ${p.count(CrlaImportOutcome.import)})');
    final ids = <int>[];
    final failed = <CrlaImportRow, String>{};
    for (final ir in p.rows.where((r) => r.outcome == CrlaImportOutcome.import)) {
      final row = ir.row;
      try {
        final a = await _crla.startAssessment(
          studentId: ir.student!.id!,
          sectionId: sectionId,
          schoolYear: p.section.schoolYear,
          subjectVariant: row.variant,
          language: p.file.languages[row.variant]!,
          round: p.round,
          administeredBy: _auth.currentUser?.id,
          assessedAt: DateTime.parse(row.assessedOn!),
        );
        ids.add(a.id!);
        if (row.hasPart1) {
          if (row.variant == 'eng') {
            await _crla.savePart1English(assessmentId: a.id!, task1Score: row.task1!, task2Score: row.task2);
          } else {
            await _crla.savePart1Standard(
                assessmentId: a.id!, task1Score: row.task1!, task2LowScore: row.task2Low, task2HighScore: row.task2High);
          }
        }
        if (row.hasPart2) {
          await _crla.savePart2Fluency(
            assessmentId: a.id!,
            storyNo: row.storyNo!,
            miscues: row.miscues!,
            wordsRead: row.wordsRead!,
            timeMinutes: row.minutes!,
            timeSeconds: row.seconds!,
            comprehensionCorrect: row.comprehension!,
            learnerExperienceRating: row.experienceRating,
            observationLevel: row.observationLevel,
            remarks: row.remarks,
          );
        }
      } catch (e) {
        failed[ir] = '$e';
        _log('row ${row.sheet}!${row.rowNo} failed: $e');
      }
    }
    return CrlaImportResult(p, ids, failed);
  }

  Future<Section> _requireSection(int sectionId) async {
    final me = _auth.currentUser;
    if (me == null) throw const ViewModelException('Not signed in.');
    final section = await _sections.getById(sectionId);
    if (section == null) throw ViewModelException('No section with id $sectionId.');
    if ((me.role == UserRole.admin || me.role == UserRole.coordinator) &&
        me.schoolId != null &&
        me.schoolId != section.schoolId) {
      throw const ViewModelException('Forbidden: that section is in another school.');
    }
    if (crlaGradeOf(section.gradeLevel) == null) {
      throw ViewModelException('CRLA is for Grade 1-3 sections only (section $sectionId is Grade ${section.gradeLevel}).');
    }
    return section;
  }

  static String _norm(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
}
