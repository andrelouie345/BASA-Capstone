// lib/core/console/commands/aral_irip_commands.dart

/// Commands for the ARAL-Reading IRIP (local, offline-first). One action per
/// command; the ViewModel does the checks. Learners are named by their ARAL
/// enrollment id (the #id of aral-roster); weeks by the #id aral-irip shows.
library;

import '../console_command.dart';
import '../console_registry.dart';
import '../date_args.dart';
import '../../../viewmodels/aral_irip_viewmodel.dart';
import '../../models/aral_irip.dart';

class _Usage implements Exception {
  final String message;
  const _Usage(this.message);
}

int _int(String raw, String what) =>
    int.tryParse(raw) ?? (throw _Usage('Invalid $what: "$raw" (expected a number)'));

AralIripStatus? _status(String raw) => AralIripStatus.values.where((s) => s.value == raw || s.name == raw).firstOrNull;

AralIripProgram? _program(String raw) => switch (raw) {
      'basic' || 'basic_ks23' => AralIripProgram.basicKs23,
      'plus_ks2' || 'ks2' => AralIripProgram.plusKs2,
      'plus_ks3' || 'ks3' => AralIripProgram.plusKs3,
      _ => null,
    };

/// A YYYY-MM-DD token; one that isn't a real date is refused (F22).
bool _isDate(String a) {
  if (!looksLikeDateArg(a)) return false;
  if (strictDateArg(a) == null) throw _Usage(notARealDateMessage(a));
  return true;
}

String _targetText(AralIripTarget t) {
  if (t.program == AralIripProgram.basicKs23) {
    return '#${t.id} ${t.strand.label} ${t.seq}: ${t.focus} | letters: ${t.letterFocus} | sight words: ${t.sightWords}';
  }
  return '#${t.id} Target ${t.seq}: ${t.skillList.join('; ')}';
}

String _week(AralIripWeek w, Map<int, AralIripTarget> targets) {
  final t = targets[w.targetId];
  final status = w.status == null ? '(not rated)' : '${w.status!.symbol} ${w.status!.value} ${w.ratedOn}';
  return '  week ${w.weekNo}${w.strand == AralIripStrand.main ? '' : ' ${w.strand.label}'} (#${w.id}) | '
      '${t?.label ?? 'target ${w.targetId}'} | $status${w.notes == null ? '' : ' | ${w.notes}'}';
}

