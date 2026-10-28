// lib/ui/admin/learner_history_screen.dart
// Learner history (docs/handoff/screens/admin.md): one learner's progress by
// school year from this device's records, found by LRN or opened from the
// Learners screen. A part this device can't read shows its note in place.
// Admin build only.
import 'package:flutter/material.dart';

import '../../viewmodels/learner_history_viewmodel.dart';
import '../common/pickers.dart';
import '../common/screen_kit.dart';
import 'admin_scope.dart';

class LearnerHistoryScreen extends StatefulWidget {
  /// Opened from the Learners screen; null = search by LRN.
  final int? studentId;
  const LearnerHistoryScreen({super.key, this.studentId});

  @override
  State<LearnerHistoryScreen> createState() => _LearnerHistoryScreenState();
}

class _LearnerHistoryScreenState extends State<LearnerHistoryScreen> {
  final _lrn = TextEditingController();
  String? _search;

  @override
  void dispose() {
    _lrn.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final history = AdminScope.of(context).learnerHistory;
    final id = widget.studentId;
    return Scaffold(
      appBar: AppBar(title: const Text('Learner history')),
      body: id == null && _search == null
          ? PageBody(
              maxWidth: 520,
              children: [
                const SizedBox(height: 24),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Center(child: IconBadge(Icons.history_edu_outlined, size: 56)),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _lrn,
                          decoration: const InputDecoration(labelText: 'LRN', prefixIcon: Icon(Icons.search)),
                          keyboardType: TextInputType.number,
                          onSubmitted: (v) => setState(() => _search = v.trim()),
                        ),
                        const SizedBox(height: 16),
                        FilledButton(onPressed: () => setState(() => _search = _lrn.text.trim()), child: const Text('Find')),
                      ],
                    ),
                  ),
                ),
              ],
            )
          : LoadView<LearnerHistory>(
              where: 'LearnerHistory',
              reloadKey: _search,
              load: (_) => id != null ? history.history(id) : history.historyByLrn(_search!),
              builder: (context, h, _) => PageBody(
                maxWidth: 1200,
                children: [
                  if (id == null)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () => setState(() => _search = null),
                        icon: const Icon(Icons.search),
                        label: const Text('Find another learner'),
                      ),
                    ),
                  _LearnerHeader(history: h),
                  if (h.years.isEmpty) const EmptyNote('No records for this learner on this device.', icon: Icons.history),
                  if (h.years.isNotEmpty)
                    LayoutBuilder(
                      builder: (context, c) {
                        // Two columns of years on wide screens.
                        const gap = 12.0;
                        final w = c.maxWidth >= 1000 ? (c.maxWidth - gap) / 2 : c.maxWidth;
                        return Wrap(
                          spacing: gap,
                          runSpacing: gap,
                          children: [for (final y in h.years) SizedBox(width: w, child: _YearCard(year: y))],
                        );
                      },
                    ),
                ],
              ),
            ),
    );
  }
}

/// The learner's initial, name, LRN and sex, and the device's scope note.
class _LearnerHeader extends StatelessWidget {
  final LearnerHistory history;
  const _LearnerHeader({required this.history});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = history.student;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                LetterBadge(initialOf(s.lastName.isNotEmpty ? s.lastName : s.firstName), size: 56),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(studentLabel(s), style: theme.textTheme.titleLarge),
                      const SizedBox(height: 6),
                      Wrap(spacing: 6, runSpacing: 6, children: [
                        StatusChip('LRN ${s.lrn}', icon: Icons.badge_outlined),
                        if (s.sex != null) StatusChip('Sex ${s.sex!}'),
                      ]),
                    ],
                  ),
                ),
              ],
            ),
            if (history.scopeNote != null) ...[
              const SizedBox(height: 12),
              NoticeBanner(history.scopeNote!, tone: StatusTone.neutral),
            ],
          ],
        ),
      ),
    );
  }
}

/// A label with a chip as its value.
class _ChipRow extends StatelessWidget {
  final String label;
  final Widget chip;
  const _ChipRow(this.label, this.chip);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(children: [
        Expanded(
          child: Text(label, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ),
        chip,
      ]),
    );
  }
}

