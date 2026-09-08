// lib/core/console/commands/student_commands.dart
import '../console_command.dart';
import '../console_registry.dart';
import '../../services/sf1_importer.dart';
import '../../services/roster_exporter.dart';
import '../../repositories/section_repository.dart';
import '../../repositories/student_repository.dart';
import '../../repositories/import_conflict_repository.dart';

void registerStudentCommands(
  ConsoleRegistry registry,
  Sf1Importer importer,
  RosterExporter exporter,
  SectionRepository sectionRepo,
  StudentRepository studentRepo,
  ImportConflictRepository conflictRepo,
) {
  registry.register(ConsoleCommand(
    name: 'import-preview',
    description: 'import-preview <file.xlsx> <rowIndex> — dump raw column values to verify mapping',
    handler: (args) async {
      if (args.length < 2) return 'Usage: import-preview <file.xlsx> <rowIndex>';
      final row = int.tryParse(args[1]);
      if (row == null) return 'rowIndex must be a number';
      final cells = await importer.previewRow(args[0], row);
      return cells.asMap().entries.map((e) => '[${e.key}] ${e.value ?? "(empty)"}').join('\n');
    },
  ));

  registry.register(ConsoleCommand(
    name: 'import-students',
    description: 'import-students <file.xlsx> — import an SF1 roster',
    handler: (args) async {
      if (args.isEmpty) return 'Usage: import-students <file.xlsx>';
      final result = await importer.import(args[0]);
      return 'Inserted: ${result.inserted}, Conflicts: ${result.conflicts}, Skipped: ${result.skippedBlankOrTotal}';
    },
  ));

  registry.register(ConsoleCommand(
    name: 'list-sections',
    description: 'list-sections — show all imported sections',
    handler: (_) async {
      final sections = await sectionRepo.getAll();
      if (sections.isEmpty) return '(no sections yet)';
      return sections.map((s) => '${s.id}: $s').join('\n');
    },
  ));

  registry.register(ConsoleCommand(
    name: 'list-students',
    description: 'list-students <sectionId> — list students in a section',
    handler: (args) async {
      final id = int.tryParse(args.isNotEmpty ? args[0] : '');
      if (id == null) return 'Usage: list-students <sectionId>';
      final students = await studentRepo.getBySection(id);
      if (students.isEmpty) return '(no students in this section)';
      return students.map((s) => '${s.lrn}: ${s.lastName}, ${s.firstName}').join('\n');
    },
  ));

  registry.register(ConsoleCommand(
    name: 'list-conflicts',
    description: 'list-conflicts — show pending import conflicts',
    handler: (_) async {
      final pending = await conflictRepo.getPending();
      if (pending.isEmpty) return '(no pending conflicts)';
      return pending.map((c) => '${c.id}: LRN ${c.lrn} — ${c.reason}').join('\n');
    },
  ));

  registry.register(ConsoleCommand(
    name: 'show-conflict',
    description: 'show-conflict <id> — show full incoming data for a conflict',
    handler: (args) async {
      final id = int.tryParse(args.isNotEmpty ? args[0] : '');
      if (id == null) return 'Usage: show-conflict <id>';
      final c = await conflictRepo.getById(id);
      if (c == null) return 'No conflict with id $id';
      return 'LRN: ${c.lrn}\nReason: ${c.reason}\nIncoming: ${c.incomingDataJson}';
    },
  ));

  registry.register(ConsoleCommand(
    name: 'resolve-conflict',
    description: 'resolve-conflict <id> <skip> — mark a conflict resolved (update path TBD once needed)',
    handler: (args) async {
      if (args.length < 2) return 'Usage: resolve-conflict <id> <skip>';
      final id = int.tryParse(args[0]);
      if (id == null) return 'id must be a number';
      if (args[1] != 'skip') return 'Only "skip" is wired up for now — tell me when you want "update" too.';
      await conflictRepo.resolve(id, 'resolved_skipped');
      return 'Conflict $id marked resolved (skipped).';
    },
  ));

  registry.register(ConsoleCommand(
    name: 'export-section',
    description: 'export-section <sectionId> <outputPath.csv> — export a roster to CSV',
    handler: (args) async {
      if (args.length < 2) return 'Usage: export-section <sectionId> <outputPath.csv>';
      final id = int.tryParse(args[0]);
      if (id == null) return 'sectionId must be a number';
      final students = await studentRepo.getBySection(id);
      if (students.isEmpty) return 'No students found in section $id';
      final path = await exporter.exportToCsv(students, args[1]);
      return 'Exported ${students.length} students to $path';
    },
  ));
}