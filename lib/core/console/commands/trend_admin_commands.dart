// lib/core/console/commands/trend_admin_commands.dart
// Admin build only: the admin half of trend_commands.dart (tutor build split, 2026-10-22).

import '../console_command.dart';
import '../console_registry.dart';
import '../../../viewmodels/nla_report_viewmodel.dart' show NlaSex;
import '../../../viewmodels/trend_viewmodel.dart';
import '../../models/trend_chart.dart';
import 'trend_command_helpers.dart';

void registerTrendAdminCommands(ConsoleRegistry registry, TrendViewModel vm) {
  void add(String name, String description, Future<String> Function(List<String> args) handler) {
    registry.register(ConsoleCommand(
      name: name,
      description: description,
      handler: (args) async {
        try {
          return await handler(args);
        } on TrendUsage catch (e) {
          return e.message;
        } catch (e) {
          return '$name failed: $e';
        }
      },
    ));
  }

  add('trend-bands',
      'trend-bands $_scopeHelp <year> [asof=YYYY-MM-DD] [sex=M|F|T] — learners per Form 2b band per Phil-IRI round',
      (args) async {
    const usage = 'Usage: trend-bands $_scopeHelp <year> [asof=YYYY-MM-DD] [sex=M|F|T]';
    if (args.length < 2) throw const TrendUsage(usage);
    final scope = trendScope(args[0], usage);
    final o = trendParse(args.sublist(2), allowSex: true, usage: usage);
    final c = await vm.bandDistribution(scope, args[1], sex: o.sex ?? NlaSex.total, asOf: o.asOf);
    if (c.xLabels.isEmpty) return '${c.title}\n  No Phil-IRI results yet.';
    return trendTable(c, (v) => '$v', extraRow: ['Total assessed', ..._totals(c)]);
  });

  add('trend-completion',
      'trend-completion $_scopeHelp <year> [asof=YYYY-MM-DD] — % of learners assessed per scheduled Phil-IRI round',
      (args) async {
    const usage = 'Usage: trend-completion $_scopeHelp <year> [asof=YYYY-MM-DD]';
    if (args.length < 2) throw const TrendUsage(usage);
    final scope = trendScope(args[0], usage);
    final o = trendParse(args.sublist(2), allowSex: false, usage: usage);
    final c = await vm.completion(scope, args[1], asOf: o.asOf);
    if (c.series.isEmpty) return '${c.title}\n  No Grade 4-10 sections.';
    if (c.xLabels.isEmpty) return '${c.title}\n  No Phil-IRI round scheduled.';
    final line = c.referenceLine == null
        ? 'Done threshold: differs per school'
        : 'Done threshold: ${c.referenceLine!.toStringAsFixed(1)}%';
    return '${trendTable(c, (v) => v.toStringAsFixed(1))}\n  $line';
  });

  add('trend-crla-profiles',
      'trend-crla-profiles $_scopeHelp <year> [asof=YYYY-MM-DD] [variant=mt|fil|eng] — Grade 1-3 learners per CRLA '
          'reading profile per round',
      (args) async {
    const usage = 'Usage: trend-crla-profiles $_scopeHelp <year> [asof=YYYY-MM-DD] [variant=mt|fil|eng]';
    if (args.length < 2) throw const TrendUsage(usage);
    final scope = trendScope(args[0], usage);
    final o = trendParse(args.sublist(2), allowSex: false, allowVariant: true, usage: usage);
    final c = await vm.crlaProfiles(scope, args[1], variant: o.variant, asOf: o.asOf);
    if (c.xLabels.isEmpty) return '${c.title}\n  No CRLA results yet.';
    return trendTable(c, (v) => '$v', extraRow: ['Total assessed', ..._totals(c)]);
  });

  add('trend-aral-exits',
      'trend-aral-exits $_scopeHelp <year> [asof=YYYY-MM-DD] [sex=M|F|T] — ARAL learners and exits per Phil-IRI '
          'round (Division report)',
      (args) async {
    const usage = 'Usage: trend-aral-exits $_scopeHelp <year> [asof=YYYY-MM-DD] [sex=M|F|T]';
    if (args.length < 2) throw const TrendUsage(usage);
    final scope = trendScope(args[0], usage);
    final o = trendParse(args.sublist(2), allowSex: true, usage: usage);
    final c = await vm.aralExits(scope, args[1], sex: o.sex ?? NlaSex.total, asOf: o.asOf);
    if (c.xLabels.isEmpty) return '${c.title}\n  No Phil-IRI results yet.';
    return trendTable(c, (v) => '$v');
  });
}

const _scopeHelp = '<section:ID|school:ID|region>';

/// Per x label, the sum of every series (a "Total assessed" row).
List<String> _totals(TrendChart c) => [
      for (var i = 0; i < c.xLabels.length; i++) c.series.fold<num>(0, (n, s) => n + (s.values[i] ?? 0)).toString(),
    ];
