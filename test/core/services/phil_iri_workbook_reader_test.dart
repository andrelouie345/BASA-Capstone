// Phil-IRI import Task 6: ma's workbook reader (plan
// docs/superpowers/plans/2026-11-09-phil-iri-import.md, spec D4, D9 as amended
// by R1 D18 and R2 D10, D14). Fixture workbooks use made-up names.
import 'dart:io';

import 'package:basa_capstone/core/models/phil_iri_assessment.dart' show PhilIriRound;
import 'package:basa_capstone/core/models/phil_iri_import.dart';
import 'package:basa_capstone/core/models/phil_iri_miscue.dart';
import 'package:basa_capstone/core/models/phil_iri_reading.dart' show PhilIriReadingMethod;
import 'package:basa_capstone/core/services/phil_iri_import_headers.dart';
import 'package:basa_capstone/core/services/phil_iri_workbook_reader.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/phil_iri_workbook_fixture.dart';

const _bosy = PhilIriRound.bosy, _mosy1 = PhilIriRound.mosy1, _mosy2 = PhilIriRound.mosy2;

// Learners (made up).
const ana = WbLearner('Abad, Ana B.', gst: 19, rounds: {
  _bosy: WbRound(passage: '7C Dust', wordsRead: 169, mm: 1, comprehension: 3, reversal: 2, repetition: 3,
      mispronunciation: 1, adjProfile: 'Frustration', adjLevel: 5),
  _mosy1: WbRound(passage: '7D2 Ecosystems', wordsRead: 118, comprehension: 5),
});
const ben = WbLearner('Bautista, Ben C.', gst: 23, rounds: {
  _bosy: WbRound(passage: '7C Dust', wordsReadFormula: true, mm: 1), // words read left as the formula
  _mosy1: WbRound(passage: '7D2 Ecosystems', wordsRead: 140), // no comprehension: word reading only
});
const cara = WbLearner('Cruz, Cara D.', gst: 9, rounds: {
  _bosy: WbRound(wordsRead: 145, mm: 2, ss: 5, comprehension: 4), // whole text, no passage: Untitled
  _mosy1: WbRound(wordsRead: 90, comprehension: 6), // one minute, no passage: Untitled
  _mosy2: WbRound(passage: '7A2 Diving'), // passage only: incomplete
});
const dina = WbLearner('Diaz, Dina E.', rounds: {
  _bosy: WbRound(comprehension: 2, omission: 4), // comprehension only, no passage, miscues dropped
  _mosy1: WbRound(passage: '7C Dust', comprehension: 0), // comprehension only with a passage (0 counts)
});

const full = WbSheet('03',
    males: [ana, ben],
    females: [cara, dina],
    methods: {_bosy: 'Whole-Text Reading', _mosy1: 'One-Minute Reading'});

