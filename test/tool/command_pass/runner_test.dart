// Runner of the command pass (tool/command_pass/runner.dart, device.dart,
// report.dart). Offline only: no step signs in online.
import 'dart:io';

import 'package:basa_capstone/core/console/console_command.dart';
import 'package:basa_capstone/viewmodels/viewmodel_exception.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../tool/command_pass/coverage.dart';
import '../../../tool/command_pass/device.dart';
import '../../../tool/command_pass/report.dart';
import '../../../tool/command_pass/runner.dart';
import '../../../tool/command_pass/scenario.dart';

void main() {
  late Directory runDir;
  late DeviceManager devices;
  late RunState state;
  late Accounts accounts;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    runDir = Directory.systemTemp.createTempSync('basa_pass_');
    devices = DeviceManager(runDir);
    state = await RunState.load(runDir);
    accounts = Accounts(runNumber: 1, superAccount: null, state: state);
  });

  tearDown(() async {
    await devices.close();
  });

  Future<List<StepResult>> run(String source) =>
      runScenario(parseScenario('t', source), devices, state, accounts, readOnlyCommands: const {'help'});

  test('self-test scenario: separate databases per device, kept across switches', () async {
    final source = File('tool/command_pass/scenarios/00_selftest.pass').readAsStringSync();
    final results = await runScenario(parseScenario('selftest', source), devices, state, accounts,
        readOnlyCommands: const {'help'});
    final failed = results.where((r) => !r.outcome.passed).toList();
    expect(failed.map((r) => 'line ${r.step.line}: ${r.outcome.message}\n${r.output}'), isEmpty);
    expect(results, hasLength(20));
  });

  test('an unknown command fails the run and skips its checks', () async {
    final results = await run('device a tutor\nrun no-such-cmd\nexpect x');
    expect(results[1].outcome.passed, isFalse);
    expect(results[1].outcome.message, contains('unknown command'));
    expect(results[2].skipped, isTrue);
  });

  test('a run before any device fails', () async {
    final results = await run('run help\nexpect x');
    expect(results[0].outcome.passed, isFalse);
    expect(results[0].outcome.message, contains('no device'));
  });

  test('a crash fails the step with its type; a ViewModelException is a refusal', () async {
    final device = await devices.switchTo('a', 'tutor');
    device.ctx.registry.register(ConsoleCommand(
        name: 'zz-crash', description: 'test', handler: (_) async => throw StateError('boom')));
    device.ctx.registry.register(ConsoleCommand(
        name: 'zz-refuse', description: 'test', handler: (_) async => throw const ViewModelException('Forbidden: x')));
    final results = await run('device a tutor\nrun zz-crash\nexpect boom\nrun zz-refuse\nrefuse Forbidden');
    expect(results[1].outcome.passed, isFalse);
    expect(results[1].outcome.message, contains('StateError'));
    expect(results[2].skipped, isTrue);
    expect(results[3].outcome.passed, isTrue);
    expect(results[4].outcome.passed, isTrue);
  });

  test('a capture that matches nothing fails the step', () async {
    final results = await run('device a tutor\nrun get-text\ncapture id = id (\\d+)');
    expect(results[2].outcome.passed, isFalse);
  });

  test('a missing capture fails the run', () async {
    final results = await run('device a tutor\nrun set-text {nope}\nexpect OK');
    expect(results[1].outcome.passed, isFalse);
    expect(results[1].outcome.message, contains('nope'));
  });

  test('the id guard refuses other-school on a write command', () async {
    final results = await run('device a tutor\nother-school run set-text 6\nexpect OK');
    expect(results[1].outcome.passed, isFalse);
    expect(results[1].outcome.message, contains('read-only'));
  });

  test('captures survive into a second invocation on the same run folder', () async {
    await run('device a tutor\nrun set-text id 5\ncapture x = id (\\d+)');
    await devices.close();

    final devices2 = DeviceManager(runDir);
    final state2 = await RunState.load(runDir);
    final results = await runScenario(parseScenario('t', 'device a tutor\nrun set-text v{x}\nexpect OK: "v5"'), devices2,
        state2, Accounts(runNumber: 1, superAccount: null, state: state2),
        readOnlyCommands: const {});
    await devices2.close();
    expect(results.every((r) => r.outcome.passed), isTrue);
  });

  test('a sql step must be a select', () async {
    final results = await run('device a tutor\nrun help\nsql delete from login_logs => 0');
    expect(results[2].outcome.passed, isFalse);
  });

  test('report marks steps, masks secrets and ends with the summary line', () async {
    final results = await run('device a tutor\nrun set-text hunter2\nexpect OK\nrun get-text\nexpect nothing-here');
    final report = renderReport(results, null, const ['hunter2']);
    expect(report, contains('PASS'));
    expect(report, contains('FAIL'));
    expect(report, isNot(contains('hunter2')));
    expect(summaryLine(results, null), '5 steps, 1 failed');

    const cov = CoverageResult(
        uncoveredTutor: ['whoami'],
        uncoveredAdmin: [],
        coveredTutor: 114,
        totalTutor: 115,
        coveredAdmin: 228,
        totalAdmin: 228);
    expect(summaryLine(results, cov), '342/343 covered, 5 steps, 1 failed');
    expect(renderReport(results, cov, const []), contains('UNCOVERED (tutor): whoami'));
  });
}
