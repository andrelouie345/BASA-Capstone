// lib/core/console/commands/trend_commands.dart

/// Dashboard trend charts (D4: Phil-IRI bands and completion; D5: CRLA
/// profiles, ARAL activity and exits), printed as tables: one row per series,
/// one column per x label. Read from this device's copy. `asof=` lets a test
/// look at any day.
library;

import '../console_command.dart';
import '../console_registry.dart';
import '../../../viewmodels/nla_report_viewmodel.dart' show NlaSex;
import '../../../viewmodels/trend_viewmodel.dart';
import '../../models/trend_chart.dart';
import '../../services/calendar_rules.dart';

class _Usage implements Exception {
  final String message;
  const _Usage(this.message);
}

const _scopeHelp = '<section:ID|school:ID|region>';
const _activityScopeHelp = '<tutor:ID|tutor:me|school:ID|region>';

({DateTime? asOf, NlaSex? sex, String? variant}) _parse(List<String> opts,
    {required bool allowSex, bool allowVariant = false, required String usage}) {
  DateTime? asOf;
  NlaSex? sex;
  String? variant;
  for (final o in opts) {
    final eq = o.indexOf('=');
    if (eq < 0) throw _Usage('Options look like key=value (got "$o"). $usage');
    final key = o.substring(0, eq), raw = o.substring(eq + 1).trim();
    switch (key) {
      case 'asof':
        final d = RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(raw) ? DateTime.tryParse(raw) : null;
        // DateTime.parse rolls 2026-02-30 over to March; refuse it instead.
        if (d == null || calendarDate(d) != raw) throw _Usage('asof must be a real YYYY-MM-DD date (got "$raw")');
        asOf = d;
      case 'sex' when allowSex:
        sex = switch (raw.toUpperCase()) {
          'M' => NlaSex.male,
          'F' => NlaSex.female,
          'T' => NlaSex.total,
          _ => throw _Usage('sex is M, F or T (got "$raw")'),
        };
      case 'variant' when allowVariant:
        variant = raw.toLowerCase();
        if (!trendCrlaVariants.contains(variant)) throw _Usage('variant is mt, fil or eng (got "$raw")');
      default:
        throw _Usage('Unknown option "$key". $usage');
    }
  }
  return (asOf: asOf, sex: sex, variant: variant);
}

TrendScope _scope(String raw, String usage) {
  try {
    return TrendScope.parse(raw);
  } on FormatException catch (e) {
    throw _Usage('${e.message} $usage');
  }
}

/// The chart as an aligned table; [cell] formats one value (null = '.').
String _table(TrendChart c, String Function(num v) cell, {List<String> extraRow = const []}) {
  final rows = <List<String>>[
    ['', ...c.xLabels],
    for (final s in c.series) [s.name, for (final v in s.values) v == null ? '.' : cell(v)],
    if (extraRow.isNotEmpty) extraRow,
  ];
  final widths = [
    for (var i = 0; i < rows.first.length; i++) rows.map((r) => r[i].length).reduce((a, b) => a > b ? a : b),
  ];
  final out = StringBuffer(c.title);
  for (final r in rows) {
    out.write('\n  ');
    for (var i = 0; i < r.length; i++) {
      out.write(i == 0 ? r[i].padRight(widths[i]) : '  ${r[i].padLeft(widths[i])}');
    }
  }
  return out.toString();
}

/// Per x label, the sum of every series (a "Total assessed" row).
List<String> _totals(TrendChart c) => [
      for (var i = 0; i < c.xLabels.length; i++) c.series.fold<num>(0, (n, s) => n + (s.values[i] ?? 0)).toString(),
    ];

