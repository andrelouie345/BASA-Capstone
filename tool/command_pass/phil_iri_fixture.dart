// Phil-IRI import files the command pass writes (scenario a7, import plan
// Task 11): the learners are the school-a ones make-sf1 writes (same grade,
// count and `from`), so the files name the section the scenario imported.
// Contents are fixed; scenario 37_a7.pass expects exactly these.
//
// Workbook (ma's layout; school cell "<code> - <name>": the run's school code
// is not a DepEd number, so the importer takes the signed-in user's school):
//   sheet 01 = the section. BOSY whole text of passage "Lili the Lizard and
//   Koko the Gecko" (pool passage 110, Grade 7, 357 words, 10 questions;
//   comprehension maximum 10, so nothing is scaled):
//     learner 1: GST 30/40; 357 words, 2:30, 5 mispronunciations, 8/10
//     learner 2: GST 20/40; 357 words, 3:10, 20 omissions, 3/10
//     others:    nothing (their rows are empty)
//   sheet 02 = section "ZZTEST-NONE" (not in BASA), learner 1 with a GST.
// Scoresheet (BASA file, first sheet):
//   learner 1: MOSY 1, whole text of "The Jeepney: A Filipino Tradition"
//              (pool passage 119), 2:30, 2 omissions, no answers
//   learner 3: GST 25 (when count >= 3)
//   others:    LRN, name and sex only (unused rows)
import 'dart:io';

import 'package:basa_capstone/core/models/phil_iri_assessment.dart' show PhilIriRound;
import 'package:basa_capstone/core/models/phil_iri_miscue.dart';
import 'package:basa_capstone/core/services/xlsx_cells.dart' show columnLetters;
import 'package:basa_capstone/core/services/xlsx_writer.dart';

import 'phil_iri_workbook_fixture.dart';
import 'sf1_fixture.dart';

const philIriFixtureWorkbookPassage = '7A Lili the Lizard and Koko the Gecko';
const philIriFixtureScoresheetPassage = 'G7 The Jeepney: A Filipino Tradition';

String _name(Sf1Learner l) => '${l.last}, ${l.first}';

void writePhilIriWorkbook(String path,
    {required String school, required String schoolYear, required int grade, required String section,
    required List<Sf1Learner> learners}) {
  const passage = philIriFixtureWorkbookPassage;
  WbLearner learner(int k, Sf1Learner l) => switch (k) {
        0 => WbLearner(_name(l), gst: 30, rounds: const {
            PhilIriRound.bosy: WbRound(passage: passage, wordsRead: 357, mm: 2, ss: 30, mispronunciation: 5, comprehension: 8),
          }),
        1 => WbLearner(_name(l), gst: 20, rounds: const {
            PhilIriRound.bosy: WbRound(passage: passage, wordsRead: 357, mm: 3, ss: 10, omission: 20, comprehension: 3),
          }),
        _ => WbLearner(_name(l)),
      };
  final all = [for (var k = 0; k < learners.length; k++) (learners[k], learner(k, learners[k]))];
  WbSheet sheet(String name, String sectionName, List<(Sf1Learner, WbLearner)> rows) => WbSheet(
        name,
        section: sectionName,
        school: school,
        schoolYear: schoolYear,
        grade: grade,
        males: [for (final r in rows) if (r.$1.sex == 'M') r.$2],
        females: [for (final r in rows) if (r.$1.sex == 'F') r.$2],
        methods: const {PhilIriRound.bosy: 'Whole-Text Reading'},
        comprehensionMax: const {PhilIriRound.bosy: 10},
      );
  File(path).writeAsBytesSync(buildPhilIriWorkbook([
    sheet('01', section, all),
    sheet('02', 'ZZTEST-NONE', [(learners.first, WbLearner(_name(learners.first), gst: 12))]),
  ]));
}

void writePhilIriScoresheet(String path, {required String date, required List<Sf1Learner> learners}) {
  final headers = [
    'LRN', 'Learner', 'Sex', 'Round', 'Date', 'Passage', 'Method', 'Time', 'Words read',
    for (final t in PhilIriMiscueType.values) t.label,
    'Self-corrected', 'GST score', 'Q1', 'Q2',
  ];
  final cells = <String, Object?>{};
  void row(int r, Map<String, Object?> values) {
    for (var c = 0; c < headers.length; c++) {
      final v = values[headers[c]];
      if (v != null) cells['${columnLetters(c + 1)}$r'] = v;
    }
  }

  row(1, {for (final h in headers) h: h});
  for (var k = 0; k < learners.length; k++) {
    final l = learners[k];
    row(k + 2, {
      'LRN': l.lrn,
      'Learner': _name(l),
      'Sex': l.sex,
      if (k == 0) ...{
        'Round': 'MOSY1',
        'Date': date,
        'Passage': philIriFixtureScoresheetPassage,
        'Method': 'whole text',
        'Time': '2:30',
        PhilIriMiscueType.omission.label: 2,
      },
      if (k == 2) ...{'Round': 'GST', 'Date': date, 'GST score': 25},
    });
  }
  File(path).writeAsBytesSync(writeXlsx([
    XlsxSheetSpec(name: 'Learners', cells: cells, textColumns: {1, 5, 8}),
  ]));
}
