// lib/ui/admin/sf1_import_screen.dart
// SF1 import (docs/handoff/screens/admin.md, SF1 import): a workbook path,
// the column map, a trial run (nothing written), the import, then the
// conflicts it left (skip or update each, or all). Admin build only; takes
// a file path, so it is a desktop task.
import 'package:flutter/material.dart';

import '../../core/models/import_conflict.dart';
import '../../core/models/sf1.dart';
import '../common/screen_kit.dart';
import 'admin_scope.dart';
import '../../viewmodels/learner_leavers_viewmodel.dart' show LearnerLeaverOutcome;
import 'sf1_leavers_screens.dart' show LeaverDecisionMenu, UndecidedLearnersScreen;

class Sf1ImportScreen extends StatefulWidget {
  const Sf1ImportScreen({super.key});

  @override
  State<Sf1ImportScreen> createState() => _Sf1ImportScreenState();
}

class _Sf1ImportScreenState extends State<Sf1ImportScreen> {
  final _path = TextEditingController();
  Sf1TrialResult? _trial;
  String? _imported;
  bool _busy = false;
  int _conflictsReload = 0;

  @override
  void dispose() {
    _path.dispose();
    super.dispose();
  }

  Future<void> _run(bool real) async {
    final path = _path.text.trim();
    if (path.isEmpty) return showNote(context, 'Enter the workbook path first.');
    final sf1 = AdminScope.of(context).sf1Import;
    setState(() => _busy = true);
    if (real) {
      final r = await runAction(context, () => sf1.import(path), where: 'Sf1Import');
      if (r != null) {
        _imported = [
          'Imported: ${r.inserted} new learner(s), ${r.alreadyEnrolled} already enrolled, '
              '${r.conflicts} conflict(s), ${r.skippedBlankOrTotal} blank or total row(s) skipped.',
          if (r.waiting > 0)
            '${r.waiting} moving or returning learner(s) wait for your decision: try the file again to see them.',
          ?r.lastImportWarning,
          if (r.rowWarnings.isNotEmpty) 'Imported with something left out:',
          ...r.rowWarnings,
        ].join('\n');
        _conflictsReload++;
      }
    } else {
      final t = await runAction(context, () => sf1.trial(path), where: 'Sf1Import');
      if (t != null) _trial = t;
    }
    if (mounted) setState(() => _busy = false);
  }

  /// After a decision (move, restore, archive): the ViewModel's message,
  /// then the trial runs again so the rows show the new state.
  Future<void> _decided(LearnerLeaverOutcome? r) async {
    if (r == null || !mounted) return;
    await showTextDialog(context, title: 'Done', text: r.message);
    if (mounted) await _run(false);
  }

  Future<void> _moveHere(
      ({String name, String? fromSectionName, int enrollmentId}) r, int sectionId) async {
    final leavers = AdminScope.of(context).learnerLeavers;
    if (!await confirm(context,
            title: 'Move ${r.name} here?',
            body: "From ${r.fromSectionName ?? 'their section'}. This school year's CRLA, Phil-IRI and GST records go along.",
            action: 'Move here') ||
        !mounted) {
      return;
    }
    await _decided(await runAction(context, () => leavers.move(r.enrollmentId, sectionId), where: 'Sf1Import'));
  }

  Future<void> _restore(
      ({String name, int? fromSectionId, int enrollmentId, String? leftOn, String? leftReason}) r, Sf1TrialResult t) async {
    final leavers = AdminScope.of(context).learnerLeavers;
    // Archived in this very section: restored in place; else into this section.
    final here = r.fromSectionId == t.sectionId;
    if (!await confirm(context,
            title: 'Restore ${r.name}${here ? '' : ' into ${t.sectionName}'}?',
            body: 'Archived on ${r.leftOn ?? '—'} (${(r.leftReason ?? '').replaceAll('_', ' ')}). '
                'Their ARAL entry is not restored.',
            action: 'Restore') ||
        !mounted) {
      return;
    }
    await _decided(await runAction(
        context, () => leavers.restore(r.enrollmentId, toSectionId: here ? null : t.sectionId), where: 'Sf1Import'));
  }

