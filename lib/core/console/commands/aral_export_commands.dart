// lib/core/console/commands/aral_export_commands.dart

/// ARAL-Reading exports (IE4): the implementation report into its template
/// and as CSV, the roster and the check-in report as CSV. Admins and
/// coordinators of the school. Paths with spaces go in double quotes.
library;

import 'dart:convert';
import 'dart:io';

import '../console_command.dart';
import '../console_registry.dart';
import '../file_output.dart';
import '../../../viewmodels/aral_checkin_viewmodel.dart';
import '../../../viewmodels/aral_report_viewmodel.dart';
import '../../../viewmodels/aral_roster_import_viewmodel.dart';
import '../../../viewmodels/aral_viewmodel.dart';

class _Usage implements Exception {
  final String message;
  const _Usage(this.message);
}

int _int(String raw, String what) =>
    int.tryParse(raw) ?? (throw _Usage('Invalid $what: "$raw" (expected a number)'));

/// Splits trailing options: a number = sectionId, asof=YYYY-MM-DD.
(int?, DateTime?) _options(Iterable<String> args, String usage) {
  int? sectionId;
  DateTime? asOf;
  for (final a in args) {
    if (a.startsWith('asof=')) {
      asOf = DateTime.tryParse(a.substring(5)) ?? (throw _Usage('Invalid date in "$a" (YYYY-MM-DD)'));
    } else if (int.tryParse(a) != null) {
      sectionId = int.parse(a);
    } else {
      throw _Usage('Unknown option "$a".\n$usage');
    }
  }
  return (sectionId, asOf);
}

/// `Wrote <path>.` or `Couldn't write <path>: <reason>`.
Future<String> _write(String path, List<int> bytes) async =>
    await writeOutputFile(path, bytes: bytes) ?? 'Wrote ${outputPath(path)}.';