void registerTrendCommands(ConsoleRegistry registry, TrendViewModel vm) {
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

  add('trend-bands',
      'trend-bands $_scopeHelp <year> [asof=YYYY-MM-DD] [sex=M|F|T] — learners per Form 2b band per Phil-IRI round',
      (args) async {
    const usage = 'Usage: trend-bands $_scopeHelp <year> [asof=YYYY-MM-DD] [sex=M|F|T]';
    if (args.length < 2) throw const _Usage(usage);
    final scope = _scope(args[0], usage);
    final o = _parse(args.sublist(2), allowSex: true, usage: usage);
    final c = await vm.bandDistribution(scope, args[1], sex: o.sex ?? NlaSex.total, asOf: o.asOf);
    if (c.xLabels.isEmpty) return '${c.title}\n  No Phil-IRI results yet.';
    return _table(c, (v) => '$v', extraRow: ['Total assessed', ..._totals(c)]);
  });

  add('trend-completion',
      'trend-completion $_scopeHelp <year> [asof=YYYY-MM-DD] — % of learners assessed per scheduled Phil-IRI round',
      (args) async {
    const usage = 'Usage: trend-completion $_scopeHelp <year> [asof=YYYY-MM-DD]';
    if (args.length < 2) throw const _Usage(usage);
    final scope = _scope(args[0], usage);
    final o = _parse(args.sublist(2), allowSex: false, usage: usage);
    final c = await vm.completion(scope, args[1], asOf: o.asOf);
    if (c.series.isEmpty) return '${c.title}\n  No Grade 4-10 sections.';
    if (c.xLabels.isEmpty) return '${c.title}\n  No Phil-IRI round scheduled.';
    final line = c.referenceLine == null
        ? 'Done threshold: differs per school'
        : 'Done threshold: ${c.referenceLine!.toStringAsFixed(1)}%';
    return '${_table(c, (v) => v.toStringAsFixed(1))}\n  $line';
  });

  add('trend-crla-profiles',
      'trend-crla-profiles $_scopeHelp <year> [asof=YYYY-MM-DD] [variant=mt|fil|eng] — Grade 1-3 learners per CRLA '
          'reading profile per round',
      (args) async {
    const usage = 'Usage: trend-crla-profiles $_scopeHelp <year> [asof=YYYY-MM-DD] [variant=mt|fil|eng]';
    if (args.length < 2) throw const _Usage(usage);
    final scope = _scope(args[0], usage);
    final o = _parse(args.sublist(2), allowSex: false, allowVariant: true, usage: usage);
    final c = await vm.crlaProfiles(scope, args[1], variant: o.variant, asOf: o.asOf);
    if (c.xLabels.isEmpty) return '${c.title}\n  No CRLA results yet.';
    return _table(c, (v) => '$v', extraRow: ['Total assessed', ..._totals(c)]);
  });

  add('trend-aral-exits',
      'trend-aral-exits $_scopeHelp <year> [asof=YYYY-MM-DD] [sex=M|F|T] — ARAL learners and exits per Phil-IRI '
          'round (Division report)',
      (args) async {
    const usage = 'Usage: trend-aral-exits $_scopeHelp <year> [asof=YYYY-MM-DD] [sex=M|F|T]';
    if (args.length < 2) throw const _Usage(usage);
    final scope = _scope(args[0], usage);
    final o = _parse(args.sublist(2), allowSex: true, usage: usage);
    final c = await vm.aralExits(scope, args[1], sex: o.sex ?? NlaSex.total, asOf: o.asOf);
    if (c.xLabels.isEmpty) return '${c.title}\n  No Phil-IRI results yet.';
    return _table(c, (v) => '$v');
  });

  add('trend-aral-activity',
      'trend-aral-activity $_activityScopeHelp <year> [asof=YYYY-MM-DD] — ARAL sessions and attendance per month',
      (args) async {
    const usage = 'Usage: trend-aral-activity $_activityScopeHelp <year> [asof=YYYY-MM-DD]';
    if (args.length < 2) throw const _Usage(usage);
    final scope = _scope(args[0], usage);
    final o = _parse(args.sublist(2), allowSex: false, usage: usage);
    final c = await vm.aralActivity(scope, args[1], asOf: o.asOf);
    if (c.sessions.xLabels.isEmpty) return '${c.sessions.title}\n  No ARAL sessions yet.';
    return '${_table(c.sessions, (v) => '$v')}\n${_table(c.attendance, (v) => v.toStringAsFixed(1))}\n'
        "  Attendance = present / (present + absent); excused marks don't count.";
  });
}
