// lib/core/console/commands/calendar_commands.dart

/// Assessment round calendar (dashboard D1). The set/skip/clear commands are
/// online; calendar-show reads this device's copy (pull-cloud brings it).
/// Schools are named by id; `region` = the region-wide windows.
library;

import '../console_command.dart';
import '../console_registry.dart';
import '../../../viewmodels/round_calendar_viewmodel.dart';
import '../../models/assessment_calendar.dart';
import '../../services/calendar_rules.dart';
import 'calendar_command_helpers.dart';

String _line(CalendarEntry e, DateTime today) {
  final w = e.window;
  final name = '${w.instrument.label} ${roundLabel(w.round)}'.padRight(17);
  final src = e.isOverride ? '  (school override)' : '';
  if (e.skipped) return '$name SKIPPED$src';
  return '$name ${w.opensOn} .. ${w.closesOn}  ${roundStatus(w, today).label}$src';
}

/// A stored row whose round this app version does not know for its instrument.
String _invalidLine(CalendarWindow w) {
  final name = '${w.instrument.label} "${w.round}"'.padRight(17);
  final src = w.schoolId == null ? '' : '  (school override)';
  return '$name INVALID (ignored: ${w.instrument.label} has no round "${w.round}" in this app version; '
      'run pull-cloud, or update the app)$src';
}

void registerCalendarCommands(ConsoleRegistry registry, RoundCalendarViewModel vm) {
  void add(String name, String description, Future<String> Function(List<String> args) handler) {
    registry.register(ConsoleCommand(
      name: name,
      description: description,
      handler: (args) async {
        try {
          return await handler(args);
        } on CalendarUsage catch (e) {
          return e.message;
        } catch (e) {
          return '$name failed: $e';
        }
      },
    ));
  }

  add('calendar-show',
      'calendar-show <region|schoolId> <year> [today=YYYY-MM-DD] — the rounds and their status (this device)',
      (args) async {
    const usage = 'Usage: calendar-show <region|schoolId> <year> [today=YYYY-MM-DD]';
    if (args.length < 2 || args.length > 3) throw const CalendarUsage(usage);
    var today = DateTime.now();
    if (args.length == 3) {
      if (!args[2].startsWith('today=')) throw const CalendarUsage(usage);
      today = calendarDateArg(args[2].substring(6), 'today');
    }
    final schoolId = calendarSchool(args[0]);
    final entries = await vm.effectiveCalendar(schoolId, args[1]);
    final invalid = await vm.invalidWindows(schoolId, args[1]);
    final head = 'Assessment calendar | ${calendarWho(schoolId)} | ${args[1]} | today ${calendarDate(today)}';
    return [
      head,
      if (entries.isEmpty) 'No rounds scheduled.',
      for (final e in entries) '  ${_line(e, today)}',
      for (final w in invalid) '  ${_invalidLine(w)}',
    ].join('\n');
  });
}
