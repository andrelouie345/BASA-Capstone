// lib/core/console/commands/phil_iri_import_admin_commands.dart
//
// Admin build only (wholly admin, listed in tool/check_tutor_imports.dart):
// the Phil-IRI import (spec docs/superpowers/specs/2026-11-09-phil-iri-import-design.md,
// plan Task 11). One action per command; everything goes through
// PhilIriImportViewModel.
//
// A console can't keep the preview a coordinator saw, so a preview prints a
// confirm code (the start of its fingerprint) and an import needs
// `confirm=<code>`: the command rebuilds the preview with the same options
// and refuses when the code no longer matches (the data changed). Learner
// names are masked to initials in every line.

import 'dart:io';

import '../console_command.dart';
import '../console_registry.dart';
import '../../../viewmodels/auth_viewmodel.dart';
import '../../../viewmodels/phil_iri_import_viewmodel.dart';
import '../../models/phil_iri_assessment.dart' show PhilIriRound;
import '../../models/student.dart';

class _Usage implements Exception {
  final String message;
  const _Usage(this.message);
}

const _codeLength = 12;

String _code(PhilIriImportPreview p) => p.fingerprint.substring(0, _codeLength);

/// "Last, First M." -> "L.F.M." (letters only; nothing when there is no name).
String _initials(String? name) {
  if (name == null) return '?';
  final words = name.split(RegExp(r'[^A-Za-z0-9]+')).where((w) => w.isNotEmpty);
  final s = words.map((w) => '${w[0].toUpperCase()}.').join();
  return s.isEmpty ? '?' : s;
}

String _student(Student s) => '${s.id} ${_initials('${s.lastName} ${s.firstName} ${s.middleName ?? ''}')}';

Future<List<int>> _bytes(String path) async {
  final file = File(path);
  if (!await file.exists()) throw _Usage('No file "$path".');
  return file.readAsBytes();
}

int _int(String s, String what, String usage) =>
    int.tryParse(s) ?? (throw _Usage('Invalid $what: "$s"\n$usage'));

/// `key=value` options after the positional arguments.
Map<String, String> _options(List<String> args, Set<String> allowed, String usage) {
  final out = <String, String>{};
  for (final a in args) {
    final i = a.indexOf('=');
    final key = i < 0 ? a : a.substring(0, i).toLowerCase();
    if (i < 0 || !allowed.contains(key)) throw _Usage('Unknown option "$a".\n$usage');
    if (out.containsKey(key)) throw _Usage('$key given twice.\n$usage');
    out[key] = a.substring(i + 1);
  }
  return out;
}

List<String> _list(String s) => s.split(',').map((x) => x.trim()).where((x) => x.isNotEmpty).toList();

/// `picks=03:17=4512,...` -> {'sheet 03, row 17': 4512}.
Map<String, int> _picks(String? s, String usage) {
  final out = <String, int>{};
  for (final p in _list(s ?? '')) {
    final m = RegExp(r'^(.+):(\d+)=(\d+)$').firstMatch(p);
    if (m == null) throw _Usage('Invalid pick "$p" (sheet:row=studentId).\n$usage');
    out['sheet ${m[1]}, row ${m[2]}'] = int.parse(m[3]!);
  }
  return out;
}

/// `dates=bosy:2026-08-14,mosy1:2026-11-20`.
Map<PhilIriRound, String> _dates(String? s, String usage) {
  final out = <PhilIriRound, String>{};
  for (final d in _list(s ?? '')) {
    final i = d.indexOf(':');
    final round = i < 0 ? null : PhilIriRound.values.where((r) => r.name == d.substring(0, i).toLowerCase()).firstOrNull;
    if (round == null) throw _Usage('Invalid date "$d" (bosy|mosy1|mosy2|mosy3|eosy:YYYY-MM-DD).\n$usage');
    out[round] = d.substring(i + 1);
  }
  return out;
}

String _row(PhilIriImportRow r) {
  final what = switch (r.outcome) {
    PhilIriImportOutcome.import => 'IMPORT',
    PhilIriImportOutcome.importFlagged => 'FLAG ${r.notes.join('; ')}',
    PhilIriImportOutcome.skipped => 'SKIP ${r.notes.join('; ')}',
  };
  final where = 'sheet ${r.ref.sheet} row ${r.ref.row}';
  final learner = [
    if (r.learner.lrn != null) 'LRN ${r.learner.lrn}' else _initials(r.learner.name),
    if (r.student != null) '-> ${_student(r.student!)}',
  ].join(' ');
  final item = r.gst != null
      ? 'GST ${r.gst!.score}${r.gst!.max == null ? '' : '/${r.gst!.max}'}'
      : [
          r.round?.label ?? '',
          if (r.passage != null)
            'G${r.passage!.level ?? '?'} ${r.passage!.title}'
          else if (r.reading?.passage != null)
            r.reading!.passage!.raw
          else if (r.reading != null)
            'Untitled',
          if (r.basaProfile != null) 'BASA profile ${r.basaProfile}',
        ].where((x) => x.isNotEmpty).join(' | ');
  final candidates = r.candidates.isEmpty ? '' : ' | candidates: ${r.candidates.map(_student).join(', ')}';
  return '  $what | $where | $learner | $item$candidates';
}

