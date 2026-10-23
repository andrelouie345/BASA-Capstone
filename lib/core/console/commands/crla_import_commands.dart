// lib/core/console/commands/crla_import_commands.dart

/// Commands for importing filled DepEd CRLA2 scoresheets into a section
/// (local, offline-first like CRLA). Paths with spaces go in double quotes.
library;

import 'dart:io';

import '../console_command.dart';
import '../console_registry.dart';
import '../file_output.dart';
import '../../../viewmodels/auth_viewmodel.dart';
import '../../../viewmodels/crla_export_viewmodel.dart';
import '../../models/crla_assessment.dart' show CrlaRound;

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
        final error = await writeOutputFile(out.path, bytes: x.bytes);
        if (error != null) return error;
        return [
          'Wrote ${outputPath(out.path)}: Grade ${x.section.gradeLevel} ${x.section.sectionName}, ${x.round.label}, '
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
