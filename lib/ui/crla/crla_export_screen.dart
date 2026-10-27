// lib/ui/crla/crla_export_screen.dart
// Scoresheet export (docs/handoff/screens/crla.md): fills the blank DepEd
// CRLA2 scoresheet of the section's grade with a round's results and saves
// the filled workbook in the export folder. The template is a file on this
// device.
import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/models/crla_assessment.dart';
import '../../core/models/section.dart';
import '../common/pickers.dart';
import '../common/screen_kit.dart';

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
  String? _summary;

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
        _summary = [
          'Saved to $out',
          '${e.learners} learner(s).',
          for (final v in e.resultsByVariant.entries) '${v.key}: ${v.value} with a result',
          ...e.notes,
        ].join('\n');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scoresheet export')),
      body: PageBody(
        maxWidth: 640,
        children: [
          SectionPicker(
            value: _section,
            onChanged: (s) => setState(() => _section = s),
            where: (s) => const {'1', '2', '3'}.contains(s.gradeLevel),
          ),
          CrlaRoundPicker(value: _round, onChanged: (r) => setState(() => _round = r ?? _round)),
          FilePathField(controller: _template, label: 'Blank CRLA2 template (.xlsx) for this grade'),
          TextField(controller: _teacher, decoration: const InputDecoration(labelText: 'Teacher (optional)')),
          FilledButton.icon(
            onPressed: _busy ? null : _export,
            icon: const Icon(Icons.file_download),
            label: const Text('Fill and save'),
          ),
          if (_summary != null) SectionCard(title: 'Done', children: [SelectableText(_summary!)]),
        ],
      ),
    );
  }
}
