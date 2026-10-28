// lib/ui/crla/crla_export_screen.dart
// Scoresheet export (docs/handoff/screens/crla.md): fills the blank DepEd
// CRLA2 scoresheet of the section's grade with a round's results and saves
// the filled workbook in the export folder. The template is a file on this
// device.
import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/models/crla_assessment.dart';
import '../../core/models/section.dart';
import '../../viewmodels/crla_export_viewmodel.dart';
import '../common/pickers.dart';
import '../common/screen_kit.dart';
import 'crla_section_screen.dart';

class CrlaExportScreen extends StatefulWidget {
  const CrlaExportScreen({super.key});

  @override
  State<CrlaExportScreen> createState() => _CrlaExportScreenState();
}

class _CrlaExportScreenState extends State<CrlaExportScreen> {
  final _template = TextEditingController();
  final _teacher = TextEditingController();
  Section? _section;
  CrlaRound _round = CrlaRound.values.first;
  bool _busy = false;

  /// The last export (the result card); null before the first one.
  CrlaScoresheetExport? _done;
  String? _savedTo;

  @override
  void dispose() {
    _template.dispose();
    _teacher.dispose();
    super.dispose();
  }

  Future<void> _export() async {
    final section = _section;
    final path = _template.text.trim();
    if (section == null || path.isEmpty) return showNote(context, 'Pick a section and give the template file.');
    final exporter = vmsOf(context).crlaExport;
    final teacher = _teacher.text.trim();
    setState(() => _busy = true);
    final r = await runAction(context, () async {
      final bytes = await File(path).readAsBytes();
      final e = await exporter.exportScoresheet(section.id!, bytes, round: _round, teacher: teacher.isEmpty ? null : teacher);
      final out = await exportPath('CRLA_${section.gradeLevel}_${section.sectionName}_${_round.name}.xlsx');
      await File(out).writeAsBytes(e.bytes);
      return (e, out);
    }, where: 'CrlaExport');
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (r != null) {
        final (e, out) = r;
        _done = e;
        _savedTo = out;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scoresheet export')),
      body: PageBody(
        maxWidth: 900,
        children: [
          FilterBar(fieldWidth: 260, children: [
            SectionPicker(
              value: _section,
              onChanged: (s) => setState(() => _section = s),
              where: (s) => const {'1', '2', '3'}.contains(s.gradeLevel),
            ),
            CrlaRoundPicker(value: _round, onChanged: (r) => setState(() => _round = r ?? _round)),
            TextField(controller: _teacher, decoration: const InputDecoration(labelText: 'Teacher (optional)')),
          ]),
          SectionCard(
            title: 'Template',
            icon: Icons.table_view_outlined,
            children: [
              FilePathField(controller: _template, label: 'Blank CRLA2 template (.xlsx) for this grade'),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  onPressed: _busy ? null : _export,
                  icon: _busy
                      ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.file_download),
                  label: const Text('Fill and save'),
                ),
              ),
            ],
          ),
          if (_done != null) _DoneCard(export: _done!, savedTo: _savedTo!),
        ],
      ),
    );
  }
}

/// The saved file, learner counts per test and the exporter's notes.
class _DoneCard extends StatelessWidget {
  final CrlaScoresheetExport export;
  final String savedTo;
  const _DoneCard({required this.export, required this.savedTo});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SectionCard(
      title: 'Done',
      icon: Icons.task_alt,
      trailing: const StatusChip('Saved', tone: StatusTone.good),
      children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.folder_outlined, size: 18, color: colors.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(child: SelectableText('Saved to $savedTo')),
        ]),
        const SizedBox(height: 12),
        StatGrid(tileWidth: 150, tiles: [
          StatTile(label: 'Learners', value: '${export.learners}', icon: Icons.people_alt_outlined),
          for (final v in export.resultsByVariant.entries)
            StatTile(label: '${crlaVariantLabel(v.key)}: with a result', value: '${v.value}', icon: Icons.fact_check_outlined),
        ]),
        for (final n in export.notes) ...[const SizedBox(height: 8), NoticeBanner(n)],
      ],
    );
  }
}
