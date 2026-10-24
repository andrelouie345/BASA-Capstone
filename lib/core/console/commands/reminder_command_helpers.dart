// lib/core/console/commands/reminder_command_helpers.dart
// Helpers shared by reminder_commands.dart and reminder_admin_commands.dart (no admin code here).

import '../date_args.dart';

class ReminderUsage implements Exception {
  final String message;
  const ReminderUsage(this.message);
}

const reminderOptions = '[today=YYYY-MM-DD] [done=<percent>]';

({DateTime? today, double? done}) reminderParse(List<String> opts) {
  DateTime? today;
  double? done;
  for (final o in opts) {
    final eq = o.indexOf('=');
    if (eq < 0) throw ReminderUsage('Options look like key=value (got "$o"). $reminderOptions');
    final key = o.substring(0, eq), raw = o.substring(eq + 1).trim();
    switch (key) {
      case 'today':
        final d = strictDateArg(raw);
        if (d == null) throw ReminderUsage('today must be a real YYYY-MM-DD date (got "$raw")');
        today = d;
      case 'done':
        final p = double.tryParse(raw.endsWith('%') ? raw.substring(0, raw.length - 1) : raw);
        if (p == null || p <= 0 || p > 100) throw ReminderUsage('done is a percent above 0 and up to 100 (got "$raw")');
        done = p / 100;
      default:
        throw ReminderUsage('Unknown option "$key". $reminderOptions');
    }
  }
  return (today: today, done: done);
}
