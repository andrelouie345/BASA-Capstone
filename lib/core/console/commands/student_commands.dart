// lib/core/console/commands/student_commands.dart
import '../console_command.dart';
import '../console_registry.dart';
import '../../services/roster_exporter.dart';
import '../../repositories/section_repository.dart';
import '../../repositories/student_repository.dart';

void registerStudentCommands(
  ConsoleRegistry registry,
  RosterExporter exporter,
  SectionRepository sectionRepo,
  StudentRepository studentRepo,
) {
  registry.register(ConsoleCommand(
    name: 'list-sections',
    description: 'list-sections — show all locally cached sections',
    handler: (_) async {
      final sections = await sectionRepo.getAll();
      if (sections.isEmpty) return '(no sections yet)';
      return sections.map((s) => '${s.id}: $s').join('\n');
    },
  ));

  registry.register(ConsoleCommand(
    name: 'list-students',
    description: 'list-students <sectionId> — list students in a section (local cache)',
    handler: (args) async {
      final id = int.tryParse(args.isNotEmpty ? args[0] : '');
      if (id == null) return 'Usage: list-students <sectionId>';
      final students = await studentRepo.getBySection(id);
      if (students.isEmpty) return '(no students in this section)';
      return students.map((s) => '${s.lrn}: ${s.lastName}, ${s.firstName}').join('\n');
    },
  ));

  registry.register(ConsoleCommand(
    name: 'export-section',
    description: 'export-section <sectionId> <outputPath.csv> — export a roster to CSV (local cache)',
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