// Builds the Night City demo world (spec docs/superpowers/specs/2026-11-24-demo-data-design.md):
//   dart run tool/demo_data/build.dart --config <supabase_config.json> [--dir <folder>]
// Shows the server and waits for "yes" before writing anything. Resumable:
// finished steps are recorded in <dir>/state.json and skipped next time.
import 'dart:convert';
import 'dart:io';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'build_args.dart';
import 'phases/setup.dart';
import 'session.dart';
import 'state.dart';
import 'world.dart';

/// One step of the build: its name in state.json and what it does.
typedef DemoStep = ({String name, Future<void> Function(DemoSession s, DemoState st, DemoWorld w, DateTime today) run});

/// The steps in order (filled by the phases, demo-data plan Tasks 6-12).
final List<DemoStep> demoSteps = [
  for (final step in setupSteps) (name: step.name, run: (s, st, w, today) => step.run(s, st)),
];

Future<void> main(List<String> args) async {
  final a = parseBuildArgs(args);
  if (a == null) {
    stderr.writeln(demoBuildUsage);
    exit(64);
  }
  final config = File(a.configPath);
  if (!config.existsSync()) {
    stderr.writeln('No such config file: ${a.configPath}');
    exit(66);
  }
  final url = ((jsonDecode(config.readAsStringSync()) as Map<String, dynamic>)['cloud'] as Map?)?['url'];
  stdout
    ..writeln('Server:  ${url ?? '(no cloud url in the config)'}')
    ..writeln('Schools: ${demoSchools.map((s) => '${s.code} ${s.name}').join(', ')}')
    ..writeln('Folder:  ${a.dir}')
    ..writeln('Steps:   ${a.only ?? 'all'}')
    ..write('Type yes to build the Night City demo world on this server: ');
  if (stdin.readLineSync()?.trim() != 'yes') {
    stdout.writeln('Nothing written.');
    exit(1);
  }

  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  final dir = Directory(a.dir);
  final session = await DemoSession.open(dir, configPath: a.configPath);
  var code = 0;
  try {
    final state = await DemoState.load(dir);
    final world = DemoWorld.build();
    final today = DateTime.now();
    final steps = [for (final step in demoSteps) if (stepSelected(step.name, a.only)) step];
    if (steps.isEmpty) throw StateError('no step matches --only ${a.only}');
    for (final step in steps) {
      if (state.done(step.name)) {
        stdout.writeln('= ${step.name} (done earlier)');
        continue;
      }
      stdout.writeln('> ${step.name}');
      await step.run(session, state, world, today);
      await state.markDone(step.name);
    }
    stdout.writeln('Done: ${steps.length} steps.');
  } catch (e, st) {
    stderr.writeln('Stopped: $e\n$st\nRun the same command again to continue.');
    code = 1;
  } finally {
    await session.close();
  }
  exit(code); // the Supabase client keeps the process alive otherwise
}