  Future<void> _editMap(Sf1ColumnMap map) async {
    final current = map.toMap();
    final f = await askFields(
      context,
      title: 'Column map',
      note: 'The column number (0 = A) of each field in the SF1 workbook.',
      fields: [
        for (final e in current.entries) FieldSpec(e.key, e.key, initial: '${e.value ?? ''}', number: true, optional: true),
      ],
    );
    if (f == null || !mounted) return;
    for (final e in f.entries) {
      final v = int.tryParse(e.value);
      if (v == null || v == current[e.key]) continue;
      final err = await map.set(e.key, v);
      if (err != null && mounted) showNote(context, err);
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final sf1 = AdminScope.of(context).sf1Import;
    final t = _trial;
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('SF1 import'),
        actions: [
          IconButton(
            tooltip: 'Undecided learners',
            onPressed: () =>
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => const UndecidedLearnersScreen())),
            icon: const Icon(Icons.person_search_outlined),
          ),
          IconButton(tooltip: 'Column map', onPressed: () => _editMap(sf1.columnMap), icon: const Icon(Icons.view_column)),
        ],
      ),
      body: PageBody(
        children: [
          SectionCard(
            title: 'Workbook',
            icon: Icons.upload_file,
            children: [
              FilePathField(controller: _path, label: 'SF1 workbook (.xls or .xlsx)'),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: _busy ? null : () => _run(false),
                    icon: const Icon(Icons.science_outlined),
                    label: const Text('Try it (nothing is saved)'),
                  ),
                  FilledButton.icon(
                    onPressed: _busy ? null : () => _run(true),
                    icon: _busy
                        ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.upload_file),
                    label: const Text('Import'),
                  ),
                ],
              ),
            ],
          ),
          if (_imported != null) _DoneBanner(_imported!),
          if (t != null)
            SectionCard(
              title: 'Trial: Grade ${t.gradeLevel} ${t.sectionName} (${t.schoolYear})',
              icon: Icons.science_outlined,
              children: [
                StatGrid(tileWidth: 160, tiles: [
                  StatTile(label: 'Would add', value: '${t.wouldInsert}', icon: Icons.person_add_alt_1),
                  StatTile(label: 'Conflicts', value: '${t.wouldConflict}', icon: Icons.call_split),
                  StatTile(label: 'Already enrolled', value: '${t.alreadyEnrolled}', icon: Icons.how_to_reg_outlined),
                  StatTile(label: 'Skipped', value: '${t.wouldSkip}', icon: Icons.redo),
                ]),
                const SizedBox(height: 12),
                InfoRow('School', '${t.schoolName} (${t.schoolIdCode})'),
                if (t.regionError != null)
                  // A region problem, tinted so it is not missed.
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      color: colors.errorContainer.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: InfoRow('Region', t.regionError!),
                  )
                else
                  InfoRow('Region', t.rawRegion ?? '—'),
                InfoRow('Section', t.sectionId == null ? 'new: the import creates it' : 'section ${t.sectionId}'),
                if (t.rowWarnings.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  NoticeBanner('Imported with something left out:\n${t.rowWarnings.join('\n')}'),
                ],
                if (t.rows.any((r) => r.outcome != 'insert')) ...[
                  const SizedBox(height: 8),
                  const Divider(),
                  for (final r in t.rows.where((r) => r.outcome != 'insert'))
                    ListRow(
                      leading: IconBadge(
                          switch (r.outcome) {
                            'conflict' => Icons.call_split,
                            'moving' => Icons.swap_horiz,
                            'returning' => Icons.restore,
                            _ => Icons.redo,
                          },
                          size: 34),
                      title: 'Row ${r.rowIndex + 1}: ${r.name} ${r.lrn ?? ''} — ${r.outcome}${r.reason == null ? '' : ' (${r.reason})'}',
                      footer: StatusChip(r.outcome.toUpperCase(),
                          tone: r.outcome == 'conflict' ? StatusTone.bad : StatusTone.neutral),
                      trailing: [
                        // Moving / returning wait for a decision (the import never applies them).
                        if ((r.outcome == 'moving' || r.outcome == 'returning') && t.sectionId == null)
                          const Tooltip(message: 'Import first, then decide', child: Icon(Icons.info_outline)),
                        if (r.outcome == 'moving' && t.sectionId != null)
                          FilledButton.tonal(
                              onPressed: _busy
                                  ? null
                                  : () => _moveHere(
                                      (name: r.name, fromSectionName: r.fromSectionName, enrollmentId: r.enrollmentId!),
                                      t.sectionId!),
                              child: const Text('Move here')),
                        if (r.outcome == 'returning' && t.sectionId != null)
                          FilledButton.tonal(
                              onPressed: _busy
                                  ? null
                                  : () => _restore((
                                        name: r.name,
                                        fromSectionId: r.fromSectionId,
                                        enrollmentId: r.enrollmentId!,
                                        leftOn: r.leftOn,
                                        leftReason: r.leftReason,
                                      ), t),
                              child: const Text('Restore')),
                      ],
                    ),
                  if ((t.wouldMove + t.wouldReturn) > 0 && t.sectionId == null)
                    const NoticeBanner('This section is new: import first, then try the file again to move or restore '
                        'the learners marked moving or returning.', tone: StatusTone.neutral),
                ],
                if (t.missing.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  const Divider(),
                  Text('Not on this SF1 (${t.missing.length})', style: Theme.of(context).textTheme.titleSmall),
                  const Text('Active in this section but missing from the file. Decide each one, or leave them: '
                      'they stay active (Undecided learners lists them).'),
                  for (final m in t.missing)
                    ListRow(
                      leading: LetterBadge(initialOf(m.name)),
                      title: m.name,
                      subtitle: 'LRN ${m.lrn}',
                      trailing: [
                        LeaverDecisionMenu(
                          learner: m,
                          fromSectionId: t.sectionId!,
                          schoolId: null,
                          onDone: () => _run(false),
                        ),
                      ],
                    ),
                ],
              ],
            ),
          LoadView<List<ImportConflict>>(
            where: 'Sf1Import',
            reloadKey: _conflictsReload,
            load: (_) async {
              await sf1.loadPendingConflicts();
              return List.of(sf1.pendingConflicts);
            },
            builder: (context, items, reload) => ListCard(
              title: 'Conflicts to settle (${items.length})',
              trailing: items.isEmpty
                  ? null
                  : PopupMenuButton<String>(
                      tooltip: 'Settle all',
                      onSelected: (a) async {
                        final r = await runAction(context, () => sf1.resolveAll(a), where: 'Sf1Import');
                        if (r != null && context.mounted) {
                          final failed = r.where((x) => x.error != null).length;
                          showNote(context, 'Settled ${r.length - failed}${failed > 0 ? ', $failed failed' : ''}.');
                        }
                        reload();
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'skip', child: Text('Skip all (keep what is saved)')),
                        PopupMenuItem(value: 'update', child: Text('Update all from the workbook')),
                      ],
                    ),
              children: items.isEmpty
                  ? [const EmptyNote('No conflicts waiting.', icon: Icons.task_alt)]
                  : [
                      for (final c in items)
                        ListRow(
                          leading: IconBadge(Icons.warning_amber,
                              background: colors.errorContainer, foreground: colors.onErrorContainer),
                          title: 'LRN ${c.lrn}',
                          subtitle: c.reason,
                          trailing: [
                            TextButton(
                              onPressed: () async {
                                await runAction(context, () => sf1.resolve(c.id!, 'skip'), done: 'Skipped.', where: 'Sf1Import');
                                reload();
                              },
                              child: const Text('Skip'),
                            ),
                            TextButton(
                              onPressed: () async {
                                await runAction(context, () => sf1.resolve(c.id!, 'update'), done: 'Updated.', where: 'Sf1Import');
                                reload();
                              },
                              child: const Text('Update'),
                            ),
                          ],
                        ),
                    ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The import's result, in a good-toned banner.
class _DoneBanner extends StatelessWidget {
  final String text;
  const _DoneBanner(this.text);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(color: colors.tertiary.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(14)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.check_circle_outline, size: 20, color: colors.tertiary),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Import done', style: theme.textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(text),
          ]),
        ),
      ]),
    );
  }
}
