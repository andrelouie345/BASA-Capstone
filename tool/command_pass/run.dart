// Command pass: runs the scenario files against the dev cloud and checks
// coverage of both builds' command lists.
//
//   dart run tool/command_pass/run.dart [--run r<N>] [batch...]
//
// Run from the repo root. Without --run, a new run r<N> starts (N from
// next_run.txt). Without batches, every scenario runs and coverage is
// checked. Runs live in D:\0_CAPSTONE\verify\pass (BASA_PASS_DIR overrides);
// the test superadmin's password is in accounts.json there.
import 'dart:convert';
import 'dart:io';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'checks.dart';
import 'coverage.dart';
import 'device.dart';
import 'report.dart';
import 'runner.dart';
import 'scenario.dart';

const _scenarioDir = 'tool/command_pass/scenarios';
const _configSource = r'D:\0_CAPSTONE\verify\data\supabase_config.json';

Never _usage(String message) {
  stderr.writeln(message);
  stderr.writeln('Usage: dart run tool/command_pass/run.dart [--run r<N>] [batch...]');
  exit(2);
}

List<String> _lines(String path) => File(path).readAsLinesSync().map((l) => l.trim()).where((l) => l.isNotEmpty).toList();

Future<void> main(List<String> args) async {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  if (!Directory(_scenarioDir).existsSync()) _usage('Run from the repo root ($_scenarioDir not found).');
  final root = Directory(Platform.environment['BASA_PASS_DIR'] ?? r'D:\0_CAPSTONE\verify\pass');
  root.createSync(recursive: true);

  // Arguments.
  int? reuse;
  final batches = <String>[];
  for (var i = 0; i < args.length; i++) {
    if (args[i] == '--run') {
      if (i + 1 >= args.length) _usage('--run needs r<N>.');
      final m = RegExp(r'^r(\d+)$').firstMatch(args[++i]);
      if (m == null) _usage('--run needs r<N>, got "${args[i]}".');
      reuse = int.parse(m.group(1)!);
    } else {
      batches.add(args[i]);
    }
  }

  // Scenarios: NN_<batch>.pass, in file-name order.
  final files = Directory(_scenarioDir).listSync().whereType<File>().where((f) => f.path.endsWith('.pass')).toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  String batchOf(File f) {
    final name = f.uri.pathSegments.last.replaceAll('.pass', '');
    final us = name.indexOf('_');
    return us < 0 ? name : name.substring(us + 1);
  }

  final known = files.map(batchOf).toSet();
  final unknown = batches.where((b) => !known.contains(b)).toList();
  if (unknown.isNotEmpty) _usage('Unknown batch: ${unknown.join(', ')} (known: ${known.join(', ')}).');
  final chosen = batches.isEmpty ? files : files.where((f) => batches.contains(batchOf(f))).toList();
  final List<Scenario> scenarios;
  try {
    scenarios = [for (final f in chosen) parseScenario(batchOf(f), f.readAsStringSync())];
  } on FormatException catch (e) {
    _usage('Scenario error: ${e.message}');
  }

  // Run folder.
  final int n;
  if (reuse != null) {
    n = reuse;
    if (!Directory('${root.path}/r$n').existsSync()) _usage('No run r$n in ${root.path}.');
  } else {
    final counter = File('${root.path}/next_run.txt');
    n = counter.existsSync() ? int.parse(counter.readAsStringSync().trim()) : 1;
    counter.writeAsStringSync('${n + 1}');
  }
  final runDir = Directory('${root.path}/r$n')..createSync(recursive: true);

  // Accounts.
  ({String email, String password})? superAccount;
  final accountsFile = File('${root.path}/accounts.json');
  if (accountsFile.existsSync()) {
    final s = (jsonDecode(accountsFile.readAsStringSync()) as Map)['super'];
    if (s is Map) superAccount = (email: '${s['email']}', password: '${s['password']}');
  }

  final state = await RunState.load(runDir);
  final accounts = Accounts(runNumber: n, superAccount: superAccount, state: state, superFile: accountsFile);
  final devices = DeviceManager(runDir, configSource: _configSource);
  final readOnly = loadReadOnlyCommands();

  stdout.writeln('Run r$n: ${scenarios.map((s) => s.batch).join(', ')}');
  final results = <StepResult>[];
  for (final s in scenarios) {
    final r = await runScenario(s, devices, state, accounts, readOnlyCommands: readOnly);
    results.addAll(r);
    stdout.writeln('  ${s.batch}: ${summaryLine(r, null)}');
  }
  await devices.close();

  // Coverage only on a full run (plan D4).
  final cov = batches.isEmpty
      ? computeCoverage(scenarios,
          tutorCommands: _lines('test/core/wiring/tutor_commands.txt'),
          adminCommands: _lines('test/core/wiring/admin_commands.txt'))
      : null;
  final report = File('${runDir.path}/report.md');
  report.writeAsStringSync(renderReport(results, cov, accounts.secrets));

  final failed = results.any(isFailed); // same rule as the report (review P2)
  final uncovered = cov != null && (cov.uncoveredTutor.isNotEmpty || cov.uncoveredAdmin.isNotEmpty);
  stdout.writeln(summaryLine(results, cov));
  stdout.writeln('Report: ${report.path}');
  exit(failed || uncovered ? 1 : 0); // the Supabase client can keep the process alive otherwise
}
