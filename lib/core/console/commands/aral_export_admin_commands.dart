// lib/core/console/commands/aral_export_admin_commands.dart
// Admin build only: the admin half of aral_export_commands.dart (tutor build split, 2026-10-22).

import 'dart:io';

import '../console_command.dart';
import '../console_registry.dart';
import '../../../viewmodels/aral_checkin_viewmodel.dart';
import '../../../viewmodels/aral_report_viewmodel.dart';
import '../../../viewmodels/aral_roster_import_viewmodel.dart';
import '../../../viewmodels/aral_viewmodel.dart';
import 'aral_export_command_helpers.dart';

void registerAralExportAdminCommands(ConsoleRegistry registry, AralViewModel aral, AralReportViewModel report, AralCheckinViewModel checkins) {
  void add(String name, String description, Future<String> Function(List<String> args) handler) {
    registry.register(ConsoleCommand(
      name: name,
      description: description,
      handler: (args) async {
        try {
          return await handler(args);
        } on AralExportUsage catch (e) {
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
    if (args.length < 4) throw const AralExportUsage(usage);
    final template = File(args[2]);
    if (!await template.exists()) throw AralExportUsage('No template "${args[2]}".');
    if (File(args[3]).absolute.path == template.absolute.path) throw const AralExportUsage('Write to a new file, not over the template.');
    final (sectionId, asOf) = aralExportOptions(args.skip(4), usage);
    final (bytes, notes) = await report.implementationReportXlsx(
        template: await template.readAsBytes(),
        schoolId: aralExportInt(args[0], 'schoolId'),
        schoolYear: args[1],
        sectionId: sectionId,
        asOf: asOf);
    return ['Wrote ${await aralExportWrite(args[3], bytes)}.', ...notes.map((n) => 'Note: $n')].join('\n');
  });

  add('aral-export-report-csv',
      'aral-export-report-csv <schoolId> <schoolYear> <out.csv> [sectionId] [asof=YYYY-MM-DD] — the implementation '
          'report (Grades 1-10) as CSV', (args) async {
    const usage = 'Usage: aral-export-report-csv <schoolId> <schoolYear> <out.csv> [sectionId] [asof=YYYY-MM-DD]';
    if (args.length < 3) throw const AralExportUsage(usage);
    final (sectionId, asOf) = aralExportOptions(args.skip(3), usage);
    final csv = await report.implementationReportCsv(
        schoolId: aralExportInt(args[0], 'schoolId'), schoolYear: args[1], sectionId: sectionId, asOf: asOf);
    return 'Wrote ${await aralExportWrite(args[2], aralExportUtf8(csv))}.';
  });

  add('aral-export-checkins',
      'aral-export-checkins <schoolId> <schoolYear> <out.csv> [sectionId] — the check-in report as CSV', (args) async {
    const usage = 'Usage: aral-export-checkins <schoolId> <schoolYear> <out.csv> [sectionId]';
    if (args.length < 3) throw const AralExportUsage(usage);
    final (sectionId, asOf) = aralExportOptions(args.skip(3), usage);
    if (asOf != null) throw const AralExportUsage(usage);
    final csv =
        await checkins.checkinReportCsv(schoolId: aralExportInt(args[0], 'schoolId'), schoolYear: args[1], sectionId: sectionId);
    return 'Wrote ${await aralExportWrite(args[2], aralExportUtf8(csv))}.';
  });
}

String _rosterPreview(AralRosterImportPreview p) {
  final lines = <String>[
    'ARAL roster import -> school ${p.schoolId}, ${p.schoolYear}',
    ...p.notes.map((n) => 'Note: $n'),
  ];
  for (final r in p.rows) {
    final who = 'row ${r.rowNo} | LRN ${r.lrn ?? '-'} | ${r.name}'
        '${r.section == null ? '' : ' | G${r.section!.gradeLevel} ${r.section!.sectionName}'}';
    final what = '${r.program} | entered ${r.enteredOn}${r.tutor == null ? '' : ' | tutor ${r.tutor!.email}'}';
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
    if (args.length < 3) throw AralExportUsage(usage);
    final file = File(args[2]);
    if (!await file.exists()) throw AralExportUsage('No file "${args[2]}".');
    return (aralExportInt(args[0], 'schoolId'), args[1], await file.readAsBytes(), args[2]);
  }

  for (final (name, doIt) in const [('aral-import-roster-preview', false), ('aral-import-roster', true)]) {
    final usage = 'Usage: $name <schoolId> <schoolYear> <file.csv|file.xlsx>';
    registry.register(ConsoleCommand(
      name: name,
      description: doIt
          ? '$name <schoolId> <schoolYear> <file.csv|.xlsx> — add an ARAL roster from a spreadsheet (LRN, Program, '
              'Tutor email, Entered, Notes; Exited + Exit reason optional)'
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
            ...r.failed.entries.map((e) => 'FAILED row ${e.key.rowNo} (${e.key.name}): ${e.value}'),
          ].join('\n');
        } on AralExportUsage catch (e) {
          return e.message;
        } catch (e) {
          return '$name failed: $e';
        }
      },
    ));
  }
}
