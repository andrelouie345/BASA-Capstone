// Runner of the command pass (tool/command_pass/runner.dart, device.dart,
// report.dart). Offline only: no step signs in online.
import 'dart:io';

import 'package:basa_capstone/core/console/console_command.dart';
import 'package:basa_capstone/viewmodels/viewmodel_exception.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../tool/command_pass/checks.dart' show StepOutcome;
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

  test('device ... fresh starts the device from an empty folder on every invocation', () async {
    const s = 'device a tutor fresh\nrun sign-in-offline zz.fresh@basa.test x\nrefuse not set up\n'
        "sql select count(*) from login_logs where email_attempted = 'zz.fresh@basa.test' => 1";
    final first = await run(s);
    expect(first.every((r) => r.outcome.passed), isTrue, reason: first.map((r) => r.outcome.message).join('; '));
    final second = await run('device b tutor\nrun help\nexpect x\n$s'); // switch away, then back
    expect(second.skip(3).every((r) => r.outcome.passed), isTrue,
        reason: second.map((r) => r.outcome.message).join('; '));
  });

  test('a fresh device keeps its data while the scenario stays on it', () async {
    final r = await run('device a tutor fresh\nrun sign-in-offline zz.keep@basa.test x\nrefuse not set up\n'
        'device b tutor\nrun help\nexpect x\n'
        'device a tutor\nrun help\n'
        "sql select count(*) from login_logs where email_attempted = 'zz.keep@basa.test' => 1");
    expect(r.last.outcome.passed, isTrue, reason: r.last.outcome.message);
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

  test('report shows the first output line under a passed refuse step', () async {
    final results = await run('device a tutor\nrun set-text\nrefuse Usage:');
    final report = renderReport(results, null, const []);
    expect(report, contains('- PASS L3 `refuse Usage:`\n  > Usage: set-text <value>\n'));
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

  test('a failed sign-in after a device switch counts as a failure (R1)', () {
    final step = parseScenario('t', 'device a tutor').steps.single;
    final results = [
      StepResult('t', step, const StepOutcome(true)),
      StepResult('t', step, const StepOutcome(true), setup: true),
      StepResult('t', step, const StepOutcome(false, 'sign-in as tutor1 failed'), setup: true),
    ];
    expect(summaryLine(results, null), '2 steps, 1 failed');
  });

  test('built-in values fill run lines, expect texts and capture patterns', () async {
    String d(DateTime t) => t.toIso8601String().substring(0, 10);
    final now = DateTime.now();
    final year = now.month >= 6 ? '${now.year}-${now.year + 1}' : '${now.year - 1}-${now.year}';
    final results = await run('device a tutor\n'
        'run set-text r{run} {year} {code_a} {code_b} {name_a}|{name_b} {today} {past} {future}\n'
        'expect OK: "r{run} {year} {code_a} {code_b} {name_a}|{name_b} {today} {past} {future}"\n'
        'capture past = r{run} .* {today} (\\S+)\n'
        'run get-text\n'
        'refuse {missing}');
    expect(results[1].output.split('\n').first,
        'OK: "r1 $year ZZPASS0001 ZZPASS0001B ZZTEST PASS r1|ZZTEST PASS r1 B ${d(now)} ${d(now.subtract(const Duration(days: 30)))} ${d(now.add(const Duration(days: 30)))}"');
    expect(results[2].outcome.passed, isTrue, reason: results[2].outcome.message);
    expect(results[3].outcome.passed, isTrue, reason: results[3].outcome.message);
    expect(state.captures['past'], d(now.subtract(const Duration(days: 30))));
    expect(results[5].outcome.passed, isFalse);
    expect(results[5].outcome.message, contains('missing'));
  });

  test('{stamp} is fixed for one invocation and looks like HHmmss', () async {
    final results = await run('device a tutor\nrun set-text {stamp}\ncapture s1 = OK: "(\\d+)"\nrun set-text {stamp}\nexpect OK: "{s1}"');
    expect(results.every((r) => r.outcome.passed), isTrue, reason: results.map((r) => r.outcome.message).join('; '));
    expect(state.captures['s1'], matches(RegExp(r'^\d{6}$')));
  });

  test('{rundir} is the run folder, for files a command writes', () async {
    final results = await run('device a tutor\nrun set-text {rundir}\nexpect {rundir}');
    expect(results[1].output.split('\n').first, 'OK: "${runDir.path}"');
    expect(results[2].outcome.passed, isTrue);
  });

  test('run accounts have {email_<name>} and, once known, {pw_<name>}', () async {
    state.passwords['tutor1'] = 'Zz9!secretpw';
    final results = await run('device a tutor\nrun set-text {email_tutor1} {pw_tutor1}\n'
        'expect OK: "zztest.pass.r1.tutor1@basa.test Zz9!secretpw"\nrun set-text {pw_tutor2}\nexpect x');
    expect(results[2].outcome.passed, isTrue, reason: results[2].outcome.message);
    expect(results[3].outcome.passed, isFalse);
    expect(results[3].outcome.message, contains('pw_tutor2'));
    expect(renderReport(results, null, accounts.secrets), isNot(contains('Zz9!secretpw')));
  });

  test('a changed superadmin password is written back to the shared accounts file', () async {
    final file = File('${runDir.path}/root_accounts.json')
      ..writeAsStringSync('{"super": {"email": "zztest.super@basa.test", "password": "temp123"}}');
    final a = Accounts(
        runNumber: 1,
        superAccount: (email: 'zztest.super@basa.test', password: 'temp123'),
        state: state,
        superFile: file);
    await a.storeSuperPassword('Zz9!newpass');
    expect(file.readAsStringSync(), contains('"password": "Zz9!newpass"'));
    expect(file.readAsStringSync(), contains('zztest.super@basa.test'));
    expect(a.resolve('super').password, 'Zz9!newpass');
    expect(a.secrets, contains('Zz9!newpass'));
  });
}
