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
          FilePathField(controller: _path, label: 'Filled CRLA2 scoresheet (.xlsx)'),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: _again,
            onChanged: (v) => setState(() => _again = v ?? false),
            title: const Text('Import again for learners already assessed this round (a new attempt)'),
          ),
          Wrap(spacing: 12, runSpacing: 8, children: [
            OutlinedButton(onPressed: _busy ? null : () => _run(false), child: const Text('Preview')),
            FilledButton(onPressed: _busy || p == null ? null : () => _run(true), child: const Text('Import')),
          ]),
          if (_done != null) SectionCard(title: 'Import done', children: [SelectableText(_done!)]),
          if (p != null)
            SectionCard(
              title: '${p.section} · ${p.round.label}',
              children: [
                for (final w in p.warnings) Text('Note: $w'),
                InfoRow('To import', '${p.count(CrlaImportOutcome.import)}'),
                InfoRow('Already assessed', '${p.count(CrlaImportOutcome.alreadyAssessed)}'),
                InfoRow('With problems', '${p.count(CrlaImportOutcome.error)}'),
                const Divider(),
                for (final r in p.rows)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(switch (r.outcome) {
                      CrlaImportOutcome.import => Icons.check,
                      CrlaImportOutcome.alreadyAssessed => Icons.repeat,
                      CrlaImportOutcome.error => Icons.error_outline,
                    }),
                    title: Text('${r.row.sheet} row ${r.row.rowNo}: ${r.row.name ?? '?'} (${r.row.variant})'),
                    subtitle: r.problems.isEmpty ? null : Text(r.problems.join('; ')),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}
