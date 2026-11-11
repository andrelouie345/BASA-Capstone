// The BASA Phil-IRI scoresheet file (Phil-IRI import plan, Task 7): the
// per-section template and its reader.
//
// Set PHIL_IRI_SCORESHEET_OUT=<file.xlsx> to also save the generated template
// (verify kit t7: open it in Excel, no repair prompt, the drop-downs work),
// and PHIL_IRI_SCORESHEET_IN=<file.xlsx> to print what the reader makes of a
// file filled in Excel (kit t7; skipped when unset).
// ignore_for_file: avoid_print (verify kit step prints the plan)

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:basa_capstone/core/models/phil_iri_assessment.dart' show PhilIriRound;
import 'package:basa_capstone/core/models/phil_iri_import.dart';
import 'package:basa_capstone/core/models/phil_iri_miscue.dart';
import 'package:basa_capstone/core/models/phil_iri_passage.dart';
import 'package:basa_capstone/core/models/phil_iri_reading.dart' show PhilIriReadingMethod;
import 'package:basa_capstone/core/models/section.dart';
import 'package:basa_capstone/core/models/student.dart';
import 'package:basa_capstone/core/services/phil_iri_import_headers.dart';
import 'package:basa_capstone/core/services/phil_iri_scoresheet_reader.dart';
import 'package:basa_capstone/core/services/phil_iri_scoresheet_template.dart';
import 'package:basa_capstone/core/services/xlsx_cells.dart';
import 'package:flutter_test/flutter_test.dart';

PhilIriPassage _p(int id, String title, {String? testType, String? setCode, int level = 7, bool active = true}) =>
    PhilIriPassage(
      id: id,
      collectionId: 1,
      testType: testType,
      setCode: setCode,
      level: level,
      title: title,
      body: 'one two three',
      wordCount: 3,
      isActive: active,
    );

final _section = Section(id: 5, schoolId: 1, schoolYear: '2026-2027', gradeLevel: '7', sectionName: 'Rizal');
final _learners = [
  Student(id: 1, lrn: '012345678901', lastName: 'Cruz', firstName: 'Ana', sex: 'F'),
  Student(id: 2, lrn: '123456789012', lastName: 'Reyes', firstName: 'Ben', middleName: 'Santos', sex: 'M'),
];
final _passages = [
  _p(10, 'Dust', testType: 'mosy', setCode: 'C1'),
  _p(11, 'Lili the Lizard and Koko the Gecko', testType: 'pre'),
  _p(12, 'Lili the Lizard and Koko the Gecko', testType: 'pre'), // same text, second collection
  _p(13, 'Dark Chocolate', testType: 'pre', setCode: 'A'),
  _p(14, 'Diving', testType: 'post', setCode: 'A'),
  _p(15, 'Old One', setCode: 'Z', active: false),
  _p(16, 'Grade Eight', setCode: 'A1', level: 8),
];

/// Column letter of [label] in the Learners header row.
String _col(Map<String, Object> cells, String label) {
  for (final e in cells.entries) {
    final (c, r) = splitRef(e.key);
    if (r == 1 && e.value == label) return columnLetters(c);
  }
  throw StateError('no column "$label"');
}

