// lib/core/console/commands/reminder_commands.dart

/// Dashboard reminders (D2: coordinators). Read from this device's copy
/// (pull-cloud brings the calendar, settings and results). `today=` and
/// `done=` let a test look at any day or threshold.
library;

import '../console_command.dart';
import '../console_registry.dart';
import '../../../viewmodels/reminder_viewmodel.dart';
import '../../models/report_setting.dart';
import '../../services/calendar_rules.dart';

class _Usage implements Exception {
  final String message;
  const _Usage(this.message);
}

const _options = '[today=YYYY-MM-DD] [done=<percent>]';

({DateTime? today, double? done}) _parse(List<String> opts) {
  DateTime? today;
  double? done;
  for (final o in opts) {
    final eq = o.indexOf('=');
    if (eq < 0) throw _Usage('Options look like key=value (got "$o"). $_options');
    final key = o.substring(0, eq), raw = o.substring(eq + 1).trim();
    switch (key) {
      case 'today':
        final d = RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(raw) ? DateTime.tryParse(raw) : null;
        // DateTime.parse rolls 2026-02-30 over to March; refuse it instead.
        if (d == null || calendarDate(d) != raw) throw _Usage('today must be a real YYYY-MM-DD date (got "$raw")');
        today = d;
      case 'done':
        final p = double.tryParse(raw.endsWith('%') ? raw.substring(0, raw.length - 1) : raw);
        if (p == null || p <= 0 || p > 100) throw _Usage('done is a percent above 0 and up to 100 (got "$raw")');
        done = p / 100;
      default:
        throw _Usage('Unknown option "$key". $_options');
    }
  }
  return (today: today, done: done);
}

String _text(List<SchoolReminders> schools) {
  final out = StringBuffer();
  for (final s in schools) {
    if (out.isNotEmpty) out.write('\n');
    out.write('School ${s.schoolName} (#${s.schoolId}) — done at ${thresholdPercent(s.doneThreshold)}');
    if (s.reminders.isEmpty) out.write('\n  No reminders.');
    for (final r in s.reminders) {
      final tag = switch (r.kind) {
        ReminderKind.overdue => 'OVERDUE',
        ReminderKind.inProgress => 'IN PROGRESS',
        ReminderKind.headsUp => 'HEADS-UP',
      };
      out.write('\n  [$tag] ${r.message}');
      for (final c in r.below) {
        out.write('\n      Grade ${c.section.gradeLevel} ${c.section.sectionName} (#${c.section.id})  '
            '${c.assessed}/${c.enrolled} (${(c.share * 100).toStringAsFixed(1)}%)');
      }
    }
  }
  return out.toString();
}

void registerReminderCommands(ConsoleRegistry registry, ReminderViewModel vm) {
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

  add('reminders-coordinator',
      'reminders-coordinator <schoolId|all> <year> $_options — rounds opening soon, in progress or overdue, '
          'with the sections below the done threshold', (args) async {
    const usage = 'Usage: reminders-coordinator <schoolId|all> <year> $_options';
    if (args.length < 2) throw const _Usage(usage);
    final int? schoolId;
    if (args[0].toLowerCase() == 'all') {
      schoolId = null;
    } else {
      schoolId = int.tryParse(args[0]) ?? (throw _Usage('Invalid school: "${args[0]}" (a school id or all). $usage'));
    }
    final o = _parse(args.sublist(2));
    final schools = await vm.coordinatorReminders(schoolId, args[1], today: o.today, doneThreshold: o.done);
    if (schools.isEmpty) return 'No schools on this device.';
    return _text(schools);
  });
}
