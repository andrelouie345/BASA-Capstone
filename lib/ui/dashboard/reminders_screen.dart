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
          FilterBar(children: [SchoolYearPicker(value: _year, onChanged: (y) => setState(() => _year = y))]),
          if (_year != null && me != null)
            coordinator
                ? LoadView<List<SchoolReminders>>(
                    where: 'RemindersScreen',
                    reloadKey: _year,
                    load: (vms) => vms.reminders.coordinatorReminders(me.schoolId, _year!),
                    builder: (context, schools, _) => Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (schools.isEmpty)
                          const EmptyNote('No reminders.', icon: Icons.notifications_none)
                        else ...[
                          StatGrid(tiles: [
                            StatTile(label: 'Schools', value: '${schools.length}', icon: Icons.apartment),
                            StatTile(
                                label: 'Round reminders',
                                value: '${schools.fold<int>(0, (n, s) => n + s.reminders.length)}',
                                icon: Icons.event_note),
                            StatTile(
                                label: 'ARAL class notices',
                                value: '${schools.fold<int>(0, (n, s) => n + s.aral.length)}',
                                icon: Icons.groups_outlined),
                          ]),
                          const SizedBox(height: 16),
                        ],
                        for (final s in schools)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: SectionCard(
                              title: s.schoolName,
                              icon: Icons.apartment,
                              trailing: _CountChip(s.reminders.length + s.aral.length),
                              children: [
                                if (s.reminders.isEmpty && s.aral.isEmpty)
                                  const _AllClear('Nothing needs attention.'),
                                for (final r in s.reminders)
                                  _ReminderTile(
                                    text: r.message,
                                    icon: Icons.event_note,
                                    tone: _coordinatorTone(r.kind),
                                    details: [
                                      for (final b in r.below)
                                        _SectionProgress(
                                            label: '${b.section}: ${b.assessed}/${b.enrolled}',
                                            share: b.enrolled == 0 ? 0 : b.share),
                                    ],
                                  ),
                                for (final n in s.aral)
                                  _ReminderTile(
                                    text: n.message,
                                    icon: Icons.groups_outlined,
                                    tone: StatusTone.warn,
                                    details: [if (n.learners.isNotEmpty) _LearnerChips(n.learners)],
                                  ),
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
                    builder: (context, t, _) => Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        StatGrid(tiles: [
                          StatTile(label: 'Sessions held', value: '${t.sessionsHeld}', icon: Icons.event_available),
                          StatTile(label: 'Last session', value: t.lastSession ?? '—', icon: Icons.history),
                          StatTile(label: 'Reminders', value: '${t.reminders.length}', icon: Icons.notifications_active_outlined),
                        ]),
                        const SizedBox(height: 16),
                        SectionCard(
                          title: '${t.sessionsHeld} session(s) held${t.lastSession == null ? '' : ', last on ${t.lastSession}'}',
                          icon: Icons.notifications_none,
                          trailing: _CountChip(t.reminders.length),
                          children: [
                            if (t.reminders.isEmpty) const _AllClear('Nothing needs your attention.'),
                            for (final r in t.reminders)
                              _ReminderTile(
                                text: r.message,
                                icon: _icon(r.kind),
                                tone: r.kind == TutorReminderKind.overdueAssessment ? StatusTone.bad : StatusTone.warn,
                                details: [if (r.learners.isNotEmpty) _LearnerChips(r.learners)],
                              ),
                          ],
                        ),
                      ],
                    ),
                  )
          else if (_year == null)
            const EmptyNote('Pick a school year to see its reminders.', icon: Icons.notifications_none),
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

StatusTone _coordinatorTone(ReminderKind k) => switch (k) {
  ReminderKind.overdue => StatusTone.bad,
  ReminderKind.inProgress => StatusTone.warn,
  ReminderKind.headsUp => StatusTone.neutral,
};

/// How many reminders a card holds: good when none.
class _CountChip extends StatelessWidget {
  final int count;
  const _CountChip(this.count);

  @override
  Widget build(BuildContext context) => count == 0
      ? const StatusChip('ALL CLEAR', tone: StatusTone.good, icon: Icons.check)
      : StatusChip('$count', tone: StatusTone.warn, icon: Icons.notifications_active_outlined);
}

/// "Nothing needs attention" inside a card.
class _AllClear extends StatelessWidget {
  final String text;
  const _AllClear(this.text);

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Row(children: [
      Icon(Icons.check_circle_outline, size: 20, color: colors.tertiary),
      const SizedBox(width: 8),
      Expanded(child: Text(text, style: TextStyle(color: colors.onSurfaceVariant))),
    ]);
  }
}

/// One reminder: a tinted row with a badge, the message and what it concerns.
class _ReminderTile extends StatelessWidget {
  final String text;
  final IconData icon;
  final StatusTone tone;
  final List<Widget> details;
  const _ReminderTile({required this.text, required this.icon, required this.tone, this.details = const []});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final (bg, fg) = switch (tone) {
      StatusTone.bad => (colors.errorContainer, colors.onErrorContainer),
      StatusTone.warn => (colors.secondaryContainer, colors.onSecondaryContainer),
      StatusTone.good => (colors.tertiaryContainer, colors.onTertiaryContainer),
      StatusTone.neutral => (colors.surfaceContainerHigh, colors.onSurfaceVariant),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(color: colors.surfaceContainerLow, borderRadius: BorderRadius.circular(12)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          IconBadge(icon, size: 32, background: bg, foreground: fg),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(padding: const EdgeInsets.only(top: 6), child: Text(text)),
                for (final d in details) ...[const SizedBox(height: 8), d],
              ],
            ),
          ),
        ]),
      ),
    );
  }
}

/// A section below the done threshold: its count and a small bar.
class _SectionProgress extends StatelessWidget {
  final String label;
  final double share;
  const _SectionProgress({required this.label, required this.share});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(value: share.clamp(0.0, 1.0), minHeight: 6),
        ),
      ],
    );
  }
}

/// The learners a reminder concerns, as small chips.
class _LearnerChips extends StatelessWidget {
  final List<ReminderLearner> learners;
  const _LearnerChips(this.learners);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    // A plain Text (not StatusChip's Row) so a long name wraps on a phone.
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final l in learners)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(color: colors.surfaceContainerHigh, borderRadius: BorderRadius.circular(8)),
            child: Text('${l.name} (${l.lrn})', style: theme.textTheme.labelSmall?.copyWith(color: colors.onSurfaceVariant)),
          ),
      ],
    );
  }
}
