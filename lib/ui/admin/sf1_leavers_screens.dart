// lib/ui/admin/sf1_leavers_screens.dart
// SF1 leavers (docs/handoff/screens/sf1-leavers.md): the school-wide
// Undecided learners list (active, but not on their section's last imported
// SF1: archive as transferred out / dropped out, or move to a same-grade
// section) and Anonymize archived learners (preview, then a destructive
// confirm; never automatic). Every action is online and calls one server
// function; refusals are shown as the ViewModel words them. Admin build only.
import 'package:flutter/material.dart';

import '../../core/models/enrollment.dart' show EnrollmentStatus;
import '../../core/models/school.dart';
import '../../core/models/section.dart';
import '../../core/models/sf1_missing_learner.dart';
import '../../viewmodels/learner_leavers_viewmodel.dart';
import '../common/pickers.dart';
import '../common/screen_kit.dart';
import 'admin_scope.dart';

/// The superadmin has no school of their own: they pick one. Everyone else
/// works on their own school ([builder] gets null = "my school").
class _SchoolScope extends StatefulWidget {
  final Widget Function(BuildContext context, int? schoolId) builder;
  const _SchoolScope({required this.builder});

  @override
  State<_SchoolScope> createState() => _SchoolScopeState();
}

class _SchoolScopeState extends State<_SchoolScope> {
  School? _school;

  @override
  Widget build(BuildContext context) {
    final own = vmsOf(context).auth.currentUser?.schoolId;
    if (own != null) return widget.builder(context, null);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      FilterBar(children: [SchoolPicker(value: _school, onChanged: (s) => setState(() => _school = s))]),
      const SizedBox(height: 16),
      if (_school == null)
        const EmptyNote('Pick a school to continue.', icon: Icons.filter_alt_outlined)
      else
        widget.builder(context, _school!.id),
    ]);
  }
}

// ---------------------------------------------------------------------------
// Undecided learners

class UndecidedLearnersScreen extends StatelessWidget {
  const UndecidedLearnersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Undecided learners')),
      body: PageBody(
        maxWidth: 1200,
        children: [
          const Text("Learners still active but not on their section's last imported SF1. Decide each one, or "
              'leave them: they stay active until you do.'),
          _SchoolScope(builder: (context, schoolId) => _UndecidedBody(key: ValueKey(schoolId), schoolId: schoolId)),
        ],
      ),
    );
  }
}

class _UndecidedBody extends StatefulWidget {
  /// Null = the user's own school.
  final int? schoolId;
  const _UndecidedBody({super.key, required this.schoolId});

  @override
  State<_UndecidedBody> createState() => _UndecidedBodyState();
}

class _UndecidedBodyState extends State<_UndecidedBody> {
  Section? _section;
  int _reload = 0;

  int? get _school => widget.schoolId ?? vmsOf(context).auth.currentUser?.schoolId;

  @override
  Widget build(BuildContext context) {
    final leavers = AdminScope.of(context).learnerLeavers;
    final school = _school;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      FilterBar(children: [
        SectionPicker(
          value: _section,
          reloadKey: school,
          where: (s) => s.schoolId == school,
          onChanged: (s) => setState(() => _section = s),
        ),
        if (_section != null)
          OutlinedButton.icon(
            icon: const Icon(Icons.clear),
            label: const Text('Every section'),
            onPressed: () => setState(() => _section = null),
          ),
      ]),
      const SizedBox(height: 16),
      LoadView<List<Sf1MissingLearner>>(
        where: 'Sf1Leavers',
        reloadKey: '${widget.schoolId}-${_section?.id}-$_reload',
        load: (_) => leavers.missing(sectionId: _section?.id, schoolId: widget.schoolId),
        builder: (context, items, _) => ListCard(
          title: 'Not on their section\'s SF1',
          trailing: StatusChip('${items.length}'),
          children: items.isEmpty
              ? [const EmptyNote('No undecided learners.', icon: Icons.task_alt)]
              : [
                  for (final m in items)
                    ListRow(
                      leading: LetterBadge(initialOf(m.name)),
                      title: m.name,
                      subtitle: 'LRN ${m.lrn} · ${m.sectionName ?? 'section ${m.sectionId}'}',
                      trailing: [
                        LeaverDecisionMenu(
                          learner: m,
                          fromSectionId: m.sectionId!,
                          schoolId: widget.schoolId,
                          onDone: () => setState(() => _reload++),
                        ),
                      ],
                    ),
                ],
        ),
      ),
    ]);
  }
}

