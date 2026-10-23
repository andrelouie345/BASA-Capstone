// Scenario files of the command pass (spec
// docs/superpowers/specs/2026-10-23-command-pass-design.md, *Scenario format*).
// One step per line: the first word is the keyword, the rest its argument.

sealed class Step {
  final int line;
  const Step(this.line);
}

/// `device <name> tutor|admin`: switch to (or create) a device of that build.
class DeviceStep extends Step {
  final String name;
  final String build;
  const DeviceStep(super.line, this.name, this.build);
}

/// `as <account>`: sign out, then sign in as that account.
class AsStep extends Step {
  final String account;
  const AsStep(super.line, this.account);
}

/// `run <command line>`, or `other-school run ...` for a deliberate
/// read-only step against another school.
class RunStep extends Step {
  final String commandLine;
  final bool otherSchool;
  const RunStep(super.line, this.commandLine, {this.otherSchool = false});
}

/// `expect <text>`: the last run's output contains the text.
class ExpectStep extends Step {
  final String text;
  const ExpectStep(super.line, this.text);
}

/// `expect~ <regex>`: the last run's output matches the regex.
class ExpectRegexStep extends Step {
  final RegExp pattern;
  const ExpectRegexStep(super.line, this.pattern);
}

/// `refuse <text>`: the last run was refused with that text.
class RefuseStep extends Step {
  final String text;
  const RefuseStep(super.line, this.text);
}

/// `capture <name> = <regex>`: store group 1 of the match.
class CaptureStep extends Step {
  final String name;
  final RegExp pattern;
  const CaptureStep(super.line, this.name, this.pattern);
}

/// `sql <query> => <value>`: read-only query on the current device; the first
/// column of the first row must equal the value.
class SqlStep extends Step {
  final String query;
  final String expected;
  const SqlStep(super.line, this.query, this.expected);
}

class Scenario {
  final String batch;
  final List<Step> steps;
  const Scenario(this.batch, this.steps);
}

/// Parses a scenario. Throws a [FormatException] whose message starts with
/// `<batch>:<line>:`.
Scenario parseScenario(String batch, String source) {
  final steps = <Step>[];
  // Checks belong to the last `run`; a device or account switch ends it.
  var afterRun = false;
  final lines = source.split('\n');
  for (var i = 0; i < lines.length; i++) {
    final n = i + 1;
    final text = lines[i].replaceAll('\r', '').trim();
    if (text.isEmpty || text.startsWith('#')) continue;
    Never fail(String reason) => throw FormatException('$batch:$n: $reason');

    final space = text.indexOf(' ');
    final keyword = space < 0 ? text : text.substring(0, space);
    final rest = space < 0 ? '' : text.substring(space + 1).trim();
    RegExp regex(String source) {
      try {
        return RegExp(source);
      } on FormatException catch (e) {
        fail('bad regex "$source": ${e.message}');
      }
    }

    void requireRun() {
      if (!afterRun) fail('"$keyword" must follow a run step');
    }

    switch (keyword) {
      case 'device':
        final parts = rest.split(RegExp(r'\s+'));
        if (parts.length != 2 || !const {'tutor', 'admin'}.contains(parts[1])) {
          fail('expected "device <name> tutor|admin"');
        }
        steps.add(DeviceStep(n, parts[0], parts[1]));
        afterRun = false;
      case 'as':
        if (rest.isEmpty || rest.contains(' ')) fail('expected "as <account>"');
        steps.add(AsStep(n, rest));
        afterRun = false;
      case 'run':
        if (rest.isEmpty) fail('run needs a command line');
        steps.add(RunStep(n, rest));
        afterRun = true;
      case 'other-school':
        if (!rest.startsWith('run ') || rest.length <= 4) fail('expected "other-school run <command line>"');
        steps.add(RunStep(n, rest.substring(4).trim(), otherSchool: true));
        afterRun = true;
      case 'expect':
        requireRun();
        if (rest.isEmpty) fail('expect needs a text');
        steps.add(ExpectStep(n, rest));
      case 'expect~':
        requireRun();
        if (rest.isEmpty) fail('expect~ needs a regex');
        steps.add(ExpectRegexStep(n, regex(rest)));
      case 'refuse':
        requireRun();
        if (rest.isEmpty) fail('refuse needs a text');
        steps.add(RefuseStep(n, rest));
      case 'capture':
        requireRun();
        final eq = rest.indexOf(' = ');
        if (eq <= 0) fail('expected "capture <name> = <regex>"');
        final name = rest.substring(0, eq).trim();
        if (!RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(name)) fail('bad capture name "$name"');
        steps.add(CaptureStep(n, name, regex(rest.substring(eq + 3).trim())));
      case 'sql':
        requireRun();
        final arrow = rest.lastIndexOf(' => ');
        if (arrow <= 0) fail('expected "sql <query> => <value>"');
        steps.add(SqlStep(n, rest.substring(0, arrow).trim(), rest.substring(arrow + 4).trim()));
      default:
        fail('unknown keyword "$keyword"');
    }
  }
  return Scenario(batch, steps);
}
