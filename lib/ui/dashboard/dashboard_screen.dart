// lib/ui/dashboard/dashboard_screen.dart
// Dashboard home (docs/handoff/screens/dashboard.md): the year's figures for
// the signed-in user: a tutor's own work, a school's, or every school with
// the regional sums for a superadmin. The year is always picked; the newest
// is chosen first.
import 'package:flutter/material.dart';

import '../../core/models/report_setting.dart';
import '../../viewmodels/dashboard_viewmodel.dart';
import '../../viewmodels/nla_report_viewmodel.dart';
import '../../viewmodels/reminder_viewmodel.dart';
import '../common/pickers.dart';
import '../common/screen_kit.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  String? _year;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Dashboard')),
      body: PageBody(
        children: [
          SchoolYearPicker(value: _year, onChanged: (y) => setState(() => _year = y)),
          if (_year != null)
            LoadView<DashboardSummary>(
              where: 'DashboardScreen',
              reloadKey: _year,
              load: (vms) => vms.dashboard.summary(_year!),
              builder: (context, s, _) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: switch (s) {
                  TutorDashboard t => _tutor(context, t),
                  SchoolDashboard d => _school(context, d.school),
                  RegionDashboard r => _region(context, r),
                },
              ),
            ),
        ],
      ),
    );
  }

  List<Widget> _tutor(BuildContext context, TutorDashboard t) => [
    _Stats(items: [
      ('Sections', '${t.sections.length}'),
      ('Learners', '${t.sections.fold(0, (a, s) => a + s.$2)}'),
      ('ARAL active', '${t.aral.active}'),
      ('Sessions held', '${t.reminders.sessionsHeld}'),
    ]),
    const SizedBox(height: 12),
    SectionCard(
      title: 'My sections',
      children: t.sections.isEmpty
          ? [const Text('No sections assigned to you.')]
          : [for (final (sec, n) in t.sections) InfoRow('$sec', '$n learner(s)')],
    ),
    const SizedBox(height: 12),
    SectionCard(
      title: 'Reminders',
      children: t.reminders.reminders.isEmpty
          ? [const Text('Nothing needs your attention.')]
          : [for (final r in t.reminders.reminders) _ReminderLine(text: r.message, icon: Icons.notifications_none)],
    ),
  ];

  List<Widget> _school(BuildContext context, SchoolSummary s) => [
    Text(s.school.schoolName, style: Theme.of(context).textTheme.titleLarge),
    const SizedBox(height: 8),
    _Stats(items: [
      for (final e in s.counts.entries) ('${e.key.label} learners', '${e.value.learners} in ${e.value.sections} section(s)'),
      ('ARAL active', '${s.aral.active}'),
      ('ARAL exited', '${s.aral.exited}'),
      ('Not grade-level ready', '${s.masterlistLearners}'),
      ('SRP classes', '${s.srpClasses} (${s.srpClassLearners} learners)'),
    ]),
    const SizedBox(height: 12),
    SectionCard(
      title: 'Rounds (done at ${thresholdPercent(s.doneThreshold)})',
      children: [
        if (s.current.isEmpty && s.next.isEmpty) const Text('No rounds scheduled for this year.'),
        for (final r in [...s.current, ...s.next])
          InfoRow(
            '${r.roundName} · ${r.status.label}',
            '${r.assessed}/${r.enrolled} assessed (${progressPercent(r.share)}%) · ${r.sectionsDone}/${r.sectionCount} sections done',
          ),
      ],
    ),
    const SizedBox(height: 12),
    SectionCard(
      title: 'Reminders',
      children: [
        if (s.reminders.reminders.isEmpty && s.reminders.aral.isEmpty) const Text('Nothing needs attention.'),
        for (final r in s.reminders.reminders) _ReminderLine(text: r.message, icon: _kindIcon(r.kind)),
        for (final n in s.reminders.aral) _ReminderLine(text: n.message, icon: Icons.groups_outlined),
      ],
    ),
  ];

  List<Widget> _region(BuildContext context, RegionDashboard r) => [
    _Stats(items: [
      ('Schools', '${r.schools.length}'),
      for (final e in r.counts.entries) ('${e.key.label} learners', '${e.value.learners}'),
      ('ARAL active', '${r.aral.active}'),
      ('Not grade-level ready', '${r.masterlistLearners}'),
      ('SRP classes', '${r.srpClasses}'),
      for (final e in r.reminders.entries) ('Reminders: ${_kindLabel(e.key)}', '${e.value}'),
    ]),
    const SizedBox(height: 12),
    for (final s in r.schools) ...[
      ExpansionTile(
        title: Text(s.school.schoolName),
        subtitle: Text('ARAL ${s.aral.active} active · ${s.reminders.reminders.length} reminder(s)'),
        children: [Padding(padding: const EdgeInsets.all(8), child: Column(children: _school(context, s)))],
      ),
    ],
  ];
}

String _kindLabel(ReminderKind k) => switch (k) {
  ReminderKind.overdue => 'overdue',
  ReminderKind.inProgress => 'in progress',
  ReminderKind.headsUp => 'coming up',
};

IconData _kindIcon(ReminderKind k) => switch (k) {
  ReminderKind.overdue => Icons.warning_amber,
  ReminderKind.inProgress => Icons.timelapse,
  ReminderKind.headsUp => Icons.event_note,
};

class _ReminderLine extends StatelessWidget {
  final String text;
  final IconData icon;
  const _ReminderLine({required this.text, required this.icon});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
      const SizedBox(width: 8),
      Expanded(child: Text(text)),
    ]),
  );
}

/// Big numbers in tiles.
class _Stats extends StatelessWidget {
  final List<(String, String)> items;
  const _Stats({required this.items});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        for (final (label, value) in items)
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 150),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text(value, style: theme.textTheme.titleLarge?.copyWith(color: theme.colorScheme.primary)),
                  Text(label, style: theme.textTheme.bodySmall),
                ]),
              ),
            ),
          ),
      ],
    );
  }
}