// ---------------------------------------------------------------------------
// The decision menu for a learner not on their section's SF1 (Undecided
// learners, and "Not on this SF1" in the SF1 import trial).

/// Transferred out / Dropped out (archive, optional note) / Moved to
/// section... (same school, year and grade). Shows the ViewModel's message,
/// then calls [onDone] (reload the list, rerun the trial).
class LeaverDecisionMenu extends StatelessWidget {
  final Sf1MissingLearner learner;

  /// The section the learner is in (and missing from).
  final int fromSectionId;

  /// The superadmin passes the school; null = the user's own.
  final int? schoolId;
  final VoidCallback onDone;

  const LeaverDecisionMenu(
      {super.key, required this.learner, required this.fromSectionId, required this.schoolId, required this.onDone});

  Future<void> _done(BuildContext context, LearnerLeaverOutcome? r) async {
    if (r == null || !context.mounted) return;
    await showTextDialog(context, title: 'Done', text: r.message);
    onDone();
  }

  Future<void> _archive(BuildContext context, EnrollmentStatus reason) async {
    final m = learner;
    final leavers = AdminScope.of(context).learnerLeavers;
    final what = reason == EnrollmentStatus.transferredOut ? 'transferred out' : 'dropped out';
    final f = await askFields(
      context,
      title: 'Archive ${m.name} as $what',
      note: 'Nothing is deleted: the learner leaves every active list and can no longer be assessed; their active '
          'ARAL entry this year is exited. You can restore them later.',
      action: 'Archive',
      fields: const [FieldSpec('note', 'Note (optional)', optional: true, multiline: true)],
    );
    if (f == null || !context.mounted) return;
    final note = f['note']!.isEmpty ? null : f['note'];
    final r = await runAction(context, () => leavers.archive(m.enrollmentId, reason, note: note), where: 'Sf1Leavers');
    if (context.mounted) await _done(context, r);
  }

  Future<void> _move(BuildContext context) async {
    final m = learner;
    final vms = vmsOf(context);
    final leavers = AdminScope.of(context).learnerLeavers;
    final all = await runAction(context, () => vms.section.localSections(), where: 'Sf1Leavers');
    if (all == null || !context.mounted) return;
    final from = all.where((s) => s.id == fromSectionId).firstOrNull;
    if (from == null) {
      return showNote(context, 'Section $fromSectionId is not on this device. Download the latest data first.');
    }
    // Same school, year and grade only (the server refuses anything else).
    final targets = all
        .where((s) =>
            s.id != from.id && s.schoolId == from.schoolId && s.schoolYear == from.schoolYear && s.gradeLevel == from.gradeLevel)
        .toList()
      ..sort((a, b) => a.sectionName.compareTo(b.sectionName));
    if (targets.isEmpty) {
      return showNote(context, 'No other Grade ${from.gradeLevel} section for ${from.schoolYear} on this device.');
    }
    final to = await pickOne<Section>(context, title: 'Move ${m.name} to', options: targets, label: (s) => sectionLabel(s));
    if (to == null || !context.mounted) return;
    if (!await confirm(context,
            title: 'Move ${m.name} to ${to.sectionName}?',
            body: "This school year's CRLA, Phil-IRI and GST records go along.",
            action: 'Move') ||
        !context.mounted) {
      return;
    }
    final r = await runAction(context, () => leavers.move(m.enrollmentId, to.id!, schoolId: schoolId), where: 'Sf1Leavers');
    if (context.mounted) await _done(context, r);
  }