class _YearCard extends StatelessWidget {
  final LearnerHistoryYear year;
  const _YearCard({required this.year});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;
    Widget head(String s, IconData icon) => Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 4),
      child: Row(children: [
        Icon(icon, size: 18, color: colors.primary),
        const SizedBox(width: 8),
        Expanded(child: Text(s, style: text.titleSmall)),
      ]),
    );
    return SectionCard(
      title: 'School year ${year.schoolYear}',
      icon: Icons.calendar_month_outlined,
      children: [
        for (final e in year.enrollments)
          InfoRow('Section', 'Grade ${e.gradeLevel} ${e.sectionName} · ${e.schoolName ?? 'school not on this device'} · ${e.status}'),
        if (year.isEmpty) Text('No assessments recorded', style: text.bodyMedium?.copyWith(color: colors.onSurfaceVariant)),
        if (year.crla.isNotEmpty) ...[
          head('CRLA', Icons.record_voice_over_outlined),
          for (final round in year.crla.entries)
            for (final test in round.value.entries) InfoRow('${round.key.label} · ${test.key}', test.value ?? 'no profile'),
        ],
        if (year.philIri.isNotEmpty) ...[
          head('Phil-IRI', Icons.menu_book_outlined),
          for (final p in year.philIri) ...[
            if (p.sectionName != null) Text(p.sectionName!, style: text.labelLarge),
            if (p.results == null)
              Text(p.unavailable ?? 'No results.', style: text.bodyMedium?.copyWith(color: colors.onSurfaceVariant))
            else
              for (final r in p.results!.rounds)
                InfoRow(
                  r.round.label,
                  r.notAssessed
                      ? 'not assessed'
                      : [
                          r.profile?.label ?? 'no profile',
                          if (r.adjustedLevelLabel != null) r.adjustedLevelLabel!,
                          if (r.isStrugglingReader) 'struggling reader',
                        ].join(' · '),
                ),
          ],
        ],
        for (final a in year.aral) ...[
          head('ARAL-Reading', Icons.auto_stories_outlined),
          InfoRow('Program',
              '${a.enrollment.keyStage.label}${a.enrollment.track == null ? '' : ' ${a.enrollment.track!.label}'}'),
          if (a.className == null)
            const _ChipRow('Class', StatusChip('waiting for a class', tone: StatusTone.warn))
          else
            InfoRow('Class', '${a.className}${a.tutorName == null ? '' : ' · ${a.tutorName}'}'),
          InfoRow('Entered', '${a.enrollment.enteredOn} (${a.enrollment.basisSource.value})'),
          if (a.enrollment.referredBy != null)
            InfoRow('Referred by', '${a.enrollment.referredBy}${a.enrollment.referralReason == null ? '' : ': ${a.enrollment.referralReason}'}'),
          if (a.enrollment.exitedOn != null)
            _ChipRow(
              'Exited',
              StatusChip('${a.enrollment.exitedOn} (${a.enrollment.exitReason?.value ?? ''})', icon: Icons.logout_rounded),
            ),
          InfoRow('Attendance', a.attendance.label),
          if (a.unavailable != null)
            Text(a.unavailable!, style: text.bodyMedium?.copyWith(color: colors.onSurfaceVariant))
          else ...[
            _ChipRow('16th-session check-in', _checkinChip(a.checkin16)),
            _ChipRow('32nd-session check-in', _checkinChip(a.checkin32)),
          ],
        ],
        if (year.srp != null) ...[
          head('Summer Remediation', Icons.wb_sunny_outlined),
          InfoRow('Class', [year.srp!.className, ?year.srp!.tutorName, ?year.srp!.room].join(' · ')),
        ],
      ],
    );
  }
}

Widget _checkinChip(LearnerHistoryCheckin c) => StatusChip(
  _checkin(c),
  tone: switch (c) {
    LearnerHistoryCheckin.passed => StatusTone.good,
    LearnerHistoryCheckin.failed => StatusTone.bad,
    _ => StatusTone.neutral,
  },
);

String _checkin(LearnerHistoryCheckin c) => switch (c) {
  LearnerHistoryCheckin.passed => 'passed',
  LearnerHistoryCheckin.failed => 'not passed',
  LearnerHistoryCheckin.notTaken => 'not taken',
  LearnerHistoryCheckin.unavailable => 'not available on this device',
};
