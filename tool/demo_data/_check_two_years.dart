// THROWAWAY (demo-data plan Task 1): does a 2026-2027 SF1 with the same LRNs
// one grade up give a new enrollment (no conflict), and does learner history
// show both years? Deleted after the check.
import 'dart:convert';
import 'dart:io';

import 'package:basa_capstone/core/services/sf1_column_map.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../command_pass/device.dart';
import '../command_pass/sf1_fixture.dart';

Future<void> main(List<String> argv) async {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  final run = Directory(r'D:\0_CAPSTONE\verify\demo\check_two_years');
  final resolveOnly = argv.contains('--resolve');
  if (!resolveOnly) {
    if (run.existsSync()) run.deleteSync(recursive: true);
    run.createSync(recursive: true);
  }
  final devices = DeviceManager(run, configSource: r'D:\0_CAPSTONE\verify\data\supabase_config.json');
  final dev = await devices.switchTo('super', 'admin', fresh: !resolveOnly);
  Future<String> cmd(String name, List<String> args) async {
    final out = await dev.command(name)!.handler(args);
    stdout.writeln('> $name ${args.join(' ')}\n$out\n');
    return out;
  }

  final acc = jsonDecode(File(r'D:\0_CAPSTONE\verify\pass\accounts.json').readAsStringSync())['super'];
  await cmd('sign-in', ['cloud', acc['email'], acc['password']]);
  if (resolveOnly) {
    for (final id in ['418', '419', '420']) {
      await cmd('resolve-conflict', [id, 'update']);
    }
    await cmd('learner-history-lrn', ['999199990001']);
    await devices.close();
    return;
  }
  await cmd('school-create', ['ZZDEMOCHK', 'X', '-', 'ZZTEST DEMO CHECK']);

  const learners = [
    Sf1Learner('999199990001', 'ZZCHECK', 'Ana', 'F', birthDate: '2017-03-01'),
    Sf1Learner('999199990002', 'ZZCHECK', 'Ben', 'M', birthDate: '2017-04-01'),
    Sf1Learner('999199990003', 'ZZCHECK', 'Cara', 'F', birthDate: '2017-05-01'),
  ];
  final map = await Sf1ColumnMap.load(dev.dir.path);
  for (final (year, grade) in [('2025-2026', '3'), ('2026-2027', '4')]) {
    final path = '${run.path}/sf1_$year.xlsx';
    writeSf1(path,
        map: map,
        schoolCode: 'ZZDEMOCHK',
        schoolName: 'ZZTEST DEMO CHECK',
        regionLabel: sf1RegionLabel,
        schoolYear: year,
        grade: grade,
        section: 'ZZCHECK-G$grade',
        learners: learners);
    await cmd('import-trial', [path]);
    await cmd('import-students', [path]);
  }
  await cmd('list-conflicts', []);
  await cmd('learner-history-lrn', ['999199990001']);
  await devices.close();
}
