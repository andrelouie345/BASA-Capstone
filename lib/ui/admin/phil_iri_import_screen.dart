// lib/ui/admin/phil_iri_import_screen.dart
// Phil-IRI import (docs/handoff/screens/phil-iri-import.md): ma's VNHS ARAL
// workbook (one sheet per section, imported once per section and year) or a
// BASA scoresheet file (one section, repeatable), plus the scoresheet
// template per section. Preview first (search and filter it; tick sections,
// pick learners, give round dates), then import; nothing is uploaded until
// the coordinator sends their work. Admin build only.
import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/models/phil_iri_assessment.dart';
import '../../core/models/section.dart';
import '../../core/models/student.dart';
import '../../viewmodels/phil_iri_import_viewmodel.dart';
import '../../viewmodels/viewmodel_exception.dart';
import '../common/pickers.dart';
import '../common/screen_kit.dart';
import '../sync/upload_screen.dart';
import 'admin_scope.dart';
import 'phil_iri_import_preview.dart';

/// The workbook versions this import was checked against (owner 2026-11-12:
/// a fixed label; change it when ma's workbook gets a new version).
const philIriWorkbookLabel = 'VNHS ARAL workbook (v26.0531–v26.1130)';

class PhilIriImportScreen extends StatefulWidget {
  /// Opens in Scoresheet mode (the hub's template tile).
  final bool scoresheet;
  const PhilIriImportScreen({super.key, this.scoresheet = false});

  @override
  State<PhilIriImportScreen> createState() => _PhilIriImportScreenState();
}

class _PhilIriImportScreenState extends State<PhilIriImportScreen> {
  final _path = TextEditingController();
  late bool _scoresheet = widget.scoresheet;
  Section? _section;
  bool _busy = false;

  // The file of the shown preview, and the coordinator's choices for it.
  List<int>? _bytes;
  String? _previewedPath;
  PhilIriImportPreview? _preview;
  final _sheets = <String>{};
  final _picks = <String, int>{};
  final _dates = <PhilIriRound, String>{};
  final _candidates = <String, List<Student>>{}; // kept: a picked row has none
  Map<String, String> _labels = const {};

  // Search and filter (only what is shown changes).
  String _query = '';
  PreviewShow _show = PreviewShow.all;

  PhilIriImportResult? _result;
  String? _templatePath;

  @override
  void dispose() {
    _path.dispose();
    super.dispose();
  }

  PhilIriImportViewModel get _vm => AdminScope.of(context).philIriImport;

  void _setMode(bool scoresheet) => setState(() {
    _scoresheet = scoresheet;
    _clear();
  });

  void _clear() {
    _bytes = null;
    _previewedPath = null;
    _preview = null;
    _result = null;
    _sheets.clear();
    _picks.clear();
    _dates.clear();
    _candidates.clear();
  }

  PhilIriImportChoices get _choices => PhilIriImportChoices(sheets: {..._sheets}, picks: {..._picks}, dates: {..._dates});

  String get _fileName => _path.text.trim().split(RegExp(r'[\\/]')).last;

