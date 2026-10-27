// lib/ui/dashboard/reminders_screen.dart
// Reminders (docs/handoff/screens/dashboard.md): a tutor's own (learners not
// assessed, check-ins due, no IRIP, idle classes); an admin or coordinator
// sees each school's round reminders and ARAL class notices.
import 'package:flutter/material.dart';

import '../../viewmodels/reminder_viewmodel.dart';
import '../common/pickers.dart';
import '../common/screen_kit.dart';
import '../common/signed_in_user.dart';

class RemindersScreen extends StatefulWidget {
  const RemindersScreen({super.key});

  @override
  State<RemindersScreen> createState() => _RemindersScreenState();
}

class _RemindersScreenState extends State<RemindersScreen> {
  String? _year;

  @override
  Widget build(BuildContext context) {
    final me = vmsOf(context).auth.currentUser;
    final coordinator = me != null && isAdminOrCoordinator(me);
    return Scaffold(
      appBar: AppBar(title: const Text('Reminders')),
      body: PageBody(
        children: [
          SchoolYearPicker(value: _year, onChanged: (y) => setState(() => _year = y)),
          if (_year != null && me != null)
            coordinator
                ? LoadView<List<SchoolReminders>>(
                    where: 'RemindersScreen',
                    reloadKey: _year,
                    load: (vms) => vms.reminders.coordinatorReminders(me.schoolId, _year!),
                    builder: (context, schools, _) => Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (schools.isEmpty) const EmptyNote('No reminders.'),
                        for (final s in schools)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: SectionCard(
                              title: s.schoolName,
                              children: [
                                if (s.reminders.isEmpty && s.aral.isEmpty) const Text('Nothing needs attention.'),
                                for (final r in s.reminders) ...[
                                  _Line(r.message, Icons.event_note),
                                  for (final b in r.below)
                                    Padding(
                                      padding: const EdgeInsets.only(left: 32),
                                      child: Text('${b.section}: ${b.assessed}/${b.enrolled}'),
                                    ),
                                ],
                                for (final n in s.aral) ...[
                                  _Line(n.message, Icons.groups_outlined),
                                  for (final l in n.learners)
                                    Padding(padding: const EdgeInsets.only(left: 32), child: Text('${l.name} (${l.lrn})')),
                                ],
                              ],
                            ),
                          ),
                      ],
                    ),
                  )
                : LoadView<TutorReminders>(
                    where: 'RemindersScreen',
                    reloadKey: _year,
                    load: (vms) => vms.reminders.tutorReminders(me.id, _year!),
                    builder: (context, t, _) => SectionCard(
                      title: '${t.sessionsHeld} session(s) held${t.lastSession == null ? '' : ', last on ${t.lastSession}'}',
                      children: [
                        if (t.reminders.isEmpty) const Text('Nothing needs your attention.'),
                        for (final r in t.reminders) ...[
                          _Line(r.message, _icon(r.kind)),
                          for (final l in r.learners)
                            Padding(padding: const EdgeInsets.only(left: 32), child: Text('${l.name} (${l.lrn})')),
                        ],
                      ],
                    ),
                  ),
        ],
      ),
    );
  }
}

IconData _icon(TutorReminderKind k) => switch (k) {
  TutorReminderKind.overdueAssessment => Icons.warning_amber,
  TutorReminderKind.checkinDue => Icons.checklist,
  TutorReminderKind.openAssessment => Icons.fact_check_outlined,
  TutorReminderKind.noIrip => Icons.flag_outlined,
  TutorReminderKind.noSessionLately => Icons.hourglass_empty,
};

class _Line extends StatelessWidget {
  final String text;
  final IconData icon;
  const _Line(this.text, this.icon);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
      const SizedBox(width: 8),
      Expanded(child: Text(text)),
    ]),
  );
}
