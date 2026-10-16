// lib/core/console/commands/crla_import_commands.dart

/// Commands for importing filled DepEd CRLA2 scoresheets into a section
/// (local, offline-first like CRLA). Paths with spaces go in double quotes.
library;

import 'dart:io';

import '../console_command.dart';
import '../console_registry.dart';
import '../../../viewmodels/auth_viewmodel.dart';
import '../../../viewmodels/crla_export_viewmodel.dart';
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

/// crla-export lives with the import commands: same file format, same section.
void registerCrlaExportCommands(ConsoleRegistry registry, AuthViewModel authVm, CrlaExportViewModel vm) {
  registry.register(ConsoleCommand(
    name: 'crla-export',
    description: 'crla-export <sectionId> <template.xlsx> <out.xlsx> <bosy|mosy|eosy> ["teacher"] — fill the blank '
        'CRLA2 scoresheet template of the section\'s grade with the round\'s results',
    handler: (args) async {
      final guardError = authVm.requireActiveSession();
      if (guardError != null) return guardError;
      const usage = 'Usage: crla-export <sectionId> <template.xlsx> <out.xlsx> <bosy|mosy|eosy> ["teacher"]';
      if (args.length < 4) return usage;
      final sectionId = int.tryParse(args[0]);
      if (sectionId == null) return 'Invalid sectionId: "${args[0]}"\n$usage';
      final template = File(args[1]);
      if (!await template.exists()) return 'No template "${args[1]}".';
      final out = File(args[2]);
      if (out.absolute.path == template.absolute.path) return 'Write to a new file, not over the template.';
      final r = args[3].toLowerCase();
      if (!const ['bosy', 'mosy', 'eosy'].contains(r)) return usage;
      try {
        final x = await vm.exportScoresheet(sectionId, await template.readAsBytes(),
            round: CrlaRound.fromString(r), teacher: args.length > 4 ? args.sublist(4).join(' ') : null);
        await out.writeAsBytes(x.bytes);
        return [
          'Wrote ${out.path}: Grade ${x.section.gradeLevel} ${x.section.sectionName}, ${x.round.label}, '
              '${x.learners} learner(s); results: '
              '${x.resultsByVariant.isEmpty ? 'none' : x.resultsByVariant.entries.map((e) => '${e.key} ${e.value}').join(', ')}.',
          ...x.notes.map((n) => 'Note: $n'),
        ].join('\n');
      } catch (e) {
        return 'crla-export failed: $e';
      }
    },
  ));
}