void main() {
  late Directory dir;
  late PhilIriImportHeaders headers;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('basa_scoresheet_');
    headers = await PhilIriImportHeaders.load(dir.path);
  });
  tearDown(() async => dir.delete(recursive: true));

  List<int> template() =>
      buildPhilIriScoresheetTemplate(section: _section, learners: _learners, passages: _passages, headers: headers);

  /// The template with [rows] written over the Learners sheet: row number ->
  /// header label -> value.
  List<int> filled(Map<int, Map<String, Object?>> rows) {
    final wb = XlsxWorkbook.decode(template());
    final head = wb.readSheet('Learners');
    wb.write('Learners', {
      for (final r in rows.entries)
        for (final c in r.value.entries) '${_col(head, c.key)}${r.key}': c.value,
    });
    return wb.encode();
  }

  test('passage codes are the booklet codes', () {
    expect(philIriPassageCode(_passages[0]), 'G7C1');
    expect(philIriPassageCode(_passages[1]), 'G7Pre');
    expect(philIriPassageCode(_passages[3]), 'G7A');
    expect(philIriPassageCode(_passages[4]), 'G7A');
    expect(philIriPassageCode(_p(1, 'Jeepney', testType: 'post')), 'G7Post');
    expect(philIriPassageCode(_p(1, 'Pool', testType: 'mosy')), 'G7');
  });

  test('template: learners pre-filled, codes listed once with titles, drop-downs, instructions', () {
    final bytes = template();
    final out = Platform.environment['PHIL_IRI_SCORESHEET_OUT'];
    if (out != null) File(out).writeAsBytesSync(bytes);

    final wb = XlsxWorkbook.decode(bytes);
    expect(wb.sheetNames, ['Learners', 'Codes', 'Instructions']);
    final l = wb.readSheet('Learners');
    final lrn = _col(l, 'LRN');
    expect(l['${lrn}2'], '012345678901', reason: 'LRN written as text, leading zero kept');
    expect(l['${_col(l, 'Learner')}3'], 'Reyes, Ben Santos');
    expect(l['${_col(l, 'Sex')}2'], 'F');
    for (final label in [
      'Round', 'Date', 'Passage', 'Method', 'Time', 'Words read', 'Mispronunciation', 'Reversal',
      'Self-corrected', 'GST score', 'Q1', 'Q20',
    ]) {
      _col(l, label);
    }
    expect(l.containsKey('A4'), isFalse, reason: 'one row per learner');

    final codes = wb.readSheet('Codes').values.whereType<String>().toList();
    expect(codes, containsAll(['GST', 'BOSY', 'MOSY1', 'MOSY2', 'MOSY3', 'EOSY']));
    expect(codes, containsAll(['whole text', 'one minute', 'silent']));
    expect(codes, containsAll(['G7C1 Dust', 'G7A Dark Chocolate', 'G7A Diving']));
    expect(codes.where((c) => c == 'G7Pre Lili the Lizard and Koko the Gecko').length, 1,
        reason: 'same code and title listed once');
    expect(codes.any((c) => c.contains('Old One')), isFalse, reason: 'inactive passage');
    expect(codes.any((c) => c.contains('Grade Eight')), isFalse, reason: 'other grade');

    final sheet1 = utf8.decode(ZipDecoder().decodeBytes(bytes).findFile('xl/worksheets/sheet1.xml')!.content);
    final lists = RegExp(r'sqref="([A-Z]+)\d+:[A-Z]+\d+"><formula1>([^<]+)<').allMatches(sheet1)
        .map((m) => '${m.group(1)} ${m.group(2)}').toSet();
    expect(lists.map((s) => s.split(' ').first),
        containsAll([_col(l, 'Round'), _col(l, 'Method'), _col(l, 'Passage')]),
        reason: 'drop-downs on Round, Method, Passage: $lists');
    expect(wb.readSheet('Instructions').values.whereType<String>().join('\n'), contains('never guess'));
  });

  test('template round trip: filled rows read back as entered', () {
    final plan = readPhilIriScoresheet(
      filled({
        2: {
          'Round': 'BOSY', 'Date': '2026-08-15', 'Passage': 'G7C1 Dust', 'Method': 'whole text', 'Time': '2:35',
          'Words read': null, 'Mispronunciation': 2, 'Omission': 1, 'Reversal': 1, 'Self-corrected': 3,
          'Q1': 'a', 'Q2': 'B', 'Q3': null, 'Q4': 'd',
        },
        3: {'Round': 'MOSY1', 'Date': '10/20/2026', 'Passage': 'G7A Diving', 'Method': 'one minute', 'Words read': 96},
      }),
      'scoresheet.xlsx',
      headers,
    );
    expect(plan.source, PhilIriImportSource.scoresheet);
    expect(plan.problems, isEmpty, reason: '${plan.problems}');
    expect(plan.headerIssues, isEmpty);
    expect(plan.readings, hasLength(2));

    final a = plan.readings[0];
    expect(a.learner.lrn, '012345678901');
    expect(a.round, PhilIriRound.bosy);
    expect(a.date, '2026-08-15');
    expect(a.passage!.code, 'G7C1');
    expect(a.passage!.level, 7);
    expect(a.passage!.title, 'Dust');
    expect(a.method, PhilIriReadingMethod.wholeText);
    expect(a.seconds, 155);
    expect(a.miscues, {
      PhilIriMiscueType.mispronunciation: 2,
      PhilIriMiscueType.omission: 1,
      PhilIriMiscueType.reversal: 1,
    });
    expect(a.selfCorrected, 3);
    expect(a.answers, ['a', 'b', null, 'd'], reason: 'any case; blank stays null; trimmed after the last answer');
    expect(a.correctCount, isNull);
    expect(a.ref.row, 2);

    final b = plan.readings[1];
    expect(b.learner.lrn, '123456789012');
    expect(b.round, PhilIriRound.mosy1);
    expect(b.date, '2026-10-20');
    expect(b.method, PhilIriReadingMethod.oneMinute);
    expect(b.wordsRead, 96);
    expect(b.passage!.title, 'Diving');
    expect(b.answers, isNull, reason: 'no answers = word reading only');
  });

  test('GST row needs only the score and the date', () {
    final plan = readPhilIriScoresheet(
      filled({2: {'Round': 'gst', 'Date': '2026-08-10', 'GST score': 14}}),
      'scoresheet.xlsx',
      headers,
    );
    expect(plan.problems, isEmpty, reason: '${plan.problems}');
    expect(plan.readings, isEmpty);
    expect(plan.gst, hasLength(1));
    expect(plan.gst.single.score, 14);
    expect(plan.gst.single.date, '2026-08-10');
    expect(plan.gst.single.learner.lrn, '012345678901');
  });

  test('Excel-mangled values read correctly (Review Focus 4)', () {
    final plan = readPhilIriScoresheet(
      filled({
        2: {
          'LRN': 123456789012.0, 'Round': 'EOSY', 'Date': 45883, 'Passage': 'G7C1 Dust', 'Method': 'whole text',
          'Time': 0.10763888888888888,
        },
        3: {'LRN': 12345678901, 'Round': 'BOSY', 'Date': '2026-08-15', 'Passage': 'G7C1 Dust', 'Method': 'silent',
            'Time': 155 / 86400},
        4: {'LRN': '012345678901', 'Round': 'BOSY', 'Date': '2026-08-15', 'Passage': 'G7C1 Dust', 'Method': 'whole text',
            'Time': 155},
      }),
      'scoresheet.xlsx',
      headers,
    );
    expect(plan.problems, isEmpty, reason: '${plan.problems}');
    expect(plan.readings[0].learner.lrn, '123456789012');
    expect(plan.readings[0].date, '2025-08-14', reason: 'serial 45883 (45658 = 2025-01-01)');
    expect(plan.readings[0].seconds, 155, reason: '2:35 typed into an h:mm cell');
    expect(plan.readings[1].learner.lrn, '012345678901', reason: 'lost leading zero restored');
    expect(plan.readings[1].seconds, 155, reason: 'a real 0:02:35');
    expect(plan.readings[1].method, PhilIriReadingMethod.silent);
    expect(plan.readings[2].seconds, 155, reason: 'whole seconds');
  });

  test('unknown round names the row and column', () {
    final wb = XlsxWorkbook.decode(template());
    final roundCol = _col(wb.readSheet('Learners'), 'Round');
    final plan = readPhilIriScoresheet(
      filled({3: {'Round': 'MOSY4', 'Date': '2026-08-15', 'Passage': 'G7C1 Dust', 'Method': 'one minute', 'Words read': 90}}),
      'scoresheet.xlsx',
      headers,
    );
    expect(plan.readings, isEmpty);
    expect(plan.problems, hasLength(1));
    final p = plan.problems.single;
    expect(p.ref.sheet, 'Learners');
    expect(p.ref.row, 3);
    expect(p.ref.column, roundCol);
    expect(p.message, contains('MOSY4'));
  });

  test('blank answer stays null and the row is kept', () {
    final plan = readPhilIriScoresheet(
      filled({2: {'Round': 'BOSY', 'Date': '2026-08-15', 'Passage': 'G7C1 Dust', 'Method': 'whole text', 'Time': '95',
          'Q1': null, 'Q2': 'c'}}),
      'scoresheet.xlsx',
      headers,
    );
    expect(plan.problems, isEmpty);
    expect(plan.readings.single.answers, [null, 'c']);
  });

  test('required values: date, passage (no Untitled in the scoresheet), method', () {
    final plan = readPhilIriScoresheet(
      filled({
        2: {'Round': 'BOSY', 'Passage': 'G7C1 Dust', 'Method': 'whole text', 'Time': '1:40'},
        3: {'Round': 'BOSY', 'Date': '2026-08-15', 'Method': 'whole text', 'Time': '1:40', 'Q1': 'a'},
      }),
      'scoresheet.xlsx',
      headers,
    );
    expect(plan.readings, isEmpty);
    expect(plan.problems.map((p) => p.message), containsAll(['Date is required', 'Passage is required']));
  });

  test('rows with only the pre-filled learner cells are ignored', () {
    final plan = readPhilIriScoresheet(template(), 'scoresheet.xlsx', headers);
    expect(plan.problems, isEmpty);
    expect(plan.readings, isEmpty);
    expect(plan.gst, isEmpty);
    expect(plan.skipped, isEmpty);
  });

  test('comprehension only, incomplete, silent miscues, unreadable values', () {
    final plan = readPhilIriScoresheet(
      filled({
        // answers but no time: a comprehension-only reading; its miscue dropped
        2: {'Round': 'MOSY2', 'Date': '2026-11-15', 'Passage': 'G7C1 Dust', 'Method': 'whole text', 'Omission': 2,
            'Q1': 'a'},
        // passage only: incomplete
        3: {'Round': 'MOSY2', 'Date': '2026-11-15', 'Passage': 'G7A Diving', 'Method': 'one minute'},
        // silent with a miscue: miscue dropped
        4: {'LRN': '012345678901', 'Round': 'EOSY', 'Date': '2027-03-15', 'Passage': 'G7A Diving', 'Method': 'silent', 'Time': '1:10',
            'Substitution': 1},
        // unreadable values: the row is refused, each value named
        5: {'LRN': '123456789012', 'Round': 'EOSY', 'Date': '2027-02-30', 'Passage': 'G7A Diving', 'Method': 'whole text', 'Time': 'soon',
            'Q1': 'ab'},
      }),
      'scoresheet.xlsx',
      headers,
    );
    expect(plan.readings, hasLength(2));
    final compOnly = plan.readings[0];
    expect(compOnly.seconds, isNull);
    expect(compOnly.wordsRead, isNull);
    expect(compOnly.miscues, isEmpty);
    expect(compOnly.answers, ['a']);
    final silent = plan.readings[1];
    expect(silent.method, PhilIriReadingMethod.silent);
    expect(silent.seconds, 70);
    expect(silent.miscues, isEmpty);

    expect(plan.skipped, hasLength(1));
    expect(plan.skipped.single.ref.row, 3);
    expect(plan.skipped.single.reason, startsWith('incomplete'));

    final msgs = plan.problems.map((p) => '${p.ref.row}: ${p.message}').toList();
    expect(msgs, contains('2: miscues without a time, not imported'));
    expect(msgs, contains('4: miscues on a silent reading, not imported'));
    expect(msgs.where((m) => m.startsWith('5: ')), hasLength(3), reason: '$msgs');
  });

  test('a renamed header is a header issue; with an override it reads', () async {
    final wb = XlsxWorkbook.decode(template());
    final passageCol = _col(wb.readSheet('Learners'), 'Passage');
    wb.write('Learners', {
      '${passageCol}1': 'Selection',
      '${_col(wb.readSheet('Learners'), 'Round')}2': 'BOSY',
      '${_col(wb.readSheet('Learners'), 'Date')}2': '2026-08-15',
      '${passageCol}2': 'G7C1 Dust',
      '${_col(wb.readSheet('Learners'), 'Method')}2': 'one minute',
      '${_col(wb.readSheet('Learners'), 'Words read')}2': 88,
    });
    final bytes = wb.encode();

    final before = readPhilIriScoresheet(bytes, 'scoresheet.xlsx', headers);
    expect(before.readings, isEmpty);
    expect(before.headerIssues.single.field, 'ss.passage');
    expect(before.headerIssues.single.found, contains('Selection'));

    expect(await headers.set('ss.passage', 'Selection'), isNull);
    final after = readPhilIriScoresheet(bytes, 'scoresheet.xlsx', headers);
    expect(after.headerIssues, isEmpty);
    expect(after.readings.single.wordsRead, 88);
  });

  test('verify kit: print a file filled in Excel', () {
    final path = Platform.environment['PHIL_IRI_SCORESHEET_IN']!;
    final plan = readPhilIriScoresheet(File(path).readAsBytesSync(), path, headers);
    for (final i in plan.headerIssues) {
      print('HEADER ISSUE ${i.field}: found ${i.found.join(' | ')}');
    }
    for (final g in plan.gst) {
      print('GST row ${g.ref.row}: lrn ${g.learner.lrn} score ${g.score} date ${g.date}');
    }
    for (final r in plan.readings) {
      print('READING row ${r.ref.row}: lrn ${r.learner.lrn} ${r.round.name} ${r.date} passage ${r.passage?.code} '
          '"${r.passage?.title}" ${r.method.name} seconds ${r.seconds} wordsRead ${r.wordsRead} '
          'miscues ${{for (final e in r.miscues.entries) e.key.name: e.value}} selfCorrected ${r.selfCorrected} '
          'answers ${r.answers}');
    }
    for (final k in plan.skipped) {
      print('SKIPPED row ${k.ref.row}: ${k.reason}');
    }
    for (final p in plan.problems) {
      print('PROBLEM $p');
    }
  }, skip: Platform.environment['PHIL_IRI_SCORESHEET_IN'] == null ? 'set PHIL_IRI_SCORESHEET_IN' : false);
}
