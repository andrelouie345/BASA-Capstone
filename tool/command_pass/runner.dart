// Executes a scenario on the devices of a run (plan Task 4, D1-D3).
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:basa_capstone/core/console/console_registry.dart';
import 'package:basa_capstone/core/console/console_session.dart';
import 'package:basa_capstone/viewmodels/viewmodel_exception.dart';

import 'package:basa_capstone/core/services/sf1_column_map.dart';

import 'checks.dart';
import 'device.dart';
import 'scenario.dart';
import 'sf1_fixture.dart';

/// Captures and the run accounts' passwords, saved after every change so an
/// interrupted run can be resumed with `--run r<N>`.
class RunState {
  final Directory runDir;
  final Map<String, String> captures;
  final Map<String, String> passwords;
  /// HHmmss when this invocation loaded the run: {stamp}, for names that must
  /// differ between reruns of a batch.
  final String stamp;
  RunState._(this.runDir, this.captures, this.passwords, this.stamp);

  static Future<RunState> load(Directory runDir) async {
    Map<String, String> read(String name) {
      final f = File('${runDir.path}/$name');
      if (!f.existsSync()) return {};
      return (jsonDecode(f.readAsStringSync()) as Map).map((k, v) => MapEntry('$k', '$v'));
    }

    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    return RunState._(runDir, read('captures.json'), read('accounts.json'),
        '${two(now.hour)}${two(now.minute)}${two(now.second)}');
  }

  Future<void> save() async {
    const enc = JsonEncoder.withIndent('  ');
    await File('${runDir.path}/captures.json').writeAsString(enc.convert(captures));
    await File('${runDir.path}/accounts.json').writeAsString(enc.convert(passwords));
  }
}

/// Account names used by `as`: `super` (D:\0_CAPSTONE\verify\pass\accounts.json)
/// and the run's own `coord`, `tutor1`, `tutor2` (temporary password from the
/// capture `temp_<name>` until the first sign-in replaces it).
class Accounts {
  static const runAccounts = {'coord', 'tutor1', 'tutor2'};
  final int runNumber;
  ({String email, String password})? superAccount;
  final RunState state;
  /// D:\0_CAPSTONE\verify\pass\accounts.json: gets the superadmin's new
  /// password when the first sign-in replaces a temporary one.
  final File? superFile;
  Accounts({required this.runNumber, required this.superAccount, required this.state, this.superFile});

  Future<void> storeSuperPassword(String password) async {
    final s = superAccount;
    if (s == null) return;
    superAccount = (email: s.email, password: password);
    final f = superFile;
    if (f == null) return;
    final data = f.existsSync() ? jsonDecode(f.readAsStringSync()) as Map<String, dynamic> : <String, dynamic>{};
    data['super'] = {'email': s.email, 'password': password};
    await f.writeAsString(const JsonEncoder.withIndent('  ').convert(data));
  }

  ({String email, String password}) resolve(String name) {
    if (name == 'super') {
      final s = superAccount;
      if (s == null) {
        throw StateError(r'no "super" account: add it to D:\0_CAPSTONE\verify\pass\accounts.json');
      }
      return s;
    }
    if (!runAccounts.contains(name)) throw StateError('unknown account "$name"');
    final password = state.passwords[name] ?? state.captures['temp_$name'];
    if (password == null) throw StateError('no password for "$name" (capture temp_$name first)');
    return (email: emailOf(name), password: password);
  }

  String emailOf(String name) => 'zztest.pass.r$runNumber.$name@basa.test';

  bool isPrivileged(String? account) => account == 'super' || account == 'coord';

  Iterable<String> get secrets => [
        if (superAccount != null) superAccount!.password,
        ...state.passwords.values,
        for (final e in state.captures.entries)
          if (e.key.startsWith('temp_')) e.value,
      ];
}

class StepResult {
  final String batch;
  final Step step;
  final StepOutcome outcome;
  final String output;
  final bool skipped;
  /// A runner action that is not a scenario step (e.g. signing in again
  /// after a device switch). Reported, not counted.
  final bool setup;
  const StepResult(this.batch, this.step, this.outcome,
      {this.output = '', this.skipped = false, this.setup = false});
}

final _random = Random.secure();

String _newPassword() {
  const chars = 'abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  return 'Zz9!${List.generate(16, (_) => chars[_random.nextInt(chars.length)]).join()}';
}

