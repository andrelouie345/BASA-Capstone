// Files written by console commands (command pass finding F4).
import 'dart:io';

import 'package:basa_capstone/core/console/file_output.dart';
import 'package:basa_capstone/core/models/student.dart';
import 'package:basa_capstone/core/services/roster_exporter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('basa_out_'));

  test('writes text and bytes, returning null', () async {
    expect(await writeOutputFile('${dir.path}/a.csv', text: 'x,y\n'), isNull);
    expect(File('${dir.path}/a.csv').readAsStringSync(), 'x,y\n');
    expect(await writeOutputFile('${dir.path}/b.bin', bytes: [1, 2, 3]), isNull);
    expect(File('${dir.path}/b.bin').readAsBytesSync(), [1, 2, 3]);
  });

  test('a file it cannot write gives a readable message, not an exception', () async {
    final path = '${dir.path}/no-such-folder/a.csv';
    final message = await writeOutputFile(path, text: 'x');
    expect(message, startsWith("Couldn't write ${outputPath(path)}: "));
    expect(message, isNot(contains('Exception')));
    expect(message, isNot(contains('errno')));
  });

  test('outputPath shows where a relative path lands', () {
    expect(outputPath('g2.csv'), p.normalize(p.join(Directory.current.path, 'g2.csv')));
    expect(outputPath('${dir.path}/sub/../a.csv'), p.normalize(p.join(dir.path, 'a.csv')));
  });

  test('the error names the full path', () async {
    final message = await writeOutputFile('no-such-folder-zz/a.csv', text: 'x');
    expect(message, startsWith("Couldn't write ${outputPath('no-such-folder-zz/a.csv')}: "));
  });

  test('roster CSV: header, one row per learner, escaped values', () {
    final csv = RosterExporter().toCsv([
      Student(lrn: '999000052001', lastName: 'ZZTESTA', firstName: 'Learner, One', sex: 'M'),
      Student(lrn: '999000052002', lastName: 'Dela "Cruz"', firstName: 'Ana'),
    ]);
    final lines = csv.trimRight().split('\n');
    expect(lines, hasLength(3));
    expect(lines[0], startsWith('LRN,Last Name,First Name,Middle Name,Sex,'));
    expect(lines[1], startsWith('999000052001,ZZTESTA,"Learner, One",,M,'));
    expect(lines[2], startsWith('999000052002,"Dela ""Cruz""",Ana,'));
  });
}
