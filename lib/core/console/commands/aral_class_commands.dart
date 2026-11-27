// lib/core/console/commands/aral_class_commands.dart

/// ARAL classes, both builds: read the classes (a tutor sees the classes they
/// teach). One action per command; the ViewModel does the checks. Changing
/// classes is in aral_class_admin_commands.dart (admin build).
library;

import '../console_command.dart';
import '../console_registry.dart';
import '../date_args.dart';
import '../../models/aral_progress.dart';
import '../../../viewmodels/aral_class_viewmodel.dart';
import '../../../viewmodels/aral_viewmodel.dart';
import 'aral_command_helpers.dart';

void registerAralClassCommands(ConsoleRegistry registry, AralClassViewModel vm, AralViewModel aral) {
  void add(String name, String description, Future<String> Function(List<String> args) handler) {
    registry.register(ConsoleCommand(
      name: name,
      description: description,
      handler: (args) async {
        try {
          return await handler(args);
        } on AralUsage catch (e) {
          return e.message;
        } catch (e) {
          return '$name failed: $e';
        }
      },
    ));
  }

  add('aral-classes', 'aral-classes <schoolId> <schoolYear> — the school\'s ARAL classes (a tutor: their own)',
      (args) async {
    if (args.length != 2) throw const AralUsage('Usage: aral-classes <schoolId> <schoolYear>');
    final list = await vm.classes(schoolId: aralInt(args[0], 'schoolId'), schoolYear: args[1]);
    if (list.isEmpty) return 'No ARAL classes for that school and year on this device.';
    return [for (final c in list) aralClassLine(c, cap: await vm.classMax(c.schoolId), active: await vm.activeCount(c.id!))].join('\n');
  });

  add('aral-class-show', 'aral-class-show <classId> — one ARAL class and its learners', (args) async {
    if (args.length != 1) throw const AralUsage('Usage: aral-class-show <classId>');
    final c = await vm.getClass(aralInt(args[0], 'classId'));
    final learners = await vm.classRoster(c.id!);
    final names = <int, String>{};
    for (final section in learners.map((e) => e.sectionId).toSet()) {
      names.addAll(await aral.learnerNames(section));
    }
    return [
      aralClassLine(c, cap: await vm.classMax(c.schoolId), active: learners.where((e) => e.isActive).length),
      'school ${c.schoolId}, ${c.schoolYear}',
      if (c.notes != null) 'notes: ${c.notes}',
      for (final e in learners) '  ${aralLine(e, names, {c.id!: c.className})}',
      if (learners.isEmpty) '  (no learners yet)',
    ].join('\n');
  });

  add('aral-class-progress',
      'aral-class-progress <classId> [asof=YYYY-MM-DD] — each learner\'s change since their ARAL starting round '
          '(up / same / down by reading profile, with the numbers)', (args) async {
    const usage = 'Usage: aral-class-progress <classId> [asof=YYYY-MM-DD]';
    if (args.isEmpty || args.length > 2 || (args.length == 2 && !args[1].startsWith('asof='))) {
      throw const AralUsage(usage);
    }
    String? asOf;
    if (args.length == 2) {
      final raw = args[1].substring(5);
      if (strictDateArg(raw) == null) throw AralUsage(asofDateMessage(raw));
      asOf = raw.trim();
    }
    final id = aralInt(args[0], 'classId');
    final c = await vm.getClass(id);
    final rows = await vm.classProgress(id, asOf: asOf);
    return [
      '${c.className}: ${rows.length} learner${rows.length == 1 ? '' : 's'}',
      for (final p in rows) _progressLine(p),
    ].join('\n');
  });

  add('aral-no-improvement',
      'aral-no-improvement <classId> [asof=YYYY-MM-DD] — the class\'s learners with no improvement '
          '(same or down since their ARAL start after enough sessions, or a failed check-in), with the reasons',
      (args) async {
    const usage = 'Usage: aral-no-improvement <classId> [asof=YYYY-MM-DD]';
    if (args.isEmpty || args.length > 2 || (args.length == 2 && !args[1].startsWith('asof='))) {
      throw const AralUsage(usage);
    }
    String? asOf;
    if (args.length == 2) {
      final raw = args[1].substring(5);
      if (strictDateArg(raw) == null) throw AralUsage(asofDateMessage(raw));
      asOf = raw.trim();
    }
    final id = aralInt(args[0], 'classId');
    final c = await vm.getClass(id);
    final rows = await vm.noImprovement(id, asOf: asOf);
    return [
      '${c.className}: ${rows.length} learner${rows.length == 1 ? '' : 's'} with no improvement',
      for (final f in rows) f.toString(),
    ].join('\n');
  });
}

/// "CRUZ, Ana | Grade 2 CRLA | BOSY Low Emerging Reader -> MOSY Developing Reader | Up | wpm 40 -> 62".
String _progressLine(AralLearnerProgress p) {
  final latest = p.latestRound == null ? '-' : '${p.latestRoundLabel} ${p.latestProfile ?? '-'}';
  final pct = p.instrument == AralLearnerProgress.philIri;
  String? pair(String what, double? a, double? b, {bool percent = false}) {
    if (a == null && b == null) return null;
    String f(double? v) => v == null ? '-' : '${v.round()}${percent ? '%' : ''}';
    return '$what ${f(a)} -> ${f(b)}';
  }

  final numbers = [
    pair(pct ? 'word recognition' : 'correct words', p.startNumbers?.correctWordsPct, p.latestNumbers?.correctWordsPct,
        percent: true),
    pair('wpm', p.startNumbers?.wpm, p.latestNumbers?.wpm),
    pair('comprehension', p.startNumbers?.comprehension, p.latestNumbers?.comprehension, percent: pct),
  ].whereType<String>();
  return [
    p.learnerName,
    'Grade ${p.grade} ${p.instrument}',
    '${p.startRoundLabel} ${p.startProfile ?? '-'} -> $latest',
    p.change.label,
    if (p.exited) 'left ARAL ${p.enrollment.exitedOn}',
    if (numbers.isNotEmpty) numbers.join(', '),
  ].join(' | ');
}
