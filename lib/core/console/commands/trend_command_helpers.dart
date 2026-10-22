// lib/core/console/commands/trend_command_helpers.dart
// Helpers shared by trend_commands.dart and trend_admin_commands.dart (no admin code here).

import '../../../viewmodels/nla_report_viewmodel.dart' show NlaSex;
import '../../../viewmodels/trend_viewmodel.dart';
import '../../models/trend_chart.dart';
import '../../services/calendar_rules.dart';

class TrendUsage implements Exception {
  final String message;
  const TrendUsage(this.message);
}

({DateTime? asOf, NlaSex? sex, String? variant}) trendParse(List<String> opts,
    {required bool allowSex, bool allowVariant = false, required String usage}) {
  DateTime? asOf;
  NlaSex? sex;
  String? variant;
  for (final o in opts) {
    final eq = o.indexOf('=');
    if (eq < 0) throw TrendUsage('Options look like key=value (got "$o"). $usage');
    final key = o.substring(0, eq), raw = o.substring(eq + 1).trim();
    switch (key) {
      case 'asof':
        final d = RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(raw) ? DateTime.tryParse(raw) : null;
        // DateTime.parse rolls 2026-02-30 over to March; refuse it instead.
        if (d == null || calendarDate(d) != raw) throw TrendUsage('asof must be a real YYYY-MM-DD date (got "$raw")');
        asOf = d;
      case 'sex' when allowSex:
        sex = switch (raw.toUpperCase()) {
          'M' => NlaSex.male,
          'F' => NlaSex.female,
          'T' => NlaSex.total,
          _ => throw TrendUsage('sex is M, F or T (got "$raw")'),
        };
      case 'variant' when allowVariant:
        variant = raw.toLowerCase();
        if (!trendCrlaVariants.contains(variant)) throw TrendUsage('variant is mt, fil or eng (got "$raw")');
      default:
        throw TrendUsage('Unknown option "$key". $usage');
    }
  }
  return (asOf: asOf, sex: sex, variant: variant);
}

TrendScope trendScope(String raw, String usage) {
  try {
    return TrendScope.parse(raw);
  } on FormatException catch (e) {
    throw TrendUsage('${e.message} $usage');
  }
}

/// The chart as an aligned table; [cell] formats one value (null = '.').
String trendTable(TrendChart c, String Function(num v) cell, {List<String> extraRow = const []}) {
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
