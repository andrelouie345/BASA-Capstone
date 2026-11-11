// The command pass's Phil-IRI files (scenario a7) read back as the scenario
// expects them, through the real readers.
import 'dart:io';

import 'package:basa_capstone/core/models/phil_iri_assessment.dart' show PhilIriRound;
import 'package:basa_capstone/core/models/phil_iri_miscue.dart';
import 'package:basa_capstone/core/services/phil_iri_import_headers.dart';
import 'package:basa_capstone/core/services/phil_iri_scoresheet_reader.dart';
import 'package:basa_capstone/core/services/phil_iri_workbook_reader.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../tool/command_pass/phil_iri_fixture.dart';
import '../../../tool/command_pass/sf1_fixture.dart';

void main() {
  late Directory dir;
  late PhilIriImportHeaders headers;
  // from=stamp can start on an even index: the first learner is then female.
  final learners = sf1Learners(runNumber: 99, grade: 7, count: 3, first: 202);

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('pif');
    headers = await PhilIriImportHeaders.load(dir.path);
  });
  tearDown(() => dir.delete(recursive: true));

  test('workbook: two sheets, two BOSY readings and three GSTs, nothing unreadable', () {
    final path = '${dir.path}/wb.xlsx';
    writePhilIriWorkbook(path,
        school: 'ZZPASS0099 - ZZTEST PASS r99', schoolYear: '2026-2027', grade: 7, section: 'ZZTEST-G7I1', learners: learners);
    final plan = readPhilIriWorkbook(File(path).readAsBytesSync(), headers);
    expect(plan.headerIssues, isEmpty);
    expect(plan.problems, isEmpty);
    expect([for (final s in plan.sections) '${s.sheet} ${s.sectionName} ${s.grade} ${s.schoolYear} ${s.depedSchoolId}'],
        ['01 ZZTEST-G7I1 7 2026-2027 null', '02 ZZTEST-NONE 7 2026-2027 null']);
    expect(plan.readings.map((r) => '${r.learner.name} ${r.round.name} ${r.passage?.level} ${r.passage?.title} '
        '${r.seconds} ${r.wordsRead} ${r.correctCount}/${r.correctTotal}').toList()..sort(), [
      'ZZTESTT, Learner202 bosy 7 Lili the Lizard and Koko the Gecko 150 357 8/10',
      'ZZTESTU, Learner203 bosy 7 Lili the Lizard and Koko the Gecko 190 357 3/10',
    ]);
    expect(plan.gst.map((g) => '${g.ref.sheet} ${g.learner.name} ${g.score}/${g.max}').toList()..sort(), [
      '01 ZZTESTT, Learner202 30/40',
      '01 ZZTESTU, Learner203 20/40',
      '02 ZZTESTT, Learner202 12/40',
    ]);
  });

  test('scoresheet: learner 1 MOSY 1 reading, learner 3 GST', () {
    final path = '${dir.path}/ss.xlsx';
    writePhilIriScoresheet(path, date: '2026-10-12', learners: learners);
    final plan = readPhilIriScoresheet(File(path).readAsBytesSync(), 'ss.xlsx', headers);
    expect(plan.headerIssues, isEmpty);
    expect(plan.problems, isEmpty);
    expect(plan.readings, hasLength(1));
    final r = plan.readings.single;
    expect('${r.learner.lrn} ${r.round} ${r.date} ${r.passage?.title} ${r.seconds} ${r.miscues[PhilIriMiscueType.omission]}',
        '${learners[0].lrn} ${PhilIriRound.mosy1} 2026-10-12 The Jeepney: A Filipino Tradition 150 2');
    expect(plan.gst.map((g) => '${g.learner.lrn} ${g.score}'), ['${learners[2].lrn} 25']);
  });
}
