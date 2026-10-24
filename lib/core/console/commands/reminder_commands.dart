// lib/core/console/commands/reminder_commands.dart

/// Dashboard reminders (D2: coordinators, D3: tutors). Read from this device's copy
/// (pull-cloud brings the calendar, settings and results). `today=` and
/// `done=` let a test look at any day or threshold.
library;

import '../console_command.dart';
import '../console_registry.dart';
import '../../../viewmodels/reminder_viewmodel.dart';
import '../../models/report_setting.dart';
import 'reminder_command_helpers.dart';

/// Coordinator reminders as console text (also used by `dashboard`).
String coordinatorRemindersText(List<SchoolReminders> schools) {
  final out = StringBuffer();
  for (final s in schools) {
    if (out.isNotEmpty) out.write('\n');
    out.write('School ${s.schoolName} (#${s.schoolId}) — done at ${thresholdPercent(s.doneThreshold)}');
    if (s.reminders.isEmpty && s.aral.isEmpty) out.write('\n  No reminders.');
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
    for (final n in s.aral) {
      out.write('\n  [ARAL] ${n.message}');
      for (final l in n.learners) {
        out.write('\n      ${l.lrn.isEmpty ? '(no LRN)' : l.lrn}  ${l.name}  (ARAL #${l.enrollmentId})');
      }
    }
  }
  return out.toString();
}

/// Tutor reminders as console text (also used by `dashboard`).
String tutorRemindersText(TutorReminders t) {
  final out = StringBuffer('Tutor ${t.tutorName == null ? t.tutorId : '${t.tutorName} (${t.tutorId})'} — ${t.schoolYear}: '
      '${t.sessionsHeld} session${t.sessionsHeld == 1 ? '' : 's'} held in their ARAL classes, last ${t.lastSession ?? 'none'}; '
      'no-session reminder after ${t.idleSessionDays} days');
  if (t.reminders.isEmpty) out.write('\n  No reminders.');
  for (final r in t.reminders) {
    final tag = switch (r.kind) {
      TutorReminderKind.overdueAssessment => 'OVERDUE',
      TutorReminderKind.checkinDue => 'CHECK-IN',
      TutorReminderKind.openAssessment => 'IN PROGRESS',
      TutorReminderKind.noIrip => 'NO IRIP',
      TutorReminderKind.noSessionLately => 'NO SESSION',
    };
    out.write('\n  [$tag] ${r.message}');
    for (final l in r.learners) {
      out.write('\n      ${l.lrn.isEmpty ? '(no LRN)' : l.lrn}  ${l.name}'
          '${l.enrollmentId == null ? '' : '  (ARAL #${l.enrollmentId})'}');
    }
  }
  return out.toString();
}

void registerReminderCommands(ConsoleRegistry registry, ReminderViewModel vm, String? Function() currentUserId) {
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

  add('reminders-tutor',
      'reminders-tutor <tutorId|me> <year> [today=YYYY-MM-DD] — a tutor\'s unfinished work: learners not '
          'assessed, check-ins due, no IRIP, no session lately', (args) async {
    const usage = 'Usage: reminders-tutor <tutorId|me> <year> [today=YYYY-MM-DD]';
    if (args.length < 2) throw const ReminderUsage(usage);
    final o = reminderParse(args.sublist(2));
    if (o.done != null) throw const ReminderUsage('reminders-tutor takes no done= (tutors are reminded per learner). $usage');
    final tutorId = args[0].toLowerCase() == 'me' ? (currentUserId() ?? (throw const ReminderUsage('Not signed in.'))) : args[0];
    return tutorRemindersText(await vm.tutorReminders(tutorId, args[1], today: o.today));
  });
}
