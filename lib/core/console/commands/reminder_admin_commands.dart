// lib/core/console/commands/reminder_admin_commands.dart
// Admin build only: the admin half of reminder_commands.dart (tutor build split, 2026-10-22).

import '../console_command.dart';
import '../console_registry.dart';
import '../../../viewmodels/reminder_viewmodel.dart';
import 'reminder_command_helpers.dart';
import 'reminder_commands.dart';

void registerReminderAdminCommands(ConsoleRegistry registry, ReminderViewModel vm) {
  void add(String name, String description, Future<String> Function(List<String> args) handler) {
    registry.register(ConsoleCommand(
      name: name,
      description: description,
      handler: (args) async {
        try {
          return await handler(args);
        } on ReminderUsage catch (e) {
          return e.message;
        } catch (e) {
          return '$name failed: $e';
        }
      },
    ));
  }

  add('reminders-coordinator',
      'reminders-coordinator <schoolId|all> <year> $reminderOptions — rounds opening soon, in progress or overdue, '
          'with the sections below the done threshold', (args) async {
    const usage = 'Usage: reminders-coordinator <schoolId|all> <year> $reminderOptions';
    if (args.length < 2) throw const ReminderUsage(usage);
    final int? schoolId;
    if (args[0].toLowerCase() == 'all') {
      schoolId = null;
    } else {
      schoolId = int.tryParse(args[0]) ?? (throw ReminderUsage('Invalid school: "${args[0]}" (a school id or all). $usage'));
    }
    final o = reminderParse(args.sublist(2));
    final schools = await vm.coordinatorReminders(schoolId, args[1], today: o.today, doneThreshold: o.done);
    if (schools.isEmpty) return 'No schools on this device.';
    return coordinatorRemindersText(schools);
  });
}