void registerAralExportCommands(
    ConsoleRegistry registry, AralViewModel aral, AralReportViewModel report, AralCheckinViewModel checkins) {
  void add(String name, String description, Future<String> Function(List<String> args) handler) {
    registry.register(ConsoleCommand(
      name: name,
      description: description,
      handler: (args) async {
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

  add('aral-export-report',
      'aral-export-report <schoolId> <schoolYear> <template.xlsx> <out.xlsx> [sectionId] [asof=YYYY-MM-DD] — the '
          'implementation report (Grades 4-10) in the ARAL Reading Implementation Report layout', (args) async {
    const usage = 'Usage: aral-export-report <schoolId> <schoolYear> <template.xlsx> <out.xlsx> [sectionId] [asof=YYYY-MM-DD]';
    if (args.length < 4) throw const _Usage(usage);
    final template = File(args[2]);
    if (!await template.exists()) throw _Usage('No template "${args[2]}".');
    if (File(args[3]).absolute.path == template.absolute.path) throw const _Usage('Write to a new file, not over the template.');
    final (sectionId, asOf) = _options(args.skip(4), usage);
    final (bytes, notes) = await report.implementationReportXlsx(
        template: await template.readAsBytes(),
        schoolId: _int(args[0], 'schoolId'),
        schoolYear: args[1],
        sectionId: sectionId,
        asOf: asOf);
    return [await _write(args[3], bytes), ...notes.map((n) => 'Note: $n')].join('\n');
  });

  add('aral-export-report-csv',
      'aral-export-report-csv <schoolId> <schoolYear> <out.csv> [sectionId] [asof=YYYY-MM-DD] — the implementation '
          'report (Grades 1-10) as CSV', (args) async {
    const usage = 'Usage: aral-export-report-csv <schoolId> <schoolYear> <out.csv> [sectionId] [asof=YYYY-MM-DD]';
    if (args.length < 3) throw const _Usage(usage);
    final (sectionId, asOf) = _options(args.skip(3), usage);
    final csv = await report.implementationReportCsv(
        schoolId: _int(args[0], 'schoolId'), schoolYear: args[1], sectionId: sectionId, asOf: asOf);
    return _write(args[2], _utf8(csv));
  });

  add('aral-export-roster',
      'aral-export-roster <schoolId> <schoolYear> <out.csv> [sectionId] — the ARAL roster as CSV', (args) async {
    const usage = 'Usage: aral-export-roster <schoolId> <schoolYear> <out.csv> [sectionId]';
    if (args.length < 3) throw const _Usage(usage);
    final (sectionId, asOf) = _options(args.skip(3), usage);
    if (asOf != null) throw const _Usage(usage);
    final csv = await aral.rosterCsv(schoolId: _int(args[0], 'schoolId'), schoolYear: args[1], sectionId: sectionId);
    return _write(args[2], _utf8(csv));
  });

  add('aral-export-checkins',
      'aral-export-checkins <schoolId> <schoolYear> <out.csv> [sectionId] — the check-in report as CSV', (args) async {
    const usage = 'Usage: aral-export-checkins <schoolId> <schoolYear> <out.csv> [sectionId]';
    if (args.length < 3) throw const _Usage(usage);
    final (sectionId, asOf) = _options(args.skip(3), usage);
    if (asOf != null) throw const _Usage(usage);
    final csv =
        await checkins.checkinReportCsv(schoolId: _int(args[0], 'schoolId'), schoolYear: args[1], sectionId: sectionId);
    return _write(args[2], _utf8(csv));
  });
}

List<int> _utf8(String s) => utf8.encode(s);

String _rosterPreview(AralRosterImportPreview p) {
  final lines = <String>[
    'ARAL roster import -> school ${p.schoolId}, ${p.schoolYear}',
    ...p.notes.map((n) => 'Note: $n'),
  ];
  for (final r in p.rows) {
    final who = 'row ${r.rowNo} | LRN ${r.lrn ?? '-'} | ${r.name}'
        '${r.section == null ? '' : ' | G${r.section!.gradeLevel} ${r.section!.sectionName}'}';
    final what = '${r.program} | entered ${r.enteredOn}${r.aralClass == null ? '' : ' | class "${r.aralClass!.className}"'}'
        '${r.classFlag == null ? '' : ' | ${r.classFlag}'}';
    lines.add(switch (r.outcome) {
      AralRosterImportOutcome.add => '  add     $who | $what',
      AralRosterImportOutcome.addAndExit =>
        '  add+exit $who | $what | exited ${r.exitedOn} (${r.exitReason!.value})',
      AralRosterImportOutcome.alreadyOnRoster => '  skip    $who | already on the ARAL roster',
      AralRosterImportOutcome.skipGradeLevelReady =>
        '  skip    $who | grade-level-ready exit (BASA sets these from results)',
      AralRosterImportOutcome.error => '  ERROR   $who | ${r.problems.join('; ')}',
    });
  }
  lines.add('${p.count(AralRosterImportOutcome.add) + p.count(AralRosterImportOutcome.addAndExit)} to add, '
      '${p.count(AralRosterImportOutcome.alreadyOnRoster) + p.count(AralRosterImportOutcome.skipGradeLevelReady)} skipped, '
      '${p.count(AralRosterImportOutcome.error)} with errors.');
  return lines.join('\n');
}

void registerAralRosterImportCommands(ConsoleRegistry registry, AralRosterImportViewModel vm) {
  Future<(int, String, List<int>, String)> args3(List<String> args, String usage) async {
    if (args.length < 3) throw _Usage(usage);
    final file = File(args[2]);
    if (!await file.exists()) throw _Usage('No file "${args[2]}".');
    return (_int(args[0], 'schoolId'), args[1], await file.readAsBytes(), args[2]);
  }

  for (final (name, doIt) in const [('aral-import-roster-preview', false), ('aral-import-roster', true)]) {
    final usage = 'Usage: $name <schoolId> <schoolYear> <file.csv|file.xlsx>';
    registry.register(ConsoleCommand(
      name: name,
      description: doIt
          ? '$name <schoolId> <schoolYear> <file.csv|.xlsx> — add an ARAL roster from a spreadsheet (LRN, Program, '
              'Class, Entered, Notes; Exited + Exit reason optional)'
          : '$name <schoolId> <schoolYear> <file.csv|.xlsx> — check an ARAL roster file (nothing is written)',
      handler: (args) async {
        try {
          final (schoolId, year, bytes, fileName) = await args3(args, usage);
          if (!doIt) return _rosterPreview(await vm.preview(schoolId, year, bytes, fileName));
          final r = await vm.importRoster(schoolId, year, bytes, fileName);
          return [
            'Added ${r.added.length} learner(s) to the ARAL roster'
                '${r.added.isEmpty ? '' : ': #${r.added.map((e) => e.id).join(', #')}'}.',
            if (r.preview.count(AralRosterImportOutcome.alreadyOnRoster) > 0)
              'Skipped ${r.preview.count(AralRosterImportOutcome.alreadyOnRoster)} already on the roster.',
            if (r.preview.count(AralRosterImportOutcome.skipGradeLevelReady) > 0)
              'Skipped ${r.preview.count(AralRosterImportOutcome.skipGradeLevelReady)} grade-level-ready exit(s).',
            if (r.preview.count(AralRosterImportOutcome.error) > 0)
              'Skipped ${r.preview.count(AralRosterImportOutcome.error)} row(s) with errors (see aral-import-roster-preview).',
            ...r.warnings.entries.map((e) => 'Note row ${e.key.rowNo} (${e.key.name}): ${e.value}'),
            ...r.failed.entries.map((e) => 'FAILED row ${e.key.rowNo} (${e.key.name}): ${e.value}'),
          ].join('\n');
        } on _Usage catch (e) {
          return e.message;
        } catch (e) {
          return '$name failed: $e';
        }
      },
    ));
  }
}