  @override
  Widget build(BuildContext context) => PopupMenuButton<String>(
        tooltip: 'Decide',
        icon: const Icon(Icons.more_vert),
        onSelected: (a) => switch (a) {
          'transferred' => _archive(context, EnrollmentStatus.transferredOut),
          'dropped' => _archive(context, EnrollmentStatus.droppedOut),
          _ => _move(context),
        },
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'transferred', child: Text('Transferred out')),
          PopupMenuItem(value: 'dropped', child: Text('Dropped out')),
          PopupMenuItem(value: 'move', child: Text('Moved to section…')),
        ],
      );
}

// ---------------------------------------------------------------------------
// Anonymize archived learners

class AnonymizeLearnersScreen extends StatelessWidget {
  const AnonymizeLearnersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Anonymize archived learners')),
      body: PageBody(
        maxWidth: 1000,
        children: [
          const NoticeBanner(
            'This cannot be undone. Name, LRN, birth date and contact details are cleared; sex and the records are '
            'kept, and the learner can never be matched again. Only learners archived longer than the archive period '
            '(Report settings), after their school year ended, are listed. Nothing is ever anonymized automatically.',
            icon: Icons.warning_amber,
            tone: StatusTone.bad,
          ),
          _SchoolScope(builder: (context, schoolId) => _AnonymizeBody(key: ValueKey(schoolId), schoolId: schoolId)),
        ],
      ),
    );
  }
}

class _AnonymizeBody extends StatefulWidget {
  final int? schoolId;
  const _AnonymizeBody({super.key, required this.schoolId});

  @override
  State<_AnonymizeBody> createState() => _AnonymizeBodyState();
}

class _AnonymizeBodyState extends State<_AnonymizeBody> {
  ({List<AnonymizeCandidate> learners, String code})? _preview;
  bool _busy = false;

  Future<void> _run(Future<void> Function() step) async {
    setState(() => _busy = true);
    await step();
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _previewNow() => _run(() async {
        final leavers = AdminScope.of(context).learnerLeavers;
        final p = await runAction(context, () => leavers.anonymizePreview(schoolId: widget.schoolId), where: 'Anonymize');
        if (p != null && mounted) setState(() => _preview = p);
      });

  Future<void> _anonymize() async {
    final p = _preview;
    if (p == null || p.learners.isEmpty) return;
    final leavers = AdminScope.of(context).learnerLeavers;
    final n = p.learners.length;
    if (!await confirm(context,
            title: 'Anonymize $n learner(s)?',
            body: 'This cannot be undone.',
            action: 'Anonymize',
            destructive: true) ||
        !mounted) {
      return;
    }
    await _run(() async {
      final done = await runAction(context, () => leavers.anonymize(p.code, schoolId: widget.schoolId), where: 'Anonymize');
      if (!mounted) return;
      if (done != null) {
        setState(() => _preview = null);
        await showTextDialog(context, title: 'Done', text: leavers.lastMessage ?? 'Anonymized $done learner(s).');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = _preview;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Wrap(spacing: 8, runSpacing: 8, children: [
        OutlinedButton.icon(
          onPressed: _busy ? null : _previewNow,
          icon: const Icon(Icons.visibility_outlined),
          label: Text(p == null ? 'Preview' : 'Preview again'),
        ),
        if (p != null && p.learners.isNotEmpty)
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: _busy ? null : _anonymize,
            icon: const Icon(Icons.person_off_outlined),
            label: Text('Anonymize ${p.learners.length} learner(s)'),
          ),
      ]),
      const SizedBox(height: 16),
      if (p == null)
        const EmptyNote('Preview to see who may be anonymized now.', icon: Icons.person_off_outlined)
      else
        ListCard(
          title: 'May be anonymized now',
          trailing: StatusChip('${p.learners.length}'),
          children: p.learners.isEmpty
              ? [const EmptyNote('Nobody may be anonymized now.', icon: Icons.task_alt)]
              : [
                  for (final l in p.learners)
                    ListRow(
                      leading: LetterBadge(initialOf(l.name ?? '?')),
                      title: l.name ?? 'Learner ${l.studentId} (not on this device)',
                      subtitle: [
                        if (l.lrn != null) 'LRN ${l.lrn}',
                        'archived ${l.leftOn ?? '—'}',
                        l.schoolYear,
                      ].join(' · '),
                    ),
                ],
        ),
    ]);
  }
}
