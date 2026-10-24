// lib/core/console/commands/calendar_command_helpers.dart
// Helpers shared by calendar_commands.dart and calendar_admin_commands.dart (no admin code here).

import '../date_args.dart';

class CalendarUsage implements Exception {
  final String message;
  const CalendarUsage(this.message);
}

int? calendarSchool(String raw) =>
    raw.toLowerCase() == 'region' ? null : int.tryParse(raw) ?? (throw CalendarUsage('Invalid school: "$raw" (a school id or region)'));

DateTime calendarDateArg(String raw, String what) {
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(raw)) throw CalendarUsage('$what must be YYYY-MM-DD (got "$raw")');
  return strictDateArg(raw) ?? (throw CalendarUsage('$what is not a real date: "$raw"'));
}

String calendarWho(int? schoolId) => schoolId == null ? 'the region' : 'school $schoolId';
