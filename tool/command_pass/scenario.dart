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
  /// `device <name> <build> fresh`: start from an empty folder each time the
  /// step runs, so a batch can be rerun on the same run.
  final bool fresh;
  const DeviceStep(super.line, this.name, this.build, {this.fresh = false});
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

/// `make-sf1 <capture> a|b <grade> <section> <count> [from=<n>|from=stamp]`:
/// write an SF1 workbook for school a (the run's school) or b into the run
/// folder and capture its path. `from` is the first learner index (default 1),
/// so a second section of the same grade gets different LRNs; `from=stamp`
/// ([first] 0) takes the run's next unused block of indexes (200 up, kept in
/// the run's state), so a rerun of the batch on the same run gets new
/// learners. `from=last`, `from=last+<k>` or `from=last-<k>` ([lastOffset])
/// starts at the first index of the block the last `from=stamp` took, moved
/// by k, without taking a new block: a later file of the same learners (a
/// re-import that leaves some out, or another section's file that holds
/// some of them). Not a run: checks cannot follow it.
class MakeSf1Step extends Step {
  final String name;
  final bool schoolB;
  final int grade;
  final String section;
  final int count;
  final int first;
  final int? lastOffset;

  /// `as=<grade>`: the learners (LRNs, names) of that grade's block, in a
  /// file whose header says [grade] (a learner of another grade on a
  /// section's SF1); null = [grade].
  final int? learnerGrade;

  /// `lrns=a` (school b only): school a's learners in school b's file (a
  /// same-server transfer, D15); from=stamp / from=last are school a's blocks.
  final bool aLearners;
  const MakeSf1Step(super.line, this.name, this.schoolB, this.grade, this.section, this.count,
      {this.first = 1, this.lastOffset, this.learnerGrade, this.aLearners = false});
}

/// `make-phil-iri-workbook <capture> <grade> <section>[,<section2>] <count> [from=...]` and
/// `make-phil-iri-scoresheet <capture> <grade> <section> <count> [from=...]`:
/// a filled Phil-IRI workbook (ma's layout) or BASA scoresheet file for the
/// school-a learners `make-sf1 ... a <grade> <section> <count> [from=...]`
/// made (same `from`; `from=stamp` = the block the last make-sf1 from=stamp
/// took), contents in phil_iri_fixture.dart. A workbook may name a second
/// section (sheet 03): its learners are the next block of [count], so its
/// make-sf1 comes right after the first one's (with from=stamp: the last
/// make-sf1 made the second section). Not a run.
class MakePhilIriStep extends Step {
  final String name;
  final bool workbook;
  final int grade;
  final String section;
  final String? second;
  final int count;
  final int first;
  const MakePhilIriStep(super.line, this.name, this.workbook, this.grade, this.section, this.count,
      {this.first = 1, this.second});
}

/// `write-file <capture> <text...>`: write the text ({..} values filled in)
/// to `<run folder>/<capture>.txt` and capture its path, e.g. a passage text
/// that must differ on every run. Not a run: checks cannot follow it.
class WriteFileStep extends Step {
  final String name;
  final String text;
  const WriteFileStep(super.line, this.name, this.text);
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

    /// `from=<n>` (n >= 1) or `from=stamp` (0); null when neither.
    int? fromArg(String a) {
      final v = a.substring(5);
      if (v == 'stamp') return 0;
      final n = int.tryParse(v);
      return n != null && n >= 1 ? n : null;
    }

    void requireRun() {
      if (!afterRun) fail('"$keyword" must follow a run step');
    }

