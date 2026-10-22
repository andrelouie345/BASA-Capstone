// lib/core/console/commands/crla_import_admin_commands.dart
// Admin build only: the admin half of crla_import_commands.dart (tutor build split, 2026-10-22).

import 'dart:io';

import '../console_command.dart';
import '../console_registry.dart';
import '../../../viewmodels/auth_viewmodel.dart';
import '../../../viewmodels/crla_import_viewmodel.dart';
import '../../models/crla_assessment.dart' show CrlaRound;

class _Usage implements Exception {
  final String message;
  const _Usage(this.message);
}

/// `<sectionId> <file.xlsx> [bosy|mosy|eosy] [again]`
Future<(int, List<int>, CrlaRound?, bool)> _args(List<String> args, String usage) async {
  if (args.length < 2) throw _Usage(usage);
  final sectionId = int.tryParse(args[0]) ?? (throw _Usage('Invalid sectionId: "${args[0]}"\n$usage'));
  final file = File(args[1]);
  if (!await file.exists()) throw _Usage('No file "${args[1]}".');
  CrlaRound? round;
  var again = false;
  for (final a in args.skip(2)) {
    final l = a.toLowerCase();
    if (const ['bosy', 'mosy', 'eosy'].contains(l)) {
      round = CrlaRound.fromString(l);
    } else if (l == 'again') {
      again = true;
    } else {
      throw _Usage('Unknown option "$a".\n$usage');
    }
  }
  return (sectionId, await file.readAsBytes(), round, again);
}

String _who(CrlaImportRow r) =>
    '${r.row.sheet.split(' ').take(2).join(' ')} row ${r.row.rowNo} | LRN ${r.row.lrn ?? '-'} | ${r.row.name ?? r.student?.lastName ?? ''}';

String _preview(CrlaImportPreview p) {
  final lines = [
    'Grade ${p.file.grade} scoresheet -> section ${p.section.id} (Grade ${p.section.gradeLevel} ${p.section.sectionName}, '
        '${p.section.schoolYear}), ${p.round.label}; languages: '
        '${p.file.languages.entries.map((e) => '${e.key} ${e.value ?? '(none)'}').join(', ')}',
    ...p.warnings.map((w) => 'Note: $w'),
  ];
  for (final r in p.rows) {
    final row = r.row;
    final what = [
      if (row.hasPart1) 'Part 1 ${row.task1}${row.task2Low != null ? '+L${row.task2Low}' : ''}'
          '${row.task2High != null ? '+H${row.task2High}' : ''}${row.task2 != null ? '+W${row.task2}' : ''}',
      if (row.hasPart2) 'story ${row.storyNo}, ${row.wordsRead} words, ${row.minutes}:${row.seconds.toString().padLeft(2, '0')}, '
          'comp ${row.comprehension}',
    ].join(' | ');
    lines.add(switch (r.outcome) {
      CrlaImportOutcome.import => '  import  ${_who(r)} | ${row.assessedOn} | $what',
      CrlaImportOutcome.alreadyAssessed =>
        '  skip    ${_who(r)} | already assessed this round (attempt ${r.existingAttempt}; "again" adds a new attempt)',
      CrlaImportOutcome.error => '  ERROR   ${_who(r)} | ${r.problems.join('; ')}',
    });
  }
  lines.add('${p.count(CrlaImportOutcome.import)} to import, ${p.count(CrlaImportOutcome.alreadyAssessed)} already '
      'assessed, ${p.count(CrlaImportOutcome.error)} with errors.');
  return lines.join('\n');
}

void registerCrlaImportCommands(ConsoleRegistry registry, AuthViewModel authVm, CrlaImportViewModel vm) {
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

  add('crla-import-preview',
      'crla-import-preview <sectionId> <file.xlsx> [bosy|mosy|eosy] [again] — check a filled CRLA2 scoresheet '
          'against a section (nothing is written)', (args) async {
    final (sectionId, bytes, round, again) =
        await _args(args, 'Usage: crla-import-preview <sectionId> <file.xlsx> [bosy|mosy|eosy] [again]');
    return _preview(await vm.preview(sectionId, bytes, round: round, again: again));
  });

  add('crla-import',
      'crla-import <sectionId> <file.xlsx> [bosy|mosy|eosy] [again] — import a filled CRLA2 scoresheet into a '
          'section (rows with errors and learners already assessed this round are skipped)', (args) async {
    final (sectionId, bytes, round, again) =
        await _args(args, 'Usage: crla-import <sectionId> <file.xlsx> [bosy|mosy|eosy] [again]');
    final r = await vm.importScoresheet(sectionId, bytes, round: round, again: again);
    final lines = [
      'Imported ${r.assessmentIds.length} assessment(s) (${r.preview.round.label}): ids ${r.assessmentIds.join(', ')}',
      if (r.preview.count(CrlaImportOutcome.alreadyAssessed) > 0)
        'Skipped ${r.preview.count(CrlaImportOutcome.alreadyAssessed)} already assessed this round.',
      if (r.preview.count(CrlaImportOutcome.error) > 0)
        'Skipped ${r.preview.count(CrlaImportOutcome.error)} row(s) with errors (see crla-import-preview).',
      ...r.failed.entries.map((e) => 'FAILED ${_who(e.key)}: ${e.value}'),
    ];
    return lines.join('\n');
  });
}