String _kb(int bytes) => '${(bytes / 1024).ceil()} KB';

String _preview(PhilIriImportPreview p, int maxBytes) {
  final lines = <String>[];
  if (p.headerIssues.isNotEmpty) {
    lines.add('Header issues (nothing read; change a label with phil-iri-import-headers-set):');
    for (final h in p.headerIssues) {
      lines.add('  ${h.field} not found in ${h.block}; headers there: ${h.found.join(' | ')}');
    }
    return lines.join('\n');
  }
  for (final s in p.sections) {
    final sec = s.section;
    lines.add('Sheet ${s.ref.sheet}: ${s.status}'
        '${sec == null ? '' : ' -> section ${sec.id} (Grade ${sec.gradeLevel} ${sec.sectionName}, ${sec.schoolYear})'}'
        '${s.rows.isEmpty ? '' : ' | ${s.count(PhilIriImportOutcome.import)} import, '
            '${s.count(PhilIriImportOutcome.importFlagged)} flagged, ${s.count(PhilIriImportOutcome.skipped)} skipped'
            ' | upload ${_kb(s.uploadBytes)}'}');
    for (final n in s.notes) {
      lines.add('  Note: $n');
    }
    lines.addAll(s.rows.map(_row));
  }
  for (final pr in p.plan.problems) {
    lines.add('Unreadable: $pr');
  }
  final dates = p.proposedDates.entries.toList();
  if (dates.isNotEmpty) {
    lines.add('Dates: ${dates.map((e) => '${e.key.name} ${e.value ?? '(none: give dates=)'}').join(', ')}');
  }
  final total = p.sections.fold<int>(0, (a, s) => a + s.uploadBytes);
  lines.add('upload ≈ ${_kb(total)} + unsent ${_kb(p.unsentBytes)} of ${_kb(maxBytes)}');
  if (p.plan.source.name == 'workbook') lines.add('Warning: ${p.oneTimeWarning}');
  lines.add('confirm code: ${_code(p)}');
  return lines.join('\n');
}

String _result(PhilIriImportResult r) => [
      'Imported ${r.sessionIds.length} session(s)${r.sessionIds.isEmpty ? '' : ': ids ${r.sessionIds.join(', ')}'}; '
          '${r.gstIds.length} GST result(s)${r.gstIds.isEmpty ? '' : ': ids ${r.gstIds.join(', ')}'}',
      ...r.failed.entries.map((e) => 'FAILED ${e.key}: ${e.value}'),
      ...r.nothingToImport.map((s) => 'Nothing to import: $s'),
      'Nothing is uploaded yet: run sync-upload.',
    ].join('\n');

