// The .xls reader (third_party/excel2003, BASA's fixed copy) reads shared
// strings whose characters cross a CONTINUE record. In BIFF8 the CONTINUE
// record then starts with one option byte (bit 0: 2-byte characters) for the
// rest of the string; a split between strings has no such byte. Before the
// fix the reader ignored it: one string came out one byte off, the next
// swallowed the rest of the table and every later text cell read empty
// (a real SF1, 2026-11-12).
import 'dart:typed_data';

import 'package:excel2003/src/biff/biff_records.dart';
import 'package:excel2003/src/biff/sst_parser.dart';
import 'package:flutter_test/flutter_test.dart';

/// One BIFF record: type, length, data.
List<int> _record(int type, List<int> data) => [type & 0xff, type >> 8, data.length & 0xff, data.length >> 8, ...data];

/// SST header: total and unique string counts.
List<int> _sstHeader(int count) => [
      count & 0xff, count >> 8, 0, 0, //
      count & 0xff, count >> 8, 0, 0,
    ];

/// A compressed (1-byte) string's header + characters.
List<int> _latin(String s) => [s.length, 0, 0x00, ...s.codeUnits];

/// A 2-byte string's header + characters.
List<int> _wide(String s) => [s.length, 0, 0x01, for (final c in s.codeUnits) ...[c & 0xff, c >> 8]];

List<String> _read(List<int> stream) {
  final record = BiffParser(Uint8List.fromList(stream)).nextRecordWithContinue()!;
  final sst = SstParser()..parse(record);
  return sst.strings;
}

void main() {
  test('a 1-byte string split across a CONTINUE: the option byte is skipped', () {
    final stream = [
      ..._record(BiffRecordType.sst, [..._sstHeader(4), ..._latin('First'), 6, 0, 0x00, ...'Dela '.codeUnits]),
      ..._record(BiffRecordType.continueRec, [0x00, ...'C'.codeUnits, ..._latin('After'), ..._latin('Last')]),
    ];
    expect(_read(stream), ['First', 'Dela C', 'After', 'Last']);
  });

  test('a split that switches the rest of the string to 2-byte characters', () {
    final stream = [
      ..._record(BiffRecordType.sst, [..._sstHeader(2), 4, 0, 0x00, ...'Ni'.codeUnits]),
      ..._record(BiffRecordType.continueRec, [0x01, ...[0xF1, 0x00], ...[0x6F, 0x00], ..._latin('Next')]),
    ];
    expect(_read(stream), ['Niño', 'Next']);
  });

  test('a 2-byte string continued as 1-byte characters', () {
    final stream = [
      ..._record(BiffRecordType.sst, [..._sstHeader(2), 3, 0, 0x01, ...[0xD1, 0x00]]),
      ..._record(BiffRecordType.continueRec, [0x00, ...'ok'.codeUnits, ..._wide('Ma')]),
    ];
    expect(_read(stream), ['Ñok', 'Ma']);
  });

  test('a split between two strings has no option byte', () {
    final stream = [
      ..._record(BiffRecordType.sst, [..._sstHeader(2), ..._latin('One')]),
      ..._record(BiffRecordType.continueRec, [..._latin('Two')]),
    ];
    expect(_read(stream), ['One', 'Two']);
  });

  test('a string over two CONTINUE records, and every later string is read', () {
    final stream = [
      ..._record(BiffRecordType.sst, [..._sstHeader(3), 9, 0, 0x00, ...'abc'.codeUnits]),
      ..._record(BiffRecordType.continueRec, [0x00, ...'def'.codeUnits]),
      ..._record(BiffRecordType.continueRec, [0x00, ...'ghi'.codeUnits, ..._latin('x'), ..._latin('y')]),
    ];
    expect(_read(stream), ['abcdefghi', 'x', 'y']);
  });

  test('no CONTINUE: unchanged', () {
    final stream = _record(BiffRecordType.sst, [..._sstHeader(2), ..._latin('A'), ..._wide('B')]);
    expect(_read(stream), ['A', 'B']);
  });
}