  /// Reads the file (again when its path changed) and previews it.
  Future<void> _runPreview({bool reread = false}) async {
    final path = _path.text.trim();
    final section = _section;
    if (path.isEmpty) return showNote(context, 'Give the file.');
    if (_scoresheet && section == null) return showNote(context, 'Pick a section first.');
    final vm = _vm;
    setState(() => _busy = true);
    final p = await runAction(context, () async {
      if (reread || _bytes == null || _previewedPath != path) {
        final bytes = await File(path).readAsBytes();
        if (_previewedPath != path) {
          _clear();
        }
        _bytes = bytes;
        _previewedPath = path;
      }
      return _scoresheet
          ? vm.previewScoresheet(section!.id!, _bytes!, _fileName)
          : vm.previewWorkbook(_bytes!, choices: _choices);
    }, where: 'PhilIriImport');
    if (p != null && p.headerIssues.isNotEmpty && mounted) {
      final labels = await runAction(context, vm.headerLabels, where: 'PhilIriImport');
      if (labels != null) _labels = labels;
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (p != null) {
        _preview = p;
        _result = null;
        for (final s in p.sections) {
          for (final r in s.rows) {
            if (r.candidates.isNotEmpty) _candidates[r.learnerRef] = r.candidates;
          }
        }
        // A sheet that can't be imported any more is unticked.
        _sheets.removeWhere((sheet) =>
            p.sections.where((s) => s.ref.sheet == sheet && s.status == PhilIriImportSectionPreview.importable).isEmpty);
      }
    });
  }

  Future<void> _import() async {
    final p = _preview;
    final bytes = _bytes;
    if (p == null || bytes == null) return;
    final section = _section;
    final vm = _vm;
    setState(() => _busy = true);
    var stale = false;
    final r = await runAction(context, () async {
      try {
        return _scoresheet
            ? await vm.importScoresheet(section!.id!, bytes, _fileName, fingerprint: p.fingerprint)
            : await vm.importWorkbook(bytes, _choices, fingerprint: p.fingerprint);
      } on ViewModelException catch (e) {
        if (e.message == PhilIriImportViewModel.staleMessage) {
          stale = true;
          return null;
        }
        rethrow;
      }
    }, where: 'PhilIriImport');
    if (!mounted) return;
    setState(() => _busy = false);
    if (stale) {
      showNote(context, 'The data changed since the preview. This is the new preview: check it and import again.');
      return _runPreview();
    }
    if (r != null) {
      setState(() {
        _result = r;
        _preview = null;
        _sheets.clear();
      });
    }
  }

  Future<void> _template() async {
    final section = _section;
    if (section == null) return showNote(context, 'Pick a section first.');
    final vm = _vm;
    setState(() => _busy = true);
    final out = await runAction(context, () async {
      final bytes = await vm.scoresheetTemplate(section.id!);
      final out = await exportPath('${section.gradeLevel}_${section.sectionName}_Phil-IRI_scoresheet.xlsx');
      await File(out).writeAsBytes(bytes);
      return out;
    }, where: 'PhilIriImport');
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (out != null) _templatePath = out;
    });
    if (out != null) await showSaved(context, out);
  }

  Future<void> _samples(String field, String header) async {
    final bytes = _bytes;
    if (bytes == null) return;
    final values = await runAction(context, () => _vm.headerSamples(bytes, field, header), where: 'PhilIriImport');
    if (values == null || !mounted) return;
    await showTextDialog(context,
        title: 'Under “$header”', text: values.isEmpty ? 'No values under this header.' : values.join('\n'));
  }

  Future<void> _saveHeaders(Map<String, String> picks) async {
    final vm = _vm;
    for (final e in picks.entries) {
      final error = await runAction(context, () => vm.setHeader(e.key, e.value), where: 'PhilIriImport');
      if (!mounted) return;
      if (error != null) return showNote(context, error);
    }
    await _runPreview();
  }

  Future<void> _headersDialog() async {
    final vm = _vm;
    final labels = await runAction(context, vm.headerLabels, where: 'PhilIriImport');
    if (labels == null || !mounted) return;
    final reset = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Column headers'),
        content: SizedBox(
          width: 480,
          child: ListView(shrinkWrap: true, children: [
            const Text('The headers BASA looks for on this device.'),
            const SizedBox(height: 8),
            for (final e in labels.entries) InfoRow(e.key, e.value),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Reset to defaults')),
          FilledButton(onPressed: () => Navigator.pop(context, false), child: const Text('Close')),
        ],
      ),
    );
    if (reset != true || !mounted) return;
    if (await runStep(context, vm.resetHeaders, done: 'Column headers reset to the defaults.', where: 'PhilIriImport') &&
        _bytes != null) {
      await _runPreview();
    }
  }

  // ---- building ----

  @override
  Widget build(BuildContext context) {
    final p = _preview;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Phil-IRI import'),
        actions: [
          IconButton(tooltip: 'Column headers', onPressed: _busy ? null : _headersDialog, icon: const Icon(Icons.view_column_outlined)),
        ],
      ),
      body: PageBody(
        maxWidth: 1100,
        children: [
          _fileCard(),
          if (_busy) const LinearProgressIndicator(),
          if (_result != null) _resultCard(_result!),
          if (p != null && p.headerIssues.isNotEmpty)
            HeadersStep(
              key: ValueKey(p.fingerprint),
              issues: p.headerIssues,
              labels: _labels,
              onSamples: _samples,
              onSave: _saveHeaders,
            ),
          if (p != null && p.headerIssues.isEmpty) ..._previewParts(p),
        ],
      ),
    );
  }

  Widget _fileCard() {
    final theme = Theme.of(context);
    return SectionCard(
      title: 'File',
      icon: Icons.upload_file_outlined,
      children: [
        Wrap(spacing: 8, runSpacing: 8, children: [
          ChoiceChip(
            label: const Text(philIriWorkbookLabel),
            selected: !_scoresheet,
            onSelected: _busy ? null : (_) => _setMode(false),
          ),
          ChoiceChip(
            label: const Text('Scoresheet file'),
            selected: _scoresheet,
            onSelected: _busy ? null : (_) => _setMode(true),
          ),
        ]),
        const SizedBox(height: 6),
        Text(
          _scoresheet
              ? 'BASA\'s scoresheet for one section, filled from the paper. It can be imported again: what BASA has is skipped.'
              : 'The grade\'s VNHS ARAL workbook, one sheet per section. Each section\'s workbook is imported once.',
          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 12),
        if (_scoresheet) ...[
          FilterBar(fieldWidth: 320, children: [
            SectionPicker(
              value: _section,
              pickFirst: true,
              onChanged: (s) => setState(() {
                _section = s;
                _clear();
              }),
              where: (s) => (int.tryParse(s.gradeLevel) ?? 0) >= 4,
            ),
            OutlinedButton.icon(
              key: const Key('philIriImport.template'),
              onPressed: _busy || _section == null ? null : _template,
              icon: const Icon(Icons.file_download_outlined),
              label: const Text('Download template'),
            ),
          ]),
          if (_templatePath != null) ...[
            const SizedBox(height: 8),
            SelectableText('Template saved to $_templatePath', style: theme.textTheme.bodySmall),
          ],
          const SizedBox(height: 12),
        ],
        TextField(
          key: const Key('philIriImport.path'),
          controller: _path,
          decoration: InputDecoration(
            labelText: _scoresheet ? 'Filled scoresheet file (.xlsx)' : 'VNHS ARAL workbook (.xlsx)',
            hintText: r'e.g. C:\Users\me\Downloads\file.xlsx',
            prefixIcon: const Icon(Icons.insert_drive_file_outlined),
          ),
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerRight,
          child: OutlinedButton.icon(
            key: const Key('philIriImport.preview'),
            onPressed: _busy ? null : () => _runPreview(reread: true),
            icon: const Icon(Icons.visibility_outlined),
            label: const Text('Preview'),
          ),
        ),
      ],
    );
  }

  List<Widget> _previewParts(PhilIriImportPreview p) {
    final theme = Theme.of(context);
    final filtering = _query.trim().isNotEmpty || _show != PreviewShow.all;
    var total = 0, shown = 0;
    final cards = <Widget>[];
    if (_show != PreviewShow.unreadable) {
      for (final s in p.sections) {
        final rows = [
          for (final r in s.rows)
            if (rowShown(r, s, _query, _show)) r,
        ];
        total += s.rows.length;
        shown += rows.length;
        // While filtering, a sheet without a match is hidden (unless its own name matches).
        if (filtering && rows.isEmpty) continue;
        cards.add(SectionPreviewCard(
          key: ValueKey('sheet ${s.ref.sheet}'),
          section: s,
          rows: rows,
          filtering: filtering,
          ticked: _scoresheet ? null : _sheets.contains(s.ref.sheet),
          onTick: (v) => setState(() => v ? _sheets.add(s.ref.sheet) : _sheets.remove(s.ref.sheet)),
          picks: _picks,
          candidates: _candidates,
          onPick: (ref, id) {
            setState(() => id == null ? _picks.remove(ref) : _picks[ref] = id);
            _runPreview();
          },
        ));
      }
    }
    final problems = [
      for (final x in p.plan.problems)
        if (_show == PreviewShow.all || _show == PreviewShow.unreadable)
          if (matchesSearch(_query, [x.ref.toString(), x.message])) x,
    ];
    final ticked = _scoresheet ? p.sections : p.sections.where((s) => _sheets.contains(s.ref.sheet)).toList();
    final bytes = ticked.fold<int>(0, (a, s) => a + s.uploadBytes) + p.unsentBytes;
    final tooBig = bytes > _vm.maxUploadBytes;
    final canImport = !_busy && (_scoresheet || _sheets.isNotEmpty);
    return [
      FilterBar(fieldWidth: 300, children: [
        TextField(
          key: const Key('philIriImport.search'),
          decoration: const InputDecoration(prefixIcon: Icon(Icons.search), labelText: 'Search learner, sheet, passage, notes'),
          onChanged: (q) => setState(() => _query = q),
        ),
        BasaDropdown<PreviewShow>(
          key: const Key('philIriImport.show'),
          label: 'Show',
          items: PreviewShow.values,
          value: _show,
          itemLabel: (s) => s.label,
          onChanged: (s) => setState(() => _show = s ?? PreviewShow.all),
        ),
      ]),
      if (filtering && _show != PreviewShow.unreadable) Text('$shown of $total rows', style: theme.textTheme.bodySmall),
      if (p.sections.isEmpty) const EmptyNote('No section sheet in this file.', icon: Icons.table_chart_outlined),
      ...cards,
      if (problems.isNotEmpty) UnreadableCard(problems: problems),
      if (!_scoresheet) _datesCard(p),
      SectionCard(
        title: 'Import',
        icon: Icons.download_done,
        children: [
          Text(
            'Upload size: ${_kb(bytes - p.unsentBytes)} to import + ${_kb(p.unsentBytes)} not sent yet, '
            'of ${_kb(_vm.maxUploadBytes)} in one upload.',
            style: theme.textTheme.bodySmall,
          ),
          if (tooBig) ...[
            const SizedBox(height: 8),
            const NoticeBanner('Too big for one upload: send your work first, or tick fewer sections.', tone: StatusTone.bad),
          ],
          if (!_scoresheet) ...[
            const SizedBox(height: 8),
            NoticeBanner(p.oneTimeWarning, icon: Icons.lock_outline),
          ],
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              key: const Key('philIriImport.import'),
              onPressed: canImport ? _import : null,
              icon: const Icon(Icons.download_done),
              label: Text(_scoresheet ? 'Import' : 'Import ticked sections (${_sheets.length})'),
            ),
          ),
        ],
      ),
    ];
  }

  /// One date per round the rows need (the GST takes BOSY's).
  Widget _datesCard(PhilIriImportPreview p) {
    final rounds = <PhilIriRound?>{
      for (final s in p.sections)
        for (final r in s.rows)
          if (r.outcome != PhilIriImportOutcome.skipped) r.gst != null ? PhilIriRound.bosy : r.round,
    }.whereType<PhilIriRound>().toList()
      ..sort((a, b) => a.index.compareTo(b.index));
    if (rounds.isEmpty) return const SizedBox.shrink();
    return SectionCard(
      title: 'Round dates',
      icon: Icons.event_outlined,
      children: [
        Text('Every reading of a round gets one date. The GST takes the BOSY date.', style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 8),
        Wrap(spacing: 12, runSpacing: 12, children: [
          for (final round in rounds)
            SizedBox(
              width: 240,
              child: InkWell(
                key: Key('philIriImport.date.${round.name}'),
                onTap: _busy
                    ? null
                    : () async {
                        final d = await pickDate(context, initial: _dates[round] ?? p.proposedDates[round]);
                        if (d == null || !mounted) return;
                        setState(() => _dates[round] = d);
                        await _runPreview();
                      },
                child: InputDecorator(
                  decoration: InputDecoration(labelText: '${round.label} date', prefixIcon: const Icon(Icons.calendar_today_outlined)),
                  child: Text(p.proposedDates[round] ?? 'Pick a date (needed)'),
                ),
              ),
            ),
        ]),
      ],
    );
  }

  Widget _resultCard(PhilIriImportResult r) => SectionCard(
    title: 'Import done',
    icon: Icons.task_alt,
    trailing: const StatusChip('Done', tone: StatusTone.good),
    children: [
      Text('Imported ${r.sessionIds.length} session(s) and ${r.gstIds.length} GST result(s).'),
      for (final e in r.failed.entries) Text('Not imported: ${e.key}: ${e.value}'),
      if (r.nothingToImport.isNotEmpty) Text('Nothing to import in sheet(s) ${r.nothingToImport.join(', ')}.'),
      const SizedBox(height: 12),
      const NoticeBanner('Nothing is uploaded yet. Send your work so the server gets the imported results.'),
      const SizedBox(height: 12),
      Align(
        alignment: Alignment.centerRight,
        child: FilledButton.icon(
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const UploadScreen())),
          icon: const Icon(Icons.cloud_upload_outlined),
          label: const Text('Send my work'),
        ),
      ),
    ],
  );
}

String _kb(int bytes) => bytes < 1024 ? '$bytes B' : '${(bytes / 1024).toStringAsFixed(bytes < 10240 ? 1 : 0)} KB';
