// Demo builder arguments and resume state (demo-data plan Task 5).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../../tool/demo_data/build_args.dart';
import '../../../tool/demo_data/state.dart';

void main() {
  group('build args', () {
    test('config is required', () {
      expect(parseBuildArgs([]), isNull);
      expect(parseBuildArgs(['--config']), isNull);
      expect(parseBuildArgs(['--dir', 'x']), isNull);
    });

    test('config and the default folder', () {
      final a = parseBuildArgs(['--config', 'x.json'])!;
      expect(a.configPath, 'x.json');
      expect(a.dir, r'D:\0_CAPSTONE\verify\demo');
    });

    test('--dir overrides the folder', () {
      expect(parseBuildArgs(['--config', 'x.json', '--dir', 'y'])!.dir, 'y');
    });

    test('--only picks a phase; none = every step', () {
      expect(parseBuildArgs(['--config', 'x.json'])!.only, isNull);
      expect(parseBuildArgs(['--config', 'x.json', '--only', 'setup'])!.only, 'setup');
      expect(parseBuildArgs(['--config', 'x.json', '--only']), isNull);
    });

    test('a phase selects its own steps only', () {
      expect(stepSelected('setup.schools', null), isTrue);
      expect(stepSelected('setup.schools', 'setup'), isTrue);
      expect(stepSelected('setup', 'setup'), isTrue);
      expect(stepSelected('setup.schools', 'setup.schools'), isTrue);
      expect(stepSelected('setupx', 'setup'), isFalse);
      expect(stepSelected('rosters-2025', 'setup'), isFalse);
    });

    test('an unknown argument is refused', () {
      expect(parseBuildArgs(['--config', 'x.json', '--force']), isNull);
    });
  });

  group('state', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('basa_demo_state_'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('a finished step survives a reload', () async {
      final s = await DemoState.load(dir);
      expect(s.done('setup.schools'), isFalse);
      await s.markDone('setup.schools');
      expect((await DemoState.load(dir)).done('setup.schools'), isTrue);
      // A second save replaces the file (rename over an existing file).
      await s.markDone('rosters-2025');
      final again = await DemoState.load(dir);
      expect((again.done('setup.schools'), again.done('rosters-2025')), (true, true));
    });

    test('ids survive a reload', () async {
      await (await DemoState.load(dir)).putId('school.NCES-DEMO', 5);
      expect((await DemoState.load(dir)).ids['school.NCES-DEMO'], 5);
    });

    test('a corrupt file throws naming the file, never starts over', () async {
      File('${dir.path}/state.json').writeAsStringSync('{not json');
      await expectLater(DemoState.load(dir),
          throwsA(isA<FormatException>().having((e) => e.message, 'message', contains('state.json'))));
      expect(File('${dir.path}/state.json').readAsStringSync(), '{not json');
    });
  });
}
