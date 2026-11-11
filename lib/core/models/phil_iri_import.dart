// lib/core/models/phil_iri_import.dart
//
// Phil-IRI import (spec docs/superpowers/specs/2026-11-09-phil-iri-import-design.md).
// A reader (ma's workbook, or the BASA scoresheet file) turns a file into one
// PhilIriImportPlan: raw entries only, never a level, profile or adjusted grade
// as a result (D3). The importer (PhilIriImportViewModel) matches learners and
// passages, checks the rules, previews and writes; the plan knows nothing of
// BASA ids.
//
// Every entry keeps where it came from (PhilIriImportRef) so the preview can
// say "sheet 03, row 17, column AV".
import 'phil_iri_assessment.dart';
import 'phil_iri_miscue.dart';
import 'phil_iri_reading.dart';

export 'phil_iri_workbook_import.dart' show PhilIriImportSource;

/// Where an entry or a problem sits in the source file. [row] is the
/// spreadsheet's own 1-based row number; [column] its letter (e.g. `AV`).
class PhilIriImportRef {
  final String sheet;
  final int row;
  final String? column;

  const PhilIriImportRef({required this.sheet, required this.row, this.column});

  @override
  String toString() => 'sheet $sheet, row $row${column == null ? '' : ', column $column'}';
}

/// How the file names a learner: the LRN (scoresheet) or the name and sex as
/// typed (workbook; D5 matches them within the section).
class PhilIriLearnerKey {
  final String? lrn;
  final String? name;
  final String? sex; // 'M' | 'F'

  const PhilIriLearnerKey({this.lrn, this.name, this.sex});
}

/// One section sheet of the file, as the file states it. [empty] = a section
/// sheet with no learners (listed, nothing imported).
class PhilIriImportSectionRef {
  final String sheet;
  final String? depedSchoolId;
  final String? schoolYear; // YYYY-YYYY
  final int? grade;
  final String? sectionName;
  final bool empty;

  const PhilIriImportSectionRef({
    required this.sheet,
    this.depedSchoolId,
    this.schoolYear,
    this.grade,
    this.sectionName,
    this.empty = false,
  });
}

/// The passage as the file names it ([raw], e.g. `7C Dust` or `G7C1`), with
/// whatever the reader could take apart. Matching to a BASA passage is the
/// importer's job.
class PhilIriImportPassageRef {
  final String raw;
  final int? level;
  final String? code;
  final String? title;

  const PhilIriImportPassageRef({required this.raw, this.level, this.code, this.title});
}

/// A GST raw score. [max] = the file's stated maximum (null when it gives none).
/// [date] = YYYY-MM-DD, or null when the file has none (workbook: the BOSY
/// date, D6).
class PhilIriImportGst {
  final PhilIriImportRef ref;
  final PhilIriLearnerKey learner;
  final int score;
  final int? max;
  final String? date;

  const PhilIriImportGst({required this.ref, required this.learner, required this.score, this.max, this.date});
}

/// One passage reading of a round, raw. Timing is [seconds] (whole text,
/// silent) or [wordsRead] (one minute; also the typed count of a whole-text
/// reading when the file has one). Comprehension is either [answers] (the
/// letters chosen, null = not answered; scoresheet) or [correctCount]
/// (workbook). [workbookProfile] / [workbookAdjustedLevel] are the workbook's
/// own saved results, read only to compare (D7), never imported.
/// R2 (spec 2026-11-10-phil-iri-untitled-readings D10): [passage] null =
/// "Untitled" (workbook only: words read and time but no passage); then
/// [wordCount] is the typed word count (whole text / silent) and
/// [correctTotal] the block's comprehension header maximum [correctCount] is
/// out of. A reading with no [seconds] / [wordsRead] has comprehension only.
class PhilIriImportReading {
  final PhilIriImportRef ref;
  final PhilIriLearnerKey learner;
  final PhilIriRound round;
  final String? date;
  final PhilIriImportPassageRef? passage;
  final PhilIriReadingMethod method;
  final int? seconds;
  final int? wordsRead;
  final Map<PhilIriMiscueType, int> miscues;
  final int selfCorrected;
  final List<String?>? answers;
  final int? correctCount;
  final int? wordCount;
  final int? correctTotal;
  final String? workbookProfile;
  final int? workbookAdjustedLevel;

  bool get isUntitled => passage == null;

  const PhilIriImportReading({
    required this.ref,
    required this.learner,
    required this.round,
    this.date,
    required this.passage,
    required this.method,
    this.seconds,
    this.wordsRead,
    this.miscues = const {},
    this.selfCorrected = 0,
    this.answers,
    this.correctCount,
    this.wordCount,
    this.correctTotal,
    this.workbookProfile,
    this.workbookAdjustedLevel,
  });
}

/// A learner's round the reader saw but left out (e.g. an incomplete round,
/// D9), with the reason shown in the preview.
class PhilIriImportSkip {
  final PhilIriImportRef ref;
  final PhilIriLearnerKey learner;
  final PhilIriRound? round;
  final String reason;

  const PhilIriImportSkip({required this.ref, required this.learner, this.round, required this.reason});
}

/// A value the reader couldn't read (the entry is left out).
class PhilIriImportProblem {
  final PhilIriImportRef ref;
  final String message;

  const PhilIriImportProblem({required this.ref, required this.message});

  @override
  String toString() => '$ref: $message';
}

/// A header label the reader didn't find (D14): [field] (a
/// PhilIriImportHeaders field name) in [block] (a round block's title, or the
/// sheet), with the headers that block does have so one can be picked.
class PhilIriHeaderIssue {
  final String field;
  final String block;
  final List<String> found;

  const PhilIriHeaderIssue({required this.field, required this.block, required this.found});
}

class PhilIriImportPlan {
  final PhilIriImportSource source;
  final List<PhilIriImportSectionRef> sections;
  final List<PhilIriImportGst> gst;
  final List<PhilIriImportReading> readings;
  final List<PhilIriImportSkip> skipped;
  final List<PhilIriImportProblem> problems;
  final List<PhilIriHeaderIssue> headerIssues;

  const PhilIriImportPlan({
    required this.source,
    this.sections = const [],
    this.gst = const [],
    this.readings = const [],
    this.skipped = const [],
    this.problems = const [],
    this.headerIssues = const [],
  });
}