Future<List<StepResult>> runScenario(
  Scenario s,
  DeviceManager devices,
  RunState state,
  Accounts accounts, {
  required Set<String> readOnlyCommands,
}) async {
  final results = <StepResult>[];
  void add(Step step, StepOutcome o, {String output = '', bool skipped = false, bool setup = false}) =>
      results.add(StepResult(s.batch, step, o, output: output, skipped: skipped, setup: setup));

  Device? dev; // a scenario never inherits a device
  CommandOutput? last;
  var lastRunOk = false;

  for (final step in s.steps) {
    switch (step) {
      case DeviceStep():
        lastRunOk = false;
        try {
          dev = await devices.switchTo(step.name, step.build, fresh: step.fresh);
        } catch (e) {
          add(step, StepOutcome(false, 'cannot open device: $e'));
          return results;
        }
        add(step, const StepOutcome(true));
        final again = dev.lastAccount;
        if (again != null && !dev.ctx.authVm.isSignedIn) {
          final r = await _signIn(dev, again, accounts, state);
          add(step, r.$1, output: r.$2, setup: true);
          if (!r.$1.passed) return results;
        }

      case AsStep():
        lastRunOk = false;
        if (dev == null) {
          add(step, const StepOutcome(false, 'no device: start the scenario with a device step'));
          return results;
        }
        final r = await _signIn(dev, step.account, accounts, state);
        add(step, r.$1, output: r.$2);
        if (!r.$1.passed) return results;

      case RunStep():
        lastRunOk = false;
        if (dev == null) {
          add(step, const StepOutcome(false, 'no device: start the scenario with a device step'));
          continue;
        }
        final guard = guardIds(step, privileged: accounts.isPrivileged(dev.lastAccount), readOnlyCommands: readOnlyCommands);
        if (guard != null) {
          add(step, StepOutcome(false, 'id guard: $guard'));
          continue;
        }
        final String line;
        try {
          line = substitute(step.commandLine, _vars(accounts, state));
        } on MissingCaptureException catch (e) {
          add(step, StepOutcome(false, 'missing capture "${e.name}"'));
          continue;
        }
        final tokens = ConsoleRegistry.tokenize(line);
        final command = dev.command(tokens.first);
        if (command == null) {
          add(step, StepOutcome(false, 'unknown command "${tokens.first}" on a ${dev.build} device'));
          continue;
        }
        final session = dev.ctx.session;
        final before = session.entries.length;
        CommandOutput out;
        try {
          out = CommandOutput(await command.handler(tokens.skip(1).toList()));
        } on ViewModelException catch (e) {
          out = CommandOutput(e.message, refused: true);
        } catch (e) {
          out = CommandOutput('$e', crashType: e.runtimeType.toString());
        }
        final logs = session.entries
            .skip(before)
            .where((e) => e.type == ConsoleEntryType.log)
            .map((e) => '[${e.source}] ${e.message}');
        if (logs.isNotEmpty) {
          out = CommandOutput('${out.text}\n${logs.join('\n')}', refused: out.refused, crashType: out.crashType);
        }
        last = out;
        lastRunOk = out.crashType == null;
        add(step, lastRunOk ? const StepOutcome(true) : StepOutcome(false, 'command crashed (${out.crashType})'),
            output: out.text);

      case MakeSf1Step():
        lastRunOk = false;
        if (dev == null) {
          add(step, const StepOutcome(false, 'no device: start the scenario with a device step'));
          continue;
        }
        final path = '${devices.runDir.path}/${step.name}.xlsx';
        try {
          writeSf1(path,
              map: await Sf1ColumnMap.load(dev.dir.path), // what this device's import reads
              schoolCode: sf1SchoolCode(accounts.runNumber, schoolB: step.schoolB),
              schoolName: sf1SchoolName(accounts.runNumber, schoolB: step.schoolB),
              regionLabel: sf1RegionLabel,
              schoolYear: currentSchoolYear(DateTime.now()),
              grade: '${step.grade}',
              section: substitute(step.section, _vars(accounts, state)),
              learners: sf1Learners(
                  runNumber: accounts.runNumber,
                  grade: step.grade,
                  count: step.count,
                  schoolB: step.schoolB,
                  first: step.first));
        } catch (e) {
          add(step, StepOutcome(false, 'cannot write the SF1 workbook: $e'));
          continue;
        }
        state.captures[step.name] = path;
        await state.save();
        add(step, const StepOutcome(true), output: '${step.name} = $path');

      case WriteFileStep():
        lastRunOk = false;
        final path = '${devices.runDir.path}/${step.name}.txt';
        try {
          File(path).writeAsStringSync(substitute(step.text, _vars(accounts, state)));
        } catch (e) {
          add(step, StepOutcome(false, 'cannot write the file: $e'));
          continue;
        }
        state.captures[step.name] = path;
        await state.save();
        add(step, const StepOutcome(true), output: '${step.name} = $path');

      case ExpectStep() || ExpectRegexStep() || RefuseStep() || CaptureStep() || SqlStep():
        final o = last;
        if (!lastRunOk || o == null || dev == null) {
          add(step, const StepOutcome(false, 'skipped: the run before it failed'), skipped: true);
          continue;
        }
        // Checks may use {captures} and the built-in values too.
        String fill(String t) => substitute(t, _vars(accounts, state));
        RegExp fillRegex(RegExp r) => RegExp(fill(r.pattern));
        try {
          switch (step) {
            case ExpectStep():
              add(step, checkExpect(ExpectStep(step.line, fill(step.text)), o), output: o.text);
            case ExpectRegexStep():
              add(step, checkExpectRegex(ExpectRegexStep(step.line, fillRegex(step.pattern)), o), output: o.text);
            case RefuseStep():
              add(step, checkRefuse(RefuseStep(step.line, fill(step.text)), o), output: o.text);
            default:
              break;
          }
        } on MissingCaptureException catch (e) {
          add(step, StepOutcome(false, 'missing capture "${e.name}"'), output: o.text);
          continue;
        } on FormatException catch (e) {
          add(step, StepOutcome(false, 'bad regex after substitution: ${e.message}'), output: o.text);
          continue;
        }
        switch (step) {
          case CaptureStep():
            final CaptureStep filled;
            try {
              filled = CaptureStep(step.line, step.name, fillRegex(step.pattern));
            } on MissingCaptureException catch (e) {
              add(step, StepOutcome(false, 'missing capture "${e.name}"'), output: o.text);
              continue;
            } on FormatException catch (e) {
              add(step, StepOutcome(false, 'bad regex after substitution: ${e.message}'), output: o.text);
              continue;
            }
            final v = capture(filled, o);
            if (v == null) {
              add(step, StepOutcome(false, 'capture "${step.name}": /${step.pattern.pattern}/ matched nothing'),
                  output: o.text);
            } else {
              state.captures[step.name] = v;
              await state.save();
              add(step, const StepOutcome(true), output: '${step.name} = $v');
            }
          case SqlStep():
            final r = await _sql(step, dev, _vars(accounts, state));
            add(step, r.$1, output: r.$2);
          default:
            break;
        }
    }
  }
  return results;
}