void registerAralIripCommands(ConsoleRegistry registry, AralIripViewModel vm) {
  void add(String name, String description, Future<String> Function(List<String> args) handler) {
    registry.register(ConsoleCommand(
      name: name,
      description: description,
      handler: (args) async {
        try {
          return await handler(args);
        } on _Usage catch (e) {
          return e.message;
        } catch (e) {
          return '$name failed: $e';
        }
      },
    ));
  }

  add('aral-irip-targets', 'aral-irip-targets <basic|plus_ks2|plus_ks3> — an IRIP target list (with target ids)',
      (args) async {
    const usage = 'Usage: aral-irip-targets <basic|plus_ks2|plus_ks3>';
    if (args.isEmpty) throw const _Usage(usage);
    final program = _program(args[0]) ?? (throw const _Usage(usage));
    final list = await vm.targets(program);
    if (list.isEmpty) return 'No ${program.label} targets locally (pull-cloud brings them).';
    return '${program.label}:\n${list.map(_targetText).join('\n')}';
  });

  add('aral-irip', 'aral-irip <enrollmentId> — a learner\'s IRIP: every week, and what comes next', (args) async {
    if (args.isEmpty) throw const _Usage('Usage: aral-irip <enrollmentId>');
    final p = await vm.plan(_int(args[0], 'enrollmentId'));
    final head = 'ARAL #${p.enrollment.id} (student ${p.enrollment.studentId}) | ${p.enrollment.programLabel} | '
        '${p.program == null ? 'no IRIP for this program' : 'IRIP ${p.program!.label}'}';
    if (!p.hasIrip && !p.started) return head;
    final lines = <String>[head];
    for (var c = 1; c <= p.currentCycle; c++) {
      lines.add('Cycle $c:');
      lines.addAll(p.weeks.where((w) => w.cycleNo == c).map((w) => _week(w, p.targetById)));
    }
    if (!p.started) {
      lines.add('Not started: aral-irip-start ${p.enrollment.id}');
    } else if (p.programChanged) {
      lines.add('The learner moved to ${p.enrollment.programLabel}: start a new cycle (aral-irip-start).');
    } else if (p.cycleDone) {
      lines.add('Cycle ${p.currentCycle} done: aral-irip-start ${p.enrollment.id} starts cycle ${p.currentCycle + 1}.');
    } else {
      for (final s in p.strands) {
        final name = s.strand == AralIripStrand.main ? 'Next' : '${s.strand.label} next';
        if (s.awaitingRating) {
          lines.add('$name: rate week ${s.latest!.weekNo} (#${s.latest!.id}) first');
        } else if (s.listDone) {
          lines.add('$name: every target observed; pick one to review (aral-irip-next ... target=<id>)');
        } else if (s.suggestion != null) {
          lines.add('$name: week ${s.latest!.weekNo + 1} suggested ${s.suggestion!.label}');
        }
      }
    }
    return lines.join('\n');
  });

  add('aral-irip-start', 'aral-irip-start <enrollmentId> — start the IRIP (week 1) or its next 8-week cycle',
      (args) async {
    if (args.isEmpty) throw const _Usage('Usage: aral-irip-start <enrollmentId>');
    final weeks = await vm.startCycle(_int(args[0], 'enrollmentId'));
    final p = await vm.plan(weeks.first.enrollmentId);
    return 'Cycle ${weeks.first.cycleNo} started:\n${weeks.map((w) => _week(w, p.targetById)).join('\n')}';
  });

  add('aral-irip-rate',
      'aral-irip-rate <weekId> <observed|partial|not_observed> [YYYY-MM-DD] ["notes"] — rate a week '
          '(date defaults to today; rating again replaces it)', (args) async {
    const usage = 'Usage: aral-irip-rate <weekId> <observed|partial|not_observed> [YYYY-MM-DD] ["notes"]';
    if (args.length < 2) throw const _Usage(usage);
    final status = _status(args[1]) ?? (throw const _Usage(usage));
    var rest = args.sublist(2);
    DateTime? on;
    if (rest.isNotEmpty && _isDate(rest.first)) {
      on = DateTime.parse(rest.first);
      rest = rest.sublist(1);
    }
    final w = await vm.rate(_int(args[0], 'weekId'), status, on: on, notes: rest.isEmpty ? null : rest.join(' '));
    return 'Week ${w.weekNo} (#${w.id}): ${w.status!.symbol} ${w.status!.meaning}.';
  });

  add('aral-irip-next',
      'aral-irip-next <enrollmentId> [filipino|english] [target=<targetId>] — add the next week with the suggested '
          'target (or the one given)', (args) async {
    const usage = 'Usage: aral-irip-next <enrollmentId> [filipino|english] [target=<targetId>]';
    if (args.isEmpty) throw const _Usage(usage);
    AralIripStrand? strand;
    int? target;
    for (final a in args.skip(1)) {
      if (a == 'filipino' || a == 'english') {
        strand = AralIripStrand.fromString(a);
      } else if (a.startsWith('target=')) {
        target = _int(a.substring(7), 'targetId');
      } else {
        throw _Usage('Unknown option "$a".\n$usage');
      }
    }
    final weeks = await vm.nextWeek(_int(args[0], 'enrollmentId'), strand: strand, targetId: target);
    final p = await vm.plan(weeks.first.enrollmentId);
    return 'Added:\n${weeks.map((w) => _week(w, p.targetById)).join('\n')}';
  });

  add('aral-irip-target', 'aral-irip-target <weekId> <targetId> — pick another target for a week not rated yet',
      (args) async {
    if (args.length < 2) throw const _Usage('Usage: aral-irip-target <weekId> <targetId>');
    final w = await vm.changeTarget(_int(args[0], 'weekId'), _int(args[1], 'targetId'));
    final p = await vm.plan(w.enrollmentId);
    return 'Updated:\n${_week(w, p.targetById)}';
  });

  add('aral-irip-notes', 'aral-irip-notes <weekId> <text...|-> — set a week\'s notes ("-" clears them)', (args) async {
    if (args.length < 2) throw const _Usage('Usage: aral-irip-notes <weekId> <text...|->');
    final text = args.sublist(1).join(' ');
    final w = await vm.setNotes(_int(args[0], 'weekId'), text == '-' ? null : text);
    return 'Notes ${w.notes == null ? 'cleared' : 'saved'} for week ${w.weekNo} (#${w.id}).';
  });

  add('aral-irip-unrate', 'aral-irip-unrate <weekId> — remove a rating given by mistake (latest week only)',
      (args) async {
    if (args.isEmpty) throw const _Usage('Usage: aral-irip-unrate <weekId>');
    final w = await vm.clearRating(_int(args[0], 'weekId'));
    return 'Week ${w.weekNo} (#${w.id}) is not rated now.';
  });

  add('aral-irip-delete', 'aral-irip-delete <weekId> — delete a week added by mistake (latest week only)',
      (args) async {
    if (args.isEmpty) throw const _Usage('Usage: aral-irip-delete <weekId>');
    await vm.deleteWeek(_int(args[0], 'weekId'));
    return 'Deleted IRIP week ${args[0]}.';
  });
}