void registerPhilIriImportCommands(ConsoleRegistry registry, AuthViewModel authVm, PhilIriImportViewModel vm) {
  void add(String name, String description, Future<String> Function(List<String> args) handler) {
    registry.register(ConsoleCommand(
      name: name,
      description: description,
      handler: (args) async {
        final guardError = authVm.requireActiveSession();
        if (guardError != null) return guardError;
        try {
          return await handler(args);
        } on _Usage catch (e) {
          return e.message;
        } catch (e) {
          return '$name failed: $e';
        }
      },
    ));
  }

  /// The confirm code check shared by both imports.
  void confirm(PhilIriImportPreview p, String? given, String usage) {
    if (given == null || given.isEmpty) throw _Usage('Give confirm=<code> from the preview.\n$usage');
    if (given.toLowerCase() != _code(p)) throw _Usage(PhilIriImportViewModel.staleMessage);
  }

  add('phil-iri-import-template',
      'phil-iri-import-template <sectionId> <out.xlsx> — write the section\'s Phil-IRI scoresheet file', (args) async {
    const usage = 'Usage: phil-iri-import-template <sectionId> <out.xlsx>';
    if (args.length != 2) throw const _Usage(usage);
    final bytes = await vm.scoresheetTemplate(_int(args[0], 'sectionId', usage));
    await File(args[1]).writeAsBytes(bytes);
    return 'Wrote ${args[1]} (${bytes.length} bytes).';
  });

  add('phil-iri-import-headers', 'phil-iri-import-headers — the header labels the import looks for on this device',
      (args) async {
    if (args.isNotEmpty) throw const _Usage('Usage: phil-iri-import-headers');
    final labels = await vm.headerLabels();
    return labels.entries.map((e) => '${e.key}: ${e.value}').join('\n');
  });

  add('phil-iri-import-headers-set',
      'phil-iri-import-headers-set <field> <label> — change one header label on this device', (args) async {
    const usage = 'Usage: phil-iri-import-headers-set <field> <label>';
    if (args.length < 2) throw const _Usage(usage);
    final label = args.skip(1).join(' ');
    final error = await vm.setHeader(args[0], label);
    return error ?? 'Saved: ${args[0]} = $label';
  });

  add('phil-iri-import-headers-reset', 'phil-iri-import-headers-reset — back to BASA\'s default header labels',
      (args) async {
    if (args.isNotEmpty) throw const _Usage('Usage: phil-iri-import-headers-reset');
    await vm.resetHeaders();
    return 'Header labels reset to the defaults.';
  });

  add('phil-iri-import-header-samples',
      'phil-iri-import-header-samples <file.xlsx> <field> <label> — the first values under that header (names are '
          'never shown)', (args) async {
    const usage = 'Usage: phil-iri-import-header-samples <file.xlsx> <field> <label>';
    if (args.length < 3) throw const _Usage(usage);
    final samples = await vm.headerSamples(await _bytes(args[0]), args[1], args.skip(2).join(' '));
    return samples.isEmpty ? 'No values under that header.' : samples.join('\n');
  });

  const wbPreviewUsage =
      'Usage: phil-iri-import-workbook-preview <file.xlsx> [picks=<sheet>:<row>=<studentId>,...] [dates=bosy:YYYY-MM-DD,...]';
  add('phil-iri-import-workbook-preview',
      'phil-iri-import-workbook-preview <file.xlsx> [picks=...] [dates=...] — check a Phil-IRI/ARAL workbook '
          '(nothing is written)', (args) async {
    if (args.isEmpty) throw const _Usage(wbPreviewUsage);
    final o = _options(args.skip(1).toList(), {'picks', 'dates'}, wbPreviewUsage);
    final choices = PhilIriImportChoices(picks: _picks(o['picks'], wbPreviewUsage), dates: _dates(o['dates'], wbPreviewUsage));
    return _preview(await vm.previewWorkbook(await _bytes(args[0]), choices: choices), vm.maxUploadBytes);
  });

  const wbUsage = 'Usage: phil-iri-import-workbook <file.xlsx> sections=<sheet>,... confirm=<code> '
      '[picks=<sheet>:<row>=<studentId>,...] [dates=bosy:YYYY-MM-DD,...]';
  add('phil-iri-import-workbook',
      'phil-iri-import-workbook <file.xlsx> sections=... confirm=<code> [picks=...] [dates=...] — import the ticked '
          'sections (once per section and school year)', (args) async {
    if (args.isEmpty) throw const _Usage(wbUsage);
    final o = _options(args.skip(1).toList(), {'sections', 'confirm', 'picks', 'dates'}, wbUsage);
    final sheets = _list(o['sections'] ?? '').toSet();
    if (sheets.isEmpty) throw const _Usage('Give sections=<sheet>,...\n$wbUsage');
    final bytes = await _bytes(args[0]);
    final choices = PhilIriImportChoices(
        sheets: sheets, picks: _picks(o['picks'], wbUsage), dates: _dates(o['dates'], wbUsage));
    final preview = await vm.previewWorkbook(bytes, choices: choices);
    confirm(preview, o['confirm'], wbUsage);
    return _result(await vm.importWorkbook(bytes, choices, fingerprint: preview.fingerprint));
  });

  const ssPreviewUsage = 'Usage: phil-iri-import-scoresheet-preview <sectionId> <file.xlsx>';
  add('phil-iri-import-scoresheet-preview',
      'phil-iri-import-scoresheet-preview <sectionId> <file.xlsx> — check a filled BASA Phil-IRI scoresheet '
          '(nothing is written)', (args) async {
    if (args.length != 2) throw const _Usage(ssPreviewUsage);
    final sectionId = _int(args[0], 'sectionId', ssPreviewUsage);
    final preview = await vm.previewScoresheet(sectionId, await _bytes(args[1]), args[1]);
    return _preview(preview, vm.maxUploadBytes);
  });

  const ssUsage = 'Usage: phil-iri-import-scoresheet <sectionId> <file.xlsx> confirm=<code>';
  add('phil-iri-import-scoresheet',
      'phil-iri-import-scoresheet <sectionId> <file.xlsx> confirm=<code> — import a filled BASA Phil-IRI scoresheet '
          '(what BASA has is skipped)', (args) async {
    if (args.length < 2) throw const _Usage(ssUsage);
    final sectionId = _int(args[0], 'sectionId', ssUsage);
    final o = _options(args.skip(2).toList(), {'confirm'}, ssUsage);
    final bytes = await _bytes(args[1]);
    final preview = await vm.previewScoresheet(sectionId, bytes, args[1]);
    confirm(preview, o['confirm'], ssUsage);
    return _result(await vm.importScoresheet(sectionId, bytes, args[1], fingerprint: preview.fingerprint));
  });
}
