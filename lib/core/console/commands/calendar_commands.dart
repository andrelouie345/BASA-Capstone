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

class _Usage implements Exception {
  final String message;
  const _Usage(this.message);
}

int? _school(String raw) =>
    raw.toLowerCase() == 'region' ? null : int.tryParse(raw) ?? (throw _Usage('Invalid school: "$raw" (a school id or region)'));

CalendarInstrument _instrument(String raw) {
  try {
    return CalendarInstrument.parse(raw);
  } on ArgumentError catch (e) {
    throw _Usage('${e.message}');
  }
}

DateTime _date(String raw, String what) {
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(raw)) throw _Usage('$what must be YYYY-MM-DD (got "$raw")');
  final d = DateTime.tryParse(raw);
  // DateTime.parse rolls 2026-02-30 over to March; refuse it instead.
  if (d == null || calendarDate(d) != raw) throw _Usage('$what is not a real date: "$raw"');
  return d;
}

String _who(int? schoolId) => schoolId == null ? 'the region' : 'school $schoolId';

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
        } on _Usage catch (e) {
          return e.message;
        } catch (e) {
          return '$name failed: $e';
        }
      },
    ));
  }

  String warn() => vm.lastMirrorWarning == null ? '' : '\n${vm.lastMirrorWarning}';

  add('calendar-set',
      'calendar-set <region|schoolId> <year> <phil_iri|crla> <round> <opens YYYY-MM-DD> <closes YYYY-MM-DD> '
          '— set a round window (online)', (args) async {
    if (args.length != 6) {
      throw const _Usage('Usage: calendar-set <region|schoolId> <year> <phil_iri|crla> <round> <opens> <closes>');
    }
    final schoolId = _school(args[0]);
    final w = await vm.setWindow(schoolId, args[1], _instrument(args[2]), args[3],
        _date(args[4], 'opens'), _date(args[5], 'closes'));
    return '${w.instrument.label} ${roundLabel(w.round)} ${w.schoolYear} for ${_who(schoolId)}: '
        '${w.opensOn} .. ${w.closesOn}.${warn()}';
  });

  add('calendar-skip',
      'calendar-skip <schoolId> <year> <phil_iri|crla> <round> — the school does not hold that round (online)',
      (args) async {
    if (args.length != 4) throw const _Usage('Usage: calendar-skip <schoolId> <year> <phil_iri|crla> <round>');
    final schoolId = _school(args[0]);
    if (schoolId == null) throw const _Usage('Only a school skips a round; to drop a region window use calendar-clear region ...');
    final w = await vm.skipRound(schoolId, args[1], _instrument(args[2]), args[3]);
    return '${w.instrument.label} ${roundLabel(w.round)} ${w.schoolYear} skipped for school $schoolId.${warn()}';
  });

  add('calendar-clear',
      'calendar-clear <region|schoolId> <year> <phil_iri|crla> <round> — remove a window; a school falls back to '
          'the region window (online)', (args) async {
    if (args.length != 4) throw const _Usage('Usage: calendar-clear <region|schoolId> <year> <phil_iri|crla> <round>');
    final schoolId = _school(args[0]);
    final instrument = _instrument(args[2]);
    await vm.clearWindow(schoolId, args[1], instrument, args[3]);
    final after = schoolId == null ? 'School overrides of it stay.' : 'The region window applies again (if any).';
    return '${instrument.label} ${roundLabel(args[3].trim().toLowerCase())} ${args[1]} cleared for ${_who(schoolId)}. '
        '$after${warn()}';
  });

  add('calendar-show',
      'calendar-show <region|schoolId> <year> [today=YYYY-MM-DD] — the rounds and their status (this device)',
      (args) async {
    const usage = 'Usage: calendar-show <region|schoolId> <year> [today=YYYY-MM-DD]';
    if (args.length < 2 || args.length > 3) throw const _Usage(usage);
    var today = DateTime.now();
    if (args.length == 3) {
      if (!args[2].startsWith('today=')) throw const _Usage(usage);
      today = _date(args[2].substring(6), 'today');
    }
    final schoolId = _school(args[0]);
    final entries = await vm.effectiveCalendar(schoolId, args[1]);
    final invalid = await vm.invalidWindows(schoolId, args[1]);
    final head = 'Assessment calendar | ${_who(schoolId)} | ${args[1]} | today ${calendarDate(today)}';
    return [
      head,
      if (entries.isEmpty) 'No rounds scheduled.',
      for (final e in entries) '  ${_line(e, today)}',
      for (final w in invalid) '  ${_invalidLine(w)}',
    ].join('\n');
  });
}
