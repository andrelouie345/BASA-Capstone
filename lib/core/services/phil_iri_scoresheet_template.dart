// lib/core/services/phil_iri_scoresheet_template.dart
//
// The BASA Phil-IRI scoresheet file (spec 2026-11-09-phil-iri-import D16;
// plan Task 7): one .xlsx per section, laid out like the DepEd Teacher
// Scoresheet as one table, which teachers (or an AI tool) fill in from the
// paper and import with readPhilIriScoresheet.
//
//  * Sheet "Learners" (the first sheet: readTable reads only that one): one
//    row per learner, LRN (text) / Learner / Sex pre-filled; the other columns
//    in PhilIriImportHeaders order with the device's labels. A learner with
//    more than one round gets a copied row per round.
//  * Sheet "Codes": rounds, methods, passages, miscue types. Round, Method
//    and Passage have drop-down lists from it.
//  * Sheet "Instructions": the steps of the guide.
//
// Passage entries are "<code> <title>" (Task 7 ruling, owner 2026-11-11): the
// code alone is not unique (two active collections can hold the same G7Pre
// passage; the 2018 set has G7A for both a pre and a post passage). The same
// code and title is listed once. Time is a text column, so a typed 2:35 stays
// "2:35" instead of Excel's 2 hours 35 minutes.
import '../models/phil_iri_assessment.dart' show PhilIriRound;
import '../models/phil_iri_miscue.dart';
import '../models/phil_iri_passage.dart';
import '../models/phil_iri_reading.dart' show PhilIriReadingMethod;
import '../models/section.dart';
import '../models/student.dart';
import 'phil_iri_import_headers.dart';
import 'xlsx_cells.dart' show columnLetters;
import 'xlsx_writer.dart';

/// Highest question column (Q1 ... Q20).
const philIriScoresheetQuestions = 20;

/// Round names as the scoresheet writes them ("GST" is the GST row).
const philIriScoresheetGst = 'GST';
String philIriScoresheetRound(PhilIriRound r) => r.label.replaceAll(RegExp(r'[\s#]'), '');

/// Method names as the scoresheet writes them.
String philIriScoresheetMethod(PhilIriReadingMethod m) => switch (m) {
      PhilIriReadingMethod.wholeText => 'whole text',
      PhilIriReadingMethod.oneMinute => 'one minute',
      PhilIriReadingMethod.silent => 'silent',
    };

/// The booklet code of a passage: `G` + level + set code, else Pre/Post by
/// its test type (G7C1, G7A, G7Pre, G7Post; a pool passage without either is
/// just G7). Not unique on its own: the scoresheet pairs it with the title.
String philIriPassageCode(PhilIriPassage p) =>
    'G${p.level ?? ''}${p.setCode ?? (p.testType == 'pre' ? 'Pre' : p.testType == 'post' ? 'Post' : '')}';

/// The scoresheet entry of a passage: "<code> <title>".
String philIriScoresheetPassage(PhilIriPassage p) => '${philIriPassageCode(p)} ${p.title.trim()}';

const _learnerLabel = 'Learner';
const _sexLabel = 'Sex';
const _listRows = 2000; // drop-downs reach this row (one row per reading)

const philIriScoresheetInstructions = [
  'Phil-IRI scoresheet file (BASA)',
  '',
  '1. This file is for one section. Keep the LRN column as it is: BASA finds each learner by LRN.',
  '2. One row per reading. A learner read more than once (another round, or GST)? Copy the learner\'s row '
      'and fill one round per row. GST: Round "GST", the date and the GST score only.',
  '3. Copy the paper into the row: round, date, passage, method, time (m:ss) or words read (one minute), '
      'the miscue counts, and each answer letter in Q1, Q2, ... Pick round, method and passage from the '
      'lists (sheet Codes).',
  '4. Leave a cell empty if it isn\'t on the paper; never guess. A blank answer counts as wrong.',
  '5. Save, import the file in BASA, and read the preview before importing.',
];

