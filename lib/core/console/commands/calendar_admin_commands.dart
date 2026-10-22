// lib/core/console/commands/calendar_admin_commands.dart
// Admin build only: the admin half of calendar_commands.dart (tutor build split, 2026-10-22).

import '../console_command.dart';
import '../console_registry.dart';
import '../../../viewmodels/round_calendar_viewmodel.dart';
import '../../models/assessment_calendar.dart';
import '../../services/calendar_rules.dart';
import 'calendar_command_helpers.dart';

void registerCalendarAdminCommands(ConsoleRegistry registry, RoundCalendarViewModel vm) {
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

  String warn() => vm.lastMirrorWarning == null ? '' : '\n${vm.lastMirrorWarning}';

  add('calendar-set',
      'calendar-set <region|schoolId> <year> <phil_iri|crla> <round> <opens YYYY-MM-DD> <closes YYYY-MM-DD> '
          '— set a round window (online)', (args) async {
    if (args.length != 6) {
      throw const CalendarUsage('Usage: calendar-set <region|schoolId> <year> <phil_iri|crla> <round> <opens> <closes>');
    }
    final schoolId = calendarSchool(args[0]);
    final w = await vm.setWindow(schoolId, args[1], _instrument(args[2]), args[3],
        calendarDateArg(args[4], 'opens'), calendarDateArg(args[5], 'closes'));
    return '${w.instrument.label} ${roundLabel(w.round)} ${w.schoolYear} for ${calendarWho(schoolId)}: '
        '${w.opensOn} .. ${w.closesOn}.${warn()}';
  });

  add('calendar-skip',
      'calendar-skip <schoolId> <year> <phil_iri|crla> <round> — the school does not hold that round (online)',
      (args) async {
    if (args.length != 4) throw const CalendarUsage('Usage: calendar-skip <schoolId> <year> <phil_iri|crla> <round>');
    final schoolId = calendarSchool(args[0]);
    if (schoolId == null) throw const CalendarUsage('Only a school skips a round; to drop a region window use calendar-clear region ...');
    final w = await vm.skipRound(schoolId, args[1], _instrument(args[2]), args[3]);
    return '${w.instrument.label} ${roundLabel(w.round)} ${w.schoolYear} skipped for school $schoolId.${warn()}';
  });

  add('calendar-clear',
      'calendar-clear <region|schoolId> <year> <phil_iri|crla> <round> — remove a window; a school falls back to '
          'the region window (online)', (args) async {
    if (args.length != 4) throw const CalendarUsage('Usage: calendar-clear <region|schoolId> <year> <phil_iri|crla> <round>');
    final schoolId = calendarSchool(args[0]);
    final instrument = _instrument(args[2]);
    await vm.clearWindow(schoolId, args[1], instrument, args[3]);
    final after = schoolId == null ? 'School overrides of it stay.' : 'The region window applies again (if any).';
    return '${instrument.label} ${roundLabel(args[3].trim().toLowerCase())} ${args[1]} cleared for ${calendarWho(schoolId)}. '
        '$after${warn()}';
  });
}

CalendarInstrument _instrument(String raw) {
  try {
    return CalendarInstrument.parse(raw);
  } on ArgumentError catch (e) {
    throw CalendarUsage('${e.message}');
  }
}