void main() {
  late PhilIriImportHeaders headers;

  setUp(() async {
    headers = await PhilIriImportHeaders.load(Directory.systemTemp.createTempSync('basa_wb_headers_').path);
  });

  PhilIriImportPlan read(List<WbSheet> sheets, {List<String> other = const ['STARTHERE']}) =>
      readPhilIriWorkbook(buildPhilIriWorkbook(sheets, otherSheets: other), headers);

  PhilIriImportReading reading(PhilIriImportPlan p, WbLearner l, PhilIriRound r) =>
      p.readings.singleWhere((x) => x.learner.name == l.name && x.round == r);

  bool hasReading(PhilIriImportPlan p, WbLearner l, PhilIriRound r) =>
      p.readings.any((x) => x.learner.name == l.name && x.round == r);

  test('finds section sheets by content, ignores the rest and the Sample sheet', () {
    final p = read([full, const WbSheet('Sample', males: [ana]), const WbSheet('07', section: 'GOLD')],
        other: ['STARTHERE', 'AlphaList']);
    expect(p.source, PhilIriImportSource.workbook);
    expect([for (final s in p.sections) s.sheet], ['03', '07']);
    final s = p.sections.first;
    expect((s.depedSchoolId, s.schoolYear, s.grade, s.sectionName, s.empty), ('303988', '2027-2028', 7, 'IRON', false));
  });

  test('empty sheet is listed as empty', () {
    final p = read([const WbSheet('07', section: 'GOLD')]);
    expect(p.sections.single.empty, isTrue);
    expect(p.readings, isEmpty);
    expect(p.gst, isEmpty);
  });

  test('reads GST, both methods, all five blocks', () {
    final p = read([full]);
    expect({for (final g in p.gst) g.learner.name: (g.score, g.max, g.learner.sex)}, {
      ana.name: (19, 40, 'M'),
      ben.name: (23, 40, 'M'),
      cara.name: (9, 40, 'F'),
    });
    expect(p.gst.first.ref.sheet, '03');
    final a = reading(p, ana, _bosy);
    expect(a.method, PhilIriReadingMethod.wholeText);
    expect((a.seconds, a.wordsRead, a.correctCount, a.correctTotal), (60, 169, 3, 8));
    expect((a.passage!.raw, a.passage!.level, a.passage!.code, a.passage!.title), ('7C Dust', 7, '7C', 'Dust'));
    expect(a.date, isNull);
    expect(a.ref.row, wbRowOf(full, ana));
    final a1 = reading(p, ana, _mosy1);
    expect(a1.method, PhilIriReadingMethod.oneMinute);
    expect((a1.wordsRead, a1.seconds, a1.correctCount, a1.correctTotal), (118, null, 5, 8));
    expect(a1.passage!.code, '7D2');
    // A learner in the last block (EOSY) is read too.
    final eosy = WbSheet('09', males: [
      const WbLearner('Echo, Eli', rounds: {PhilIriRound.eosy: WbRound(passage: '7B Rain', wordsRead: 100, comprehension: 12)}),
    ]);
    final e = read([eosy]).readings.single;
    expect((e.round, e.wordsRead, e.correctCount, e.correctTotal), (PhilIriRound.eosy, 100, 12, 20));
  });

  test('D4 mapping: reversal counted, repetition self-corrected', () {
    final a = reading(read([full]), ana, _bosy);
    expect(a.miscues, {PhilIriMiscueType.mispronunciation: 1, PhilIriMiscueType.reversal: 2});
    expect(a.selfCorrected, 3);
  });

  test('one-minute words read left as the formula 0 is incomplete', () {
    final p = read([const WbSheet('03', males: [ben])]);
    expect(hasReading(p, ben, _bosy), isFalse);
    final skip = p.skipped.singleWhere((s) => s.learner.name == ben.name && s.round == _bosy);
    expect(skip.reason, startsWith('incomplete'));
  });

  test('passage with no comprehension imports as word reading only', () {
    final b = reading(read([full]), ben, _mosy1);
    expect((b.wordsRead, b.correctCount, b.correctTotal), (140, null, null));
  });

  test('blank passage with words read and time is Untitled', () {
    final p = read([full]);
    final whole = reading(p, cara, _bosy);
    expect(whole.isUntitled, isTrue);
    expect((whole.method, whole.seconds, whole.wordCount, whole.wordsRead), (PhilIriReadingMethod.wholeText, 125, 145, null));
    expect((whole.correctCount, whole.correctTotal), (4, 8));
    final minute = reading(p, cara, _mosy1);
    expect(minute.isUntitled, isTrue);
    expect((minute.wordsRead, minute.wordCount, minute.correctCount, minute.correctTotal), (90, null, 6, 8));
  });

  test('Untitled comprehension without a readable maximum is dropped with a problem', () {
    final p = read([const WbSheet('03', females: [cara], methods: {_bosy: 'Whole-Text Reading'}, comprehensionMax: {_bosy: null})]);
    final whole = reading(p, cara, _bosy);
    expect((whole.wordCount, whole.correctCount, whole.correctTotal), (145, null, null));
    expect(p.problems.map((x) => x.message), contains('comprehension without a maximum, not imported'));
  });

  test('comprehension only is a reading without timing', () {
    final p = read([full]);
    final untitled = reading(p, dina, _bosy);
    expect(untitled.isUntitled, isTrue);
    expect((untitled.seconds, untitled.wordsRead, untitled.wordCount), (null, null, null));
    expect((untitled.correctCount, untitled.correctTotal), (2, 8));
    expect(untitled.miscues, isEmpty);
    expect(p.problems.where((x) => x.ref.row == wbRowOf(full, dina)).map((x) => x.message),
        contains('miscues without a time, not imported'));
    final withPassage = reading(p, dina, _mosy1);
    expect((withPassage.passage!.raw, withPassage.seconds, withPassage.wordsRead, withPassage.correctCount),
        ('7C Dust', null, null, 0));
  });

  test('passage only is incomplete', () {
    final p = read([full]);
    expect(hasReading(p, cara, _mosy2), isFalse);
    expect(p.skipped.singleWhere((s) => s.learner.name == cara.name && s.round == _mosy2).reason, startsWith('incomplete'));
  });

  test('a learner with nothing typed in a round gives nothing for it', () {
    final p = read([full]);
    expect(p.readings.where((x) => x.round == PhilIriRound.mosy3), isEmpty);
    expect(p.skipped.where((x) => x.round == PhilIriRound.mosy3), isEmpty);
  });

  test('learner blocks: sexes, empty numbered rows and the note below are not learners', () {
    final p = read([full]);
    final names = {for (final r in p.readings) r.learner.name, for (final s in p.skipped) s.learner.name};
    expect(names, {ana.name, ben.name, cara.name, dina.name});
    expect(reading(p, cara, _bosy).learner.sex, 'F');
    expect(reading(p, ana, _bosy).learner.sex, 'M');
    expect(p.problems.where((x) => x.message.contains('Prepared')), isEmpty);
  });

  test('moved column is still found', () {
    final p = read([const WbSheet('03', males: [ana], methods: {_bosy: 'Whole-Text Reading'}, insertColumnBeforeSelection: _bosy)]);
    expect(p.headerIssues, isEmpty);
    final a = reading(p, ana, _bosy);
    expect((a.passage!.raw, a.wordsRead, a.seconds, a.correctCount), ('7C Dust', 169, 60, 3));
    expect(reading(p, ana, _mosy1).wordsRead, 118);
  });

  test('renamed header gives a header issue with the headers found', () {
    final p = read([const WbSheet('03', males: [ana], renames: {'SELECTION': 'TEXT READ'})]);
    expect(p.readings, isEmpty);
    expect(p.gst, isEmpty);
    expect(p.sections.single.sheet, '03');
    final issue = p.headerIssues.firstWhere((i) => i.block == wbTitles[_bosy]);
    expect(issue.field, 'wb.selection');
    expect(issue.found, contains('TEXT READ'));
  });

  test('with an override it reads', () async {
    expect(await headers.set('wb.selection', 'Text read'), isNull);
    final p = read([const WbSheet('03', males: [ana], renames: {'SELECTION': 'TEXT READ'})]);
    expect(p.headerIssues, isEmpty);
    expect(reading(p, ana, _bosy).passage!.raw, '7C Dust');
  });

  // Owner option A (2026-11-11): ma's sheet 13 adds a note under the name header.
  test('a name header with a note in brackets still reads (sheet 13)', () {
    final p = read([const WbSheet('13', males: [ana], renames: {'NAME OF STUDENT': 'NAME OF STUDENT\n(Last Name, First Name)'})]);
    expect(p.sections.single.sheet, '13');
    expect(p.headerIssues, isEmpty);
    expect(reading(p, ana, _bosy).learner.name, ana.name);
  });

  test('a missing name header lists the sheet with a header issue, never drops it', () {
    final p = read([const WbSheet('13', males: [ana], renames: {'NAME OF STUDENT': 'LEARNER'})]);
    expect(p.sections.single.sheet, '13');
    expect(p.readings, isEmpty);
    expect(p.gst, isEmpty);
    final issue = p.headerIssues.single;
    expect((issue.field, issue.block), ('wb.name', 'sheet'));
    expect(issue.found, contains('LEARNER'));
  });

  test('cached adj profile and level are carried for the comparison', () {
    final a = reading(read([full]), ana, _bosy);
    expect((a.workbookProfile, a.workbookAdjustedLevel), ('Frustration', 5));
  });

  test('an unreadable value is a problem with sheet, row and column', () {
    final p = read([
      const WbSheet('03', males: [WbLearner('Abad, Ana B.', gst: 19, rounds: {_mosy1: WbRound(passage: '7C Dust', wordsRead: 100, comprehension: 9)})]),
    ]);
    // 9 correct out of a maximum of 8.
    final problem = p.problems.single;
    expect((problem.ref.sheet, problem.ref.row, problem.ref.column), ('03', 14, 'BM'));
    expect(problem.message, contains('more than'));
    expect(reading(p, const WbLearner('Abad, Ana B.'), _mosy1).correctCount, isNull);
  });
}