/// Returns the outcome and the output to show.
Future<(StepOutcome, String)> _signIn(Device dev, String account, Accounts accounts, RunState state) async {
  final ({String email, String password}) cred;
  try {
    cred = accounts.resolve(account);
  } catch (e) {
    return (StepOutcome(false, '$e'), '');
  }
  if (dev.ctx.authVm.isSignedIn) await dev.command('sign-out')!.handler(const []);
  final out = await dev.command('sign-in')!.handler(['cloud', cred.email, cred.password]);
  if (!out.startsWith('Signed in as')) return (StepOutcome(false, 'sign-in as $account failed'), out);
  var shown = out;
  if (out.contains('(must change password)')) {
    final fresh = _newPassword();
    final changed = await dev.command('change-password')!.handler([fresh]);
    shown = '$out\n$changed';
    if (changed != 'Password changed.') return (StepOutcome(false, 'changing the temporary password failed'), shown);
    if (account == 'super') {
      await accounts.storeSuperPassword(fresh);
    } else {
      state.passwords[account] = fresh;
      await state.save();
    }
  }
  dev.lastAccount = account;
  return (const StepOutcome(true), shown);
}

/// Captures plus the built-in values (which win): {run}, {year}, {code_a},
/// {code_b}, {name_a}, {name_b}, {today}, {past} (today - 30 days), {yesterday},
/// {ago2} / {ago3} (today - 2 / 3 days),
/// {future} (today + 30 days), {rundir}, {stamp}, `{email_<account>}`, `{pw_<account>}`.
Map<String, String> _vars(Accounts accounts, RunState state) {
  final n = accounts.runNumber;
  final now = DateTime.now();
  String day(DateTime d) => d.toIso8601String().substring(0, 10);
  return {
    ...state.captures,
    'run': '$n',
    'year': currentSchoolYear(now),
    'code_a': sf1SchoolCode(n),
    'code_b': sf1SchoolCode(n, schoolB: true),
    'name_a': sf1SchoolName(n),
    'name_b': sf1SchoolName(n, schoolB: true),
    'today': day(now),
    'past': day(now.subtract(const Duration(days: 30))),
    'yesterday': day(now.subtract(const Duration(days: 1))),
    'ago2': day(now.subtract(const Duration(days: 2))),
    'ago3': day(now.subtract(const Duration(days: 3))),
    'future': day(now.add(const Duration(days: 30))),
    'rundir': state.runDir.path,
    'stamp': state.stamp,
    // email_* always; pw_* once the first sign-in set it.
    for (final a in Accounts.runAccounts) 'email_$a': accounts.emailOf(a),
    for (final e in state.passwords.entries) 'pw_${e.key}': e.value,
  };
}

Future<(StepOutcome, String)> _sql(SqlStep step, Device dev, Map<String, String> vars) async {
  final String query;
  try {
    query = substitute(step.query, vars);
  } on MissingCaptureException catch (e) {
    return (StepOutcome(false, 'missing capture "${e.name}"'), '');
  }
  final head = query.trimLeft().toLowerCase();
  if (!(head.startsWith('select') || head.startsWith('with'))) {
    return (const StepOutcome(false, 'sql steps are read-only: start with select or with'), query);
  }
  try {
    final rows = await dev.ctx.localDb.rawQuery(query);
    final value = rows.isEmpty ? '' : '${rows.first.values.first}';
    return (
      value == step.expected ? const StepOutcome(true) : StepOutcome(false, 'expected ${step.expected}, got $value'),
      '$query => $value'
    );
  } catch (e) {
    return (StepOutcome(false, 'sql failed: $e'), query);
  }
}
