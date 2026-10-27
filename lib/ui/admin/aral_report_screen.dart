// lib/ui/admin/aral_report_screen.dart
// Implementation report and roster files (docs/handoff/screens/aral.md),
// with the check-in report (Check-ins, admin part): the ARAL implementation
// report as a table, CSV or filled template; the roster CSV; the check-in
// report CSV; and a roster import (preview, then import). Admin build only.
import 'dart:io';

import 'package:flutter/material.dart';

import '../../viewmodels/aral_roster_import_viewmodel.dart';
import '../common/csv_table.dart';
import '../common/screen_kit.dart';
import '../common/school_year_scope.dart';
import 'admin_scope.dart';

class AralReportScreen extends StatelessWidget {
  const AralReportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ARAL reports and files')),
      body: PageBody(
        maxWidth: 1200,
        children: [
          SchoolYearScope(builder: (context, schoolId, year) => _Body(schoolId: schoolId, year: year)),
        ],
      ),
    );
  }
}

class _Body extends StatefulWidget {
  final int schoolId;
  final String year;
  const _Body({required this.schoolId, required this.year});

  @override
  State<_Body> createState() => _BodyState();
}

class _BodyState extends State<_Body> {
  final _template = TextEditingController();
  final _rosterFile = TextEditingController();
  AralRosterImportPreview? _preview;
  String? _imported;

  @override
  void dispose() {
    _template.dispose();
    _rosterFile.dispose();
    super.dispose();
  }

  Future<void> _xlsx() async {
    final path = _template.text.trim();
    if (path.isEmpty) return showNote(context, 'Give the report template file first.');
    final report = AdminScope.of(context).aralReport;
    final r = await runAction(context, () async {
      final (bytes, notes) =
          await report.implementationReportXlsx(template: await File(path).readAsBytes(), schoolId: widget.schoolId, schoolYear: widget.year);
      final out = await exportPath('ARAL_implementation_${widget.year}.xlsx');
      await File(out).writeAsBytes(bytes);
      return [out, ...notes].join('\n');
    }, where: 'AralReport');
    if (r != null && mounted) await showTextDialog(context, title: 'Saved', text: r);
  }

  Future<void> _saveCsv(String name, Future<String> Function() make) async {
    final path = await runAction(context, () async => saveTextExport(name, await make()), where: 'AralReport');
    if (path != null && mounted) await showSaved(context, path);
  }

  Future<void> _roster(bool real) async {
    final path = _rosterFile.text.trim();
    if (path.isEmpty) return showNote(context, 'Give the roster file first.');
    final vm = AdminScope.of(context).aralRosterImport;
    final name = path.split(RegExp(r'[\\/]')).last;
    if (real) {
      final r = await runAction(context, () async => vm.importRoster(widget.schoolId, widget.year, await File(path).readAsBytes(), name),
          where: 'AralRosterImport');
      if (r != null && mounted) {
        setState(() {
          _preview = r.preview;
          _imported = [
            'Added ${r.added.length} learner(s).',
            for (final e in r.warnings.entries) 'Row ${e.key.rowNo} ${e.key.name}: ${e.value}',
            for (final e in r.failed.entries) 'Failed row ${e.key.rowNo} ${e.key.name}: ${e.value}',
          ].join('\n');
        });
      }
    } else {
      final p = await runAction(context, () async => vm.preview(widget.schoolId, widget.year, await File(path).readAsBytes(), name),
          where: 'AralRosterImport');
      if (p != null && mounted) {
        setState(() {
          _preview = p;
          _imported = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final admin = AdminScope.of(context);
    final vms = vmsOf(context);
    final p = _preview;
    final id = widget.schoolId, year = widget.year;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LoadView<String>(
          where: 'AralReport',
          reloadKey: '$id-$year',
          load: (_) => admin.aralReport.implementationReportCsv(schoolId: id, schoolYear: year),
          builder: (context, csv, _) => CsvTableView(csv: csv, fileName: 'ARAL_implementation_$year.csv', title: 'Implementation report'),
        ),
        const SizedBox(height: 12),
        SectionCard(title: 'Files', children: [
          FilePathField(controller: _template, label: 'Implementation report template (.xlsx)'),
          const SizedBox(height: 8),
          Wrap(spacing: 12, runSpacing: 8, children: [
            FilledButton.icon(onPressed: _xlsx, icon: const Icon(Icons.table_view), label: const Text('Fill the template')),
            OutlinedButton.icon(
              onPressed: () => _saveCsv('ARAL_roster_$year.csv', () => vms.aral.rosterCsv(schoolId: id, schoolYear: year)),
              icon: const Icon(Icons.download),
              label: const Text('Roster CSV'),
            ),
            OutlinedButton.icon(
              onPressed: () => _saveCsv('ARAL_checkins_$year.csv', () => vms.aralCheckin.checkinReportCsv(schoolId: id, schoolYear: year)),
              icon: const Icon(Icons.download),
              label: const Text('Check-in report CSV'),
            ),
          ]),
        ]),
        const SizedBox(height: 12),
        SectionCard(title: 'Roster import', children: [
          FilePathField(controller: _rosterFile, label: 'Roster file (.csv or .xlsx)'),
          const SizedBox(height: 8),
          Wrap(spacing: 12, children: [
            OutlinedButton(onPressed: () => _roster(false), child: const Text('Preview')),
            FilledButton(onPressed: p == null ? null : () => _roster(true), child: const Text('Import')),
          ]),
          if (_imported != null) Padding(padding: const EdgeInsets.only(top: 8), child: SelectableText(_imported!)),
          if (p != null) ...[
            for (final n in p.notes) Text('Note: $n'),
            for (final o in AralRosterImportOutcome.values) InfoRow(o.name, '${p.count(o)}'),
            for (final r in p.rows.where((r) => r.problems.isNotEmpty))
              Text('Row ${r.rowNo} ${r.name}: ${r.problems.join('; ')}'),
          ],
        ]),
      ],
    );
  }
}