    switch (keyword) {
      case 'device':
        final parts = rest.split(RegExp(r'\s+'));
        if (parts.length < 2 ||
            parts.length > 3 ||
            !const {'tutor', 'admin'}.contains(parts[1]) ||
            (parts.length == 3 && parts[2] != 'fresh')) {
          fail('expected "device <name> tutor|admin [fresh]"');
        }
        steps.add(DeviceStep(n, parts[0], parts[1], fresh: parts.length == 3));
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
      case 'make-sf1':
        final all = rest.split(RegExp(r'\s+'));
        // `as=<grade>` (anywhere after the count): the learners of that
        // grade's LRN block in a file of another grade.
        final asArg = all.length > 5 ? all.skip(5).where((t) => t.startsWith('as=')).toList() : const <String>[];
        // `lrns=a` (school b only): school a's learners (their LRNs, from the
        // same block) in school b's file: a same-server transfer (D15).
        final lrnsArg = all.length > 5 ? all.skip(5).where((t) => t.startsWith('lrns=')).toList() : const <String>[];
        final p = [for (final t in all) if (!asArg.contains(t) && !lrnsArg.contains(t)) t];
        final asGrade = asArg.length != 1 ? null : int.tryParse(asArg.single.substring(3));
        final aLearners = lrnsArg.length == 1 && lrnsArg.single == 'lrns=a';
        final shapeOk = (p.length == 5 || (p.length == 6 && p[5].startsWith('from='))) &&
            asArg.length <= 1 &&
            (asArg.isEmpty || asGrade != null) &&
            (lrnsArg.isEmpty || (aLearners && p[1] == 'b'));
        final grade = shapeOk ? int.tryParse(p[2]) : null;
        final count = shapeOk ? int.tryParse(p[4]) : null;
        final last = shapeOk && p.length == 6 ? RegExp(r'^from=last(?:([+-])(\d+))?$').firstMatch(p[5]) : null;
        final lastOffset = last == null ? null : (last[1] == '-' ? -1 : 1) * int.parse(last[2] ?? '0');
        final first = lastOffset != null ? 0 : (shapeOk && p.length == 6 ? fromArg(p[5]) : 1);
        if (!shapeOk || !const {'a', 'b'}.contains(p[1]) || grade == null || count == null || count < 1 ||
            first == null || (first == 0 && p[1] == 'b' && !aLearners)) {
          fail('expected "make-sf1 <capture> a|b <grade> <section> <count> '
              '[from=<n>|from=stamp|from=last[+-<k>]] [as=<grade>] [lrns=a]" (stamp, last: school a\'s '
              'learners: school a, or school b with lrns=a)');
        }
        steps.add(MakeSf1Step(n, p[0], p[1] == 'b', grade, p[3], count,
            first: first, lastOffset: lastOffset, learnerGrade: asGrade, aLearners: aLearners));
        afterRun = false;
      case 'make-phil-iri-workbook' || 'make-phil-iri-scoresheet':
        final p = rest.split(RegExp(r'\s+'));
        final shapeOk = p.length == 4 || (p.length == 5 && p[4].startsWith('from='));
        final grade = shapeOk ? int.tryParse(p[1]) : null;
        final count = shapeOk ? int.tryParse(p[3]) : null;
        final first = shapeOk && p.length == 5 ? fromArg(p[4]) : 1;
        if (!shapeOk || !RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(p[0]) || grade == null || count == null ||
            count < 1 || first == null) {
          fail('expected "$keyword <capture> <grade> <section> <count> [from=<n>|from=stamp]"');
        }
        final workbook = keyword == 'make-phil-iri-workbook';
        final names = p[2].split(',');
        if (names.length > 2 || names.any((x) => x.isEmpty) || (!workbook && names.length > 1)) {
          fail(workbook
              ? 'a workbook names one or two sections: <section>[,<section2>]'
              : 'a scoresheet names one section');
        }
        steps.add(MakePhilIriStep(n, p[0], workbook, grade, names[0], count,
            first: first, second: names.length == 2 ? names[1] : null));
        afterRun = false;
      case 'write-file':
        final sp = rest.indexOf(' ');
        final name = sp < 0 ? '' : rest.substring(0, sp);
        if (!RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(name) || rest.substring(sp + 1).trim().isEmpty) {
          fail('expected "write-file <capture> <text...>"');
        }
        steps.add(WriteFileStep(n, name, rest.substring(sp + 1).trim()));
        afterRun = false;
      default:
        fail('unknown keyword "$keyword"');
    }
  }
  return Scenario(batch, steps);
}
