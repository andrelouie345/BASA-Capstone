// Editable header labels of the Phil-IRI import readers (plan Task 5).
import 'dart:io';

import 'package:basa_capstone/core/models/phil_iri_import.dart';
import 'package:basa_capstone/core/models/phil_iri_miscue.dart';
import 'package:basa_capstone/core/services/phil_iri_import_headers.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory dir;

  setUp(() async => dir = await Directory.systemTemp.createTemp('basa_headers_'));
  tearDown(() async => dir.delete(recursive: true));

  File file() => File('${dir.path}/phil_iri_import_headers.json');

  test('defaults are ma\'s labels', () async {
    final h = await PhilIriImportHeaders.load(dir.path);
    expect(h.label('wb.mispronunciation'), 'Mispronounciation');
    expect(h.label('wb.repetition'), 'Repetition / Self-orrection');
    expect(h.label('wb.block.mosy2'), 'MIDDLE OF SCHOOL YEAR ASSESSMENT (MOSY #2)');
    expect(h.label('ss.lrn'), 'LRN');
    for (final t in PhilIriMiscueType.values) {
      expect(h.labels.containsKey('ss.${t.name}'), isTrue, reason: t.name);
    }
    expect(file().existsSync(), isFalse, reason: 'nothing changed, nothing stored');
  });

  test('set persists and reload sees it', () async {
    final h = await PhilIriImportHeaders.load(dir.path);
    expect(await h.set('wb.wordsRead', 'No. of Words Read'), isNull);
    expect(h.label('wb.wordsRead'), 'No. of Words Read');

    final again = await PhilIriImportHeaders.load(dir.path);
    expect(again.label('wb.wordsRead'), 'No. of Words Read');
    expect(again.label('wb.name'), 'NAME OF STUDENT');
    // Only the changed label is stored.
    expect(file().readAsStringSync(), isNot(contains('NAME OF STUDENT')));
  });

  test('set refuses an unknown field', () async {
    final h = await PhilIriImportHeaders.load(dir.path);
    expect(await h.set('wb.nope', 'x'), startsWith('Unknown header field "wb.nope"'));
    expect(file().existsSync(), isFalse);
  });

  test('set refuses an empty label', () async {
    final h = await PhilIriImportHeaders.load(dir.path);
    expect(await h.set('wb.name', '  / '), isNotNull);
    expect(h.label('wb.name'), 'NAME OF STUDENT');
  });

  test('setting the default label back removes the override', () async {
    final h = await PhilIriImportHeaders.load(dir.path);
    await h.set('wb.time', 'Reading Time');
    await h.set('wb.time', 'total time reading the text'); // same once normalized
    final again = await PhilIriImportHeaders.load(dir.path);
    expect(again.label('wb.time'), 'Total Time Reading the Text');
    expect(again.changed, isEmpty);
  });

  test('reset restores the defaults and deletes the file', () async {
    final h = await PhilIriImportHeaders.load(dir.path);
    await h.set('ss.q', 'Question ');
    expect(file().existsSync(), isTrue);
    await h.reset();
    expect(h.label('ss.q'), 'Q');
    expect(file().existsSync(), isFalse);
  });

  test('a stored unknown field or a broken file is ignored', () async {
    file().writeAsStringSync('{"wb.gone": "x", "wb.gst": "GST Score"}');
    final h = await PhilIriImportHeaders.load(dir.path);
    expect(h.label('wb.gst'), 'GST Score');
    expect(h.labels.containsKey('wb.gone'), isFalse);

    file().writeAsStringSync('not json');
    final broken = await PhilIriImportHeaders.load(dir.path);
    expect(broken.label('wb.gst'), 'GST Raw Score');
  });

  test('matches compares normalized labels', () async {
    final h = await PhilIriImportHeaders.load(dir.path);
    expect(h.matches('wb.omission', 'omission/\ndeletion'), isTrue);
    expect(h.matches('wb.omission', 'Omission'), isFalse);
  });

  test('import ref prints sheet, row and column', () {
    expect(const PhilIriImportRef(sheet: '03', row: 17, column: 'AV').toString(), 'sheet 03, row 17, column AV');
    expect(const PhilIriImportRef(sheet: 'Learners', row: 4).toString(), 'sheet Learners, row 4');
  });
}
