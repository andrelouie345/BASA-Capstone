// lib/core/console/commands/trend_commands.dart

/// Dashboard trend charts (D4: Phil-IRI bands and completion; D5: CRLA
/// profiles, ARAL activity and exits), printed as tables: one row per series,
/// one column per x label. Read from this device's copy. `asof=` lets a test
/// look at any day.
library;

import '../console_command.dart';
import '../console_registry.dart';
import '../../../viewmodels/trend_viewmodel.dart';
import 'trend_command_helpers.dart';
const _activityScopeHelp = '<tutor:ID|tutor:me|school:ID|region>';

void registerTrendCommands(ConsoleRegistry registry, TrendViewModel vm) {
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

  add('trend-aral-activity',
      'trend-aral-activity $_activityScopeHelp <year> [asof=YYYY-MM-DD] — ARAL sessions and attendance per month',
      (args) async {
    const usage = 'Usage: trend-aral-activity $_activityScopeHelp <year> [asof=YYYY-MM-DD]';
    if (args.length < 2) throw const TrendUsage(usage);
    final scope = trendScope(args[0], usage);
    final o = trendParse(args.sublist(2), allowSex: false, usage: usage);
    final c = await vm.aralActivity(scope, args[1], asOf: o.asOf);
    if (c.sessions.xLabels.isEmpty) return '${c.sessions.title}\n  No ARAL sessions yet.';
    return '${trendTable(c.sessions, (v) => '$v')}\n${trendTable(c.attendance, (v) => v.toStringAsFixed(1))}\n'
        "  Attendance = present / (present + absent); excused marks don't count.";
  });
}
