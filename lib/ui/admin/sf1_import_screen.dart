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
        _imported = 'Imported: ${r.inserted} new learner(s), ${r.alreadyEnrolled} already enrolled, '
            '${r.conflicts} conflict(s), ${r.skippedBlankOrTotal} blank or total row(s) skipped.';
        _conflictsReload++;
      }
    } else {
      final t = await runAction(context, () => sf1.trial(path), where: 'Sf1Import');
      if (t != null) _trial = t;
    }
    if (mounted) setState(() => _busy = false);
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('SF1 import'),
        actions: [
          IconButton(tooltip: 'Column map', onPressed: () => _editMap(sf1.columnMap), icon: const Icon(Icons.view_column)),
        ],
      ),
      body: PageBody(
        children: [
          FilePathField(controller: _path, label: 'SF1 workbook (.xls or .xlsx)'),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: _busy ? null : () => _run(false),
                icon: const Icon(Icons.science_outlined),
                label: const Text('Try it (nothing is saved)'),
              ),
              FilledButton.icon(
                onPressed: _busy ? null : () => _run(true),
                icon: const Icon(Icons.upload_file),
                label: const Text('Import'),
              ),
              if (_busy) const SizedBox.square(dimension: 24, child: CircularProgressIndicator(strokeWidth: 2)),
            ],
          ),
          if (_imported != null) SectionCard(title: 'Import done', children: [Text(_imported!)]),
          if (t != null)
            SectionCard(
              title: 'Trial: Grade ${t.gradeLevel} ${t.sectionName} (${t.schoolYear})',
              children: [
                InfoRow('School', '${t.schoolName} (${t.schoolIdCode})'),
                InfoRow('Region', t.regionError ?? t.rawRegion ?? '—'),
                InfoRow('Would add', '${t.wouldInsert} learner(s)'),
                InfoRow('Conflicts', '${t.wouldConflict}'),
                InfoRow('Already enrolled', '${t.alreadyEnrolled}'),
                InfoRow('Skipped', '${t.wouldSkip}'),
                const Divider(),
                for (final r in t.rows.where((r) => r.outcome != 'insert'))
                  Text('Row ${r.rowIndex + 1}: ${r.name} ${r.lrn ?? ''} — ${r.outcome}${r.reason == null ? '' : ' (${r.reason})'}'),
              ],
            ),
          LoadView<List<ImportConflict>>(
            where: 'Sf1Import',
            reloadKey: _conflictsReload,
            load: (_) async {
              await sf1.loadPendingConflicts();
              return List.of(sf1.pendingConflicts);
            },
            builder: (context, items, reload) => SectionCard(
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
                  ? [const Text('No conflicts waiting.')]
                  : [
                      for (final c in items)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text('LRN ${c.lrn}'),
                          subtitle: Text(c.reason),
                          trailing: Wrap(spacing: 4, children: [
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
                          ]),
                        ),
                    ],
            ),
          ),
        ],
      ),
    );
  }
}
