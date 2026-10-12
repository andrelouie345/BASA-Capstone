// lib/core/console/commands/import_commands.dart

/// Commands for SF1 roster import and conflict review
library;

import '../console_command.dart';
import '../console_registry.dart';
import '../../models/region.dart';
import '../../../viewmodels/import_viewmodel.dart';

void registerImportCommands(ConsoleRegistry registry, ImportViewModel vm) {
  String describe(ConflictResolution r) {
    if (r.action == 'skip') return 'Conflict ${r.conflictId}: resolved (skipped).';
    final where = r.enrolledIn == null
        ? ' (no visible section on record — enrollment skipped)'
        : ', enrolled into section ${r.enrolledIn!.id} (${r.enrolledIn!.schoolYear})';
    return 'Conflict ${r.conflictId}: student ${r.studentId} updated$where.';
  }

  registry.register(ConsoleCommand(
    name: 'column-map-show',
    description: 'column-map-show — display the current SF1 column mapping',
    handler: (_) async {
      final m = vm.columnMap.toMap();
      return m.entries.map((e) => '${e.key}: ${e.value}').join('\n');
    },
  ));

  registry.register(ConsoleCommand(
    name: 'column-map-set',
    description: 'column-map-set <field> <value> — edit one SF1 column mapping field (persisted)',
    handler: (args) async {
      if (args.length < 2) return 'Usage: column-map-set <field> <value>';
      final value = int.tryParse(args[1]);
      if (value == null) return 'Invalid value: "${args[1]}" (expected a non-negative integer)';
      final error = await vm.columnMap.set(args[0], value);
      return error ?? '${args[0]} set to $value.';
    },
  ));

  registry.register(ConsoleCommand(
    name: 'import-preview',
    description: 'import-preview <file.xlsx> <rowIndex> — dump raw column values to verify mapping (admin/coordinator only)',
    handler: (args) async {
      if (args.length < 2) return 'Usage: import-preview <file.xlsx> <rowIndex>';
      final row = int.tryParse(args[1]);
      if (row == null) return 'rowIndex must be a number';
      try {
        final cells = await vm.previewRow(args[0], row);
        return cells.asMap().entries.map((e) => '[${e.key}] ${e.value ?? "(empty)"}').join('\n');
      } catch (e) {
        return 'Preview failed: $e';
      }
    },
  ));

  registry.register(ConsoleCommand(
    name: 'import-trial',
    description: 'import-trial <file.xlsx> — parse and preview an SF1 import without writing anything (admin/coordinator only)',
    handler: (args) async {
      if (args.isEmpty) return 'Usage: import-trial <file.xlsx>';
      try {
        final t = await vm.trial(args[0]);
        final buf = StringBuffer();
        buf.writeln('Region: "${t.rawRegion ?? "(empty)"}" -> ${t.regionError ?? Region.byId(t.regionId!)}');
        buf.writeln('School: ${t.schoolIdCode} | ${t.schoolName}');
        buf.writeln('Section: ${t.gradeLevel} - ${t.sectionName} (${t.schoolYear})');
        buf.writeln('Would insert: ${t.wouldInsert}, would conflict: ${t.wouldConflict}, '
            'already enrolled: ${t.alreadyEnrolled}, would skip: ${t.wouldSkip}');
        buf.writeln('(A learner registered at another school shows as INSERT here and becomes a transfer conflict on import.)');
        buf.writeln('---');
        for (final row in t.rows) {
          buf.writeln('[${row.rowIndex}] ${row.outcome.toUpperCase()}: ${row.name}${row.reason != null ? " (${row.reason})" : ""}');
        }
        return buf.toString();
      } catch (e) {
        return 'Trial failed: $e';
      }
    },
  ));

  registry.register(ConsoleCommand(
    name: 'import-students',
    description: 'import-students <file.xlsx> — import an SF1 roster (admin/coordinator only)',
    handler: (args) async {
      if (args.isEmpty) return 'Usage: import-students <file.xlsx>';
      try {
        final result = await vm.import(args[0]);
        return 'Inserted: ${result.inserted}, Conflicts: ${result.conflicts}, '
            'Already enrolled: ${result.alreadyEnrolled}, Skipped: ${result.skippedBlankOrTotal}';
      } catch (e) {
        return 'Import failed: $e';
      }
    },
  ));

  registry.register(ConsoleCommand(
    name: 'list-conflicts',
    description: 'list-conflicts — show pending import conflicts, oldest first (admin/coordinator only)',
    handler: (_) async {
      try {
        await vm.loadPendingConflicts();
        if (vm.pendingConflicts.isEmpty) return '(no pending conflicts)';
        return vm.pendingConflicts.map((c) => '${c.id}: LRN ${c.lrn} — ${c.reason}').join('\n');
      } catch (e) {
        return 'List failed: $e';
      }
    },
  ));

  registry.register(ConsoleCommand(
    name: 'show-conflict',
    description: 'show-conflict <id> — show full incoming data for a conflict, including its section (admin/coordinator only)',
    handler: (args) async {
      final id = int.tryParse(args.isNotEmpty ? args[0] : '');
      if (id == null) return 'Usage: show-conflict <id>';
      try {
        final r = await vm.getConflict(id);
        final c = r.conflict;
        final sectionInfo = c.sectionId == null
            ? '(no section on record)'
            : r.section != null
                ? '${r.section!.id} | ${r.section}'
                : '${c.sectionId} (not found)';
        return 'LRN: ${c.lrn}\nSection: $sectionInfo\nStatus: ${c.status}\nReason: ${c.reason}\nIncoming: ${c.incomingDataJson}';
      } catch (e) {
        return 'Show failed: $e';
      }
    },
  ));

  registry.register(ConsoleCommand(
    name: 'resolve-conflict',
    description: 'resolve-conflict <id> <skip|update> — resolve one pending import conflict (admin/coordinator only)',
    handler: (args) async {
      if (args.length < 2) return 'Usage: resolve-conflict <id> <skip|update>';
      final id = int.tryParse(args[0]);
      if (id == null) return 'id must be a number';
      try {
        return describe(await vm.resolve(id, args[1]));
      } catch (e) {
        return 'Resolve failed: $e';
      }
    },
  ));

  registry.register(ConsoleCommand(
    name: 'resolve-conflicts-all',
    description:
        'resolve-conflicts-all <skip|update> — bulk-resolve every pending conflict the same way (admin/coordinator only, no per-row review)',
    handler: (args) async {
      if (args.isEmpty || (args[0] != 'skip' && args[0] != 'update')) {
        return 'Usage: resolve-conflicts-all <skip|update>';
      }
      try {
        final outcomes = await vm.resolveAll(args[0]);
        if (outcomes.isEmpty) return '(no pending conflicts)';
        return outcomes.map((o) => o.resolution != null ? describe(o.resolution!) : 'Conflict ${o.id} failed: ${o.error}').join('\n');
      } catch (e) {
        return 'Resolve failed: $e';
      }
    },
  ));
}