/// The section's scoresheet file. [learners] in the order to list them;
/// [passages] = the passages to offer (only active ones of the section's
/// grade are listed).
List<int> buildPhilIriScoresheetTemplate({
  required Section section,
  required List<Student> learners,
  required List<PhilIriPassage> passages,
  required PhilIriImportHeaders headers,
}) {
  final grade = int.tryParse(section.gradeLevel.trim());
  final passageEntries = <String>{
    for (final p in passages)
      if (p.isActive && p.level != null && p.level == grade) philIriScoresheetPassage(p),
  }.toList()
    ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

  // Columns in PhilIriImportHeaders order, Learner and Sex after the LRN.
  final columns = <String>[
    headers.label('ss.lrn'),
    _learnerLabel,
    _sexLabel,
    for (final f in [
      'ss.round', 'ss.date', 'ss.passage', 'ss.method', 'ss.time', 'ss.wordsRead',
      for (final t in PhilIriMiscueType.values) 'ss.${t.name}',
      'ss.selfCorrected', 'ss.gst',
    ])
      headers.label(f),
    for (var q = 1; q <= philIriScoresheetQuestions; q++) '${headers.label('ss.q')}$q',
  ];
  String col(String label) => columnLetters(columns.indexOf(label) + 1);

  final cells = <String, Object?>{
    for (var i = 0; i < columns.length; i++) '${columnLetters(i + 1)}1': columns[i],
  };
  for (var i = 0; i < learners.length; i++) {
    final s = learners[i];
    final r = i + 2;
    final name = [s.lastName.trim(), [s.firstName.trim(), s.middleName?.trim() ?? ''].where((x) => x.isNotEmpty).join(' ')]
        .join(', ');
    cells['${col(columns[0])}$r'] = s.lrn;
    cells['${col(_learnerLabel)}$r'] = name;
    cells['${col(_sexLabel)}$r'] = s.sex;
  }

  final rounds = [philIriScoresheetGst, for (final r in PhilIriRound.values) philIriScoresheetRound(r)];
  final methods = [for (final m in PhilIriReadingMethod.values) philIriScoresheetMethod(m)];
  final codes = <String, Object?>{
    'A1': 'Round', 'B1': 'Method', 'C1': 'Passage', 'D1': 'Miscue types',
    for (var i = 0; i < rounds.length; i++) 'A${i + 2}': rounds[i],
    for (var i = 0; i < methods.length; i++) 'B${i + 2}': methods[i],
    for (var i = 0; i < passageEntries.length; i++) 'C${i + 2}': passageEntries[i],
    for (var i = 0; i < PhilIriMiscueType.values.length; i++) 'D${i + 2}': PhilIriMiscueType.values[i].label,
  };
  String range(String label) => '${col(label)}2:${col(label)}$_listRows';

  final lrnCol = columns.indexOf(columns[0]) + 1;
  final timeCol = columns.indexOf(headers.label('ss.time')) + 1;
  return writeXlsx([
    XlsxSheetSpec(
      name: 'Learners',
      cells: cells,
      textColumns: {lrnCol, timeCol},
      listValidations: {
        range(headers.label('ss.round')): '\$A\$2:\$A\$${rounds.length + 1}'.codes,
        range(headers.label('ss.method')): '\$B\$2:\$B\$${methods.length + 1}'.codes,
        if (passageEntries.isNotEmpty)
          range(headers.label('ss.passage')): '\$C\$2:\$C\$${passageEntries.length + 1}'.codes,
      },
      columnWidths: [
        for (final c in columns)
          c == _learnerLabel
              ? 30
              : c == headers.label('ss.passage')
                  ? 32
                  : c == columns[0]
                      ? 15
                      : c.length < 6
                          ? 7
                          : c.length + 3,
      ],
    ),
    XlsxSheetSpec(name: 'Codes', cells: codes, columnWidths: const [10, 12, 45, 18]),
    XlsxSheetSpec(
      name: 'Instructions',
      cells: {
        for (var i = 0; i < philIriScoresheetInstructions.length; i++)
          if (philIriScoresheetInstructions[i].isNotEmpty) 'A${i + 1}': philIriScoresheetInstructions[i],
        'A${philIriScoresheetInstructions.length + 2}':
            'Section: Grade ${section.gradeLevel} ${section.sectionName}, ${section.schoolYear}',
      },
      columnWidths: const [120],
    ),
  ]);
}

extension on String {
  String get codes => 'Codes!$this';
}
