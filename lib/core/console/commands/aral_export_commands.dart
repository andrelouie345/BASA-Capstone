// lib/core/console/commands/aral_export_commands.dart

/// ARAL-Reading exports (IE4): the implementation report into its template
/// and as CSV, the roster and the check-in report as CSV. Admins and
/// coordinators of the school. Paths with spaces go in double quotes.
library;

import 'dart:convert';
import 'dart:io';

import '../console_command.dart';
import '../console_registry.dart';
import '../../../viewmodels/aral_checkin_viewmodel.dart';
import '../../../viewmodels/aral_report_viewmodel.dart';
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

Future<String> _write(String path, List<int> bytes) async {
  final f = File(path);
  await f.writeAsBytes(bytes);
  return f.path;
}

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
    return ['Wrote ${await _write(args[3], bytes)}.', ...notes.map((n) => 'Note: $n')].join('\n');
  });

  add('aral-export-report-csv',
      'aral-export-report-csv <schoolId> <schoolYear> <out.csv> [sectionId] [asof=YYYY-MM-DD] — the implementation '
          'report (Grades 1-10) as CSV', (args) async {
    const usage = 'Usage: aral-export-report-csv <schoolId> <schoolYear> <out.csv> [sectionId] [asof=YYYY-MM-DD]';
    if (args.length < 3) throw const _Usage(usage);
    final (sectionId, asOf) = _options(args.skip(3), usage);
    final csv = await report.implementationReportCsv(
        schoolId: _int(args[0], 'schoolId'), schoolYear: args[1], sectionId: sectionId, asOf: asOf);
    return 'Wrote ${await _write(args[2], _utf8(csv))}.';
  });

  add('aral-export-roster',
      'aral-export-roster <schoolId> <schoolYear> <out.csv> [sectionId] — the ARAL roster as CSV', (args) async {
    const usage = 'Usage: aral-export-roster <schoolId> <schoolYear> <out.csv> [sectionId]';
    if (args.length < 3) throw const _Usage(usage);
    final (sectionId, asOf) = _options(args.skip(3), usage);
    if (asOf != null) throw const _Usage(usage);
    final csv = await aral.rosterCsv(schoolId: _int(args[0], 'schoolId'), schoolYear: args[1], sectionId: sectionId);
    return 'Wrote ${await _write(args[2], _utf8(csv))}.';
  });

  add('aral-export-checkins',
      'aral-export-checkins <schoolId> <schoolYear> <out.csv> [sectionId] — the check-in report as CSV', (args) async {
    const usage = 'Usage: aral-export-checkins <schoolId> <schoolYear> <out.csv> [sectionId]';
    if (args.length < 3) throw const _Usage(usage);
    final (sectionId, asOf) = _options(args.skip(3), usage);
    if (asOf != null) throw const _Usage(usage);
    final csv =
        await checkins.checkinReportCsv(schoolId: _int(args[0], 'schoolId'), schoolYear: args[1], sectionId: sectionId);
    return 'Wrote ${await _write(args[2], _utf8(csv))}.';
  });
}

List<int> _utf8(String s) => utf8.encode(s);
