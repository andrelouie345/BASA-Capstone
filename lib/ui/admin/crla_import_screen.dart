// lib/ui/admin/crla_import_screen.dart
// Scoresheet import (docs/handoff/screens/crla.md): read a filled CRLA2
// scoresheet into a section's assessments: preview first (what would be
// imported, already assessed, or wrong), then import. Admin build only.
import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/models/crla_assessment.dart';
import '../../core/models/section.dart';
import '../../viewmodels/crla_import_viewmodel.dart';
import '../common/pickers.dart';
import '../common/screen_kit.dart';
import 'admin_scope.dart';

class CrlaImportScreen extends StatefulWidget {
  const CrlaImportScreen({super.key});

  @override
  State<CrlaImportScreen> createState() => _CrlaImportScreenState();
}

class _CrlaImportScreenState extends State<CrlaImportScreen> {
  final _path = TextEditingController();
  Section? _section;
  CrlaRound? _round;
  bool _again = false;
  bool _busy = false;
  CrlaImportPreview? _preview;
  String? _done;

  @override
  void dispose() {
    _path.dispose();
    super.dispose();
  }

  Future<void> _run(bool real) async {
    final section = _section;
    final path = _path.text.trim();
    if (section == null || path.isEmpty) return showNote(context, 'Pick a section and give the scoresheet file.');
    final vm = AdminScope.of(context).crlaImport;
    setState(() => _busy = true);
    if (real) {
      final r = await runAction(context, () async {
        return vm.importScoresheet(section.id!, await File(path).readAsBytes(), round: _round, again: _again);
      }, where: 'CrlaImport');
      if (r != null) {
        _preview = r.preview;
        _done = 'Imported ${r.assessmentIds.length} assessment(s).'
            '${r.failed.isEmpty ? '' : '\nFailed: ${r.failed.entries.map((e) => '${e.key.row.name ?? e.key.row.lrn}: ${e.value}').join('; ')}'}';
      }
    } else {
      final p = await runAction(context, () async {
        return vm.preview(section.id!, await File(path).readAsBytes(), round: _round, again: _again);
      }, where: 'CrlaImport');
      if (p != null) {
        _preview = p;
        _done = null;
      }
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final p = _preview;
    return Scaffold(
      appBar: AppBar(title: const Text('Scoresheet import')),
      body: PageBody(
        children: [
          SectionCard(
            title: 'Scoresheet',
            icon: Icons.upload_file_outlined,
            children: [
              FilterBar(fieldWidth: 280, children: [
                SectionPicker(
                  value: _section,
                  onChanged: (s) => setState(() => _section = s),
                  where: (s) => const {'1', '2', '3'}.contains(s.gradeLevel),
                ),
                BasaDropdown<CrlaRound>(
                  label: 'Round (empty = from the scoresheet)',
                  items: CrlaRound.values,
                  value: _round,
                  allowNone: true,
                  hint: 'From the scoresheet',
                  itemLabel: (r) => r.label,
                  onChanged: (r) => setState(() => _round = r),
                ),
              ]),
              const SizedBox(height: 12),
              FilePathField(controller: _path, label: 'Filled CRLA2 scoresheet (.xlsx)'),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _again,
                onChanged: (v) => setState(() => _again = v ?? false),
                title: const Text('Import again for learners already assessed this round (a new attempt)'),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: Wrap(spacing: 12, runSpacing: 8, children: [
                  OutlinedButton.icon(
                    onPressed: _busy ? null : () => _run(false),
                    icon: const Icon(Icons.visibility_outlined),
                    label: const Text('Preview'),
                  ),
                  FilledButton.icon(
                    onPressed: _busy || p == null ? null : () => _run(true),
                    icon: const Icon(Icons.download_done),
                    label: const Text('Import'),
                  ),
                ]),
              ),
            ],
          ),
          if (_done != null)
            SectionCard(
              title: 'Import done',
              icon: Icons.task_alt,
              trailing: const StatusChip('Done', tone: StatusTone.good),
              children: [SelectableText(_done!)],
            ),
          if (p != null) ...[
            Text('${p.section} · ${p.round.label}', style: Theme.of(context).textTheme.titleMedium),
            for (final w in p.warnings) NoticeBanner('Note: $w'),
            StatGrid(tileWidth: 170, tiles: [
              StatTile(label: 'To import', value: '${p.count(CrlaImportOutcome.import)}', icon: Icons.check_rounded),
              StatTile(
                label: 'Already assessed',
                value: '${p.count(CrlaImportOutcome.alreadyAssessed)}',
                icon: Icons.repeat,
              ),
              StatTile(label: 'With problems', value: '${p.count(CrlaImportOutcome.error)}', icon: Icons.error_outline),
            ]),
            if (p.rows.isNotEmpty)
              ListCard(children: [
                for (final r in p.rows) _PreviewRow(row: r),
              ]),
          ],
        ],
      ),
    );
  }
}

/// One scoresheet row of the preview: its outcome as a coloured badge and chip.
class _PreviewRow extends StatelessWidget {
  final CrlaImportRow row;
  const _PreviewRow({required this.row});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final r = row;
    final (icon, tone, label) = switch (r.outcome) {
      CrlaImportOutcome.import => (Icons.check_rounded, StatusTone.good, 'To import'),
      CrlaImportOutcome.alreadyAssessed => (Icons.repeat, StatusTone.warn, 'Already assessed'),
      CrlaImportOutcome.error => (Icons.error_outline, StatusTone.bad, 'Problem'),
    };
    final accent = switch (tone) {
      StatusTone.good => colors.tertiary,
      StatusTone.warn => colors.secondary,
      _ => colors.error,
    };
    return ListRow(
      leading: IconBadge(icon, size: 36, background: accent.withValues(alpha: 0.14), foreground: accent),
      title: '${r.row.sheet} row ${r.row.rowNo}: ${r.row.name ?? '?'} (${r.row.variant})',
      subtitle: r.problems.isEmpty ? null : r.problems.join('; '),
      footer: StatusChip(label, tone: tone),
    );
  }
}
