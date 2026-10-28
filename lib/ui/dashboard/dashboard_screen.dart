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
        maxWidth: 1100,
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
    StatGrid(tiles: [
      StatTile(label: 'Sections', value: '${t.sections.length}', icon: Icons.class_outlined),
      StatTile(
        label: 'Learners',
        value: '${t.sections.fold(0, (a, s) => a + s.$2)}',
        icon: Icons.people_alt_outlined,
      ),
      StatTile(label: 'ARAL active', value: '${t.aral.active}', icon: Icons.auto_stories_outlined),
      StatTile(label: 'Sessions held', value: '${t.reminders.sessionsHeld}', icon: Icons.event_available_outlined),
    ]),
    const SizedBox(height: 16),
    SectionCard(
      title: 'My sections',
      icon: Icons.class_outlined,
      children: t.sections.isEmpty
          ? [const _Quiet('No sections assigned to you.')]
          : [for (final (sec, n) in t.sections) InfoRow('$sec', '$n learner(s)')],
    ),
    const SizedBox(height: 16),
    SectionCard(
      title: 'Reminders',
      icon: Icons.notifications_none,
      children: t.reminders.reminders.isEmpty
          ? [const _Quiet('Nothing needs your attention.')]
          : [for (final r in t.reminders.reminders) _ReminderLine(text: r.message, icon: Icons.notifications_none)],
    ),
  ];

  List<Widget> _school(BuildContext context, SchoolSummary s) => [
    Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(children: [
        const IconBadge(Icons.school_outlined, size: 36),
        const SizedBox(width: 12),
        Expanded(child: Text(s.school.schoolName, style: Theme.of(context).textTheme.titleLarge)),
      ]),
    ),
    StatGrid(tiles: [
      for (final e in s.counts.entries)
        StatTile(
          label: '${e.key.label} learners · ${e.value.sections} section(s)',
          value: '${e.value.learners}',
          icon: Icons.people_alt_outlined,
        ),
      StatTile(label: 'ARAL active', value: '${s.aral.active}', icon: Icons.auto_stories_outlined),
      StatTile(label: 'ARAL exited', value: '${s.aral.exited}', icon: Icons.logout_rounded),
      StatTile(label: 'Not grade-level ready', value: '${s.masterlistLearners}', icon: Icons.flag_outlined),
      StatTile(
        label: 'SRP classes · ${s.srpClassLearners} learners',
        value: '${s.srpClasses}',
        icon: Icons.wb_sunny_outlined,
      ),
    ]),
    const SizedBox(height: 16),
    SectionCard(
      title: 'Rounds (done at ${thresholdPercent(s.doneThreshold)})',
      icon: Icons.donut_large_outlined,
      children: [
        if (s.current.isEmpty && s.next.isEmpty) const _Quiet('No rounds scheduled for this year.'),
        for (final r in [...s.current, ...s.next])
          _RoundProgress(
            title: '${r.roundName} · ${r.status.label}',
            detail:
                '${r.assessed}/${r.enrolled} assessed (${progressPercent(r.share)}%) · ${r.sectionsDone}/${r.sectionCount} sections done',
            share: r.share,
            done: s.doneThreshold,
          ),
      ],
    ),
    const SizedBox(height: 16),
    SectionCard(
      title: 'Reminders',
      icon: Icons.notifications_none,
      children: [
        if (s.reminders.reminders.isEmpty && s.reminders.aral.isEmpty) const _Quiet('Nothing needs attention.'),
        for (final r in s.reminders.reminders) _ReminderLine(text: r.message, icon: _kindIcon(r.kind)),
        for (final n in s.reminders.aral) _ReminderLine(text: n.message, icon: Icons.groups_outlined),
      ],
    ),
  ];

  List<Widget> _region(BuildContext context, RegionDashboard r) => [
    StatGrid(tiles: [
      StatTile(label: 'Schools', value: '${r.schools.length}', icon: Icons.account_balance_outlined),
      for (final e in r.counts.entries)
        StatTile(label: '${e.key.label} learners', value: '${e.value.learners}', icon: Icons.people_alt_outlined),
      StatTile(label: 'ARAL active', value: '${r.aral.active}', icon: Icons.auto_stories_outlined),
      StatTile(label: 'Not grade-level ready', value: '${r.masterlistLearners}', icon: Icons.flag_outlined),
      StatTile(label: 'SRP classes', value: '${r.srpClasses}', icon: Icons.wb_sunny_outlined),
      for (final e in r.reminders.entries)
        StatTile(label: 'Reminders: ${_kindLabel(e.key)}', value: '${e.value}', icon: _kindIcon(e.key)),
    ]),
    const SizedBox(height: 20),
    Text('Schools', style: Theme.of(context).textTheme.titleMedium),
    const SizedBox(height: 8),
    for (final s in r.schools) ...[
      Card(
        clipBehavior: Clip.antiAlias,
        child: ExpansionTile(
          leading: const IconBadge(Icons.school_outlined, size: 36),
          title: Text(s.school.schoolName),
          subtitle: Text('ARAL ${s.aral.active} active · ${s.reminders.reminders.length} reminder(s)'),
          childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          children: [Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: _school(context, s))],
        ),
      ),
      const SizedBox(height: 10),
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

/// Muted text for "nothing here".
class _Quiet extends StatelessWidget {
  final String text;
  const _Quiet(this.text);

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
  );
}

/// One round: its name, a bar filled to the share assessed (marked green once
/// past the done threshold) and the counts.
class _RoundProgress extends StatelessWidget {
  final String title;
  final String detail;
  final double? share;
  final double done;
  const _RoundProgress({required this.title, required this.detail, required this.share, required this.done});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final value = (share ?? 0).clamp(0.0, 1.0);
    final reached = share != null && share! >= done;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Expanded(child: Text(title, style: theme.textTheme.titleSmall)),
            if (reached) Icon(Icons.check_circle, size: 18, color: colors.tertiary),
          ]),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: value,
              minHeight: 8,
              color: reached ? colors.tertiary : colors.primary,
            ),
          ),
          const SizedBox(height: 6),
          Text(detail, style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant)),
        ],
      ),
    );
  }
}

class _ReminderLine extends StatelessWidget {
  final String text;
  final IconData icon;
  const _ReminderLine({required this.text, required this.icon});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: colors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 18, color: colors.secondary),
          const SizedBox(width: 10),
          Expanded(child: Text(text)),
        ]),
      ),
    );
  }
}
