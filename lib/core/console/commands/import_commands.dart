// lib/core/console/commands/import_commands.dart

/// Commands for SF1 roster import and conflict review
library;

import 'dart:convert';
import 'package:basa_capstone/core/models/student.dart';

import '../console_command.dart';
import '../console_registry.dart';
import '../logger.dart';
import '../../models/user_role.dart';
import '../../services/sf1_importer.dart';
import '../../repositories/school_repository.dart';
import '../../repositories/section_repository.dart';
import '../../repositories/student_repository.dart';
import '../../data/remote/school_repository_supabase.dart';
import '../../data/remote/section_repository_supabase.dart';
import '../../data/remote/student_repository_supabase.dart';
import '../../data/remote/import_conflict_repository_supabase.dart';
import '../../../viewmodels/auth_viewmodel.dart';

void registerImportCommands(
  ConsoleRegistry registry,
  AuthViewModel authVm,
  SchoolRepository localSchoolRepo,
  SectionRepository localSectionRepo,
  StudentRepository localStudentRepo,
  Logger? logger,
) {
  String? _forbiddenUnlessAdminOrCoordinator() {
    final role = authVm.currentUser?.role;
    if (role != UserRole.admin && role != UserRole.coordinator) {
      return 'Forbidden: admin or coordinator only.';
    }
    return null;
  }

  Sf1Importer _buildImporter() {
    final client = authVm.client!;
    return Sf1Importer(
      schoolRepo: SchoolRepositorySupabase(client),
      localSchoolRepo: localSchoolRepo,
      sectionRepo: SectionRepositorySupabase(client),
      localSectionRepo: localSectionRepo,
      studentRepo: StudentRepositorySupabase(client),
      localStudentRepo: localStudentRepo,
      conflictRepo: ImportConflictRepositorySupabase(client),
      logger: logger,
    );
  }

  Future<String> _resolveOne( int id, String action) async {
    final client = authVm.client!;
    final conflictRepo = ImportConflictRepositorySupabase(client);

    if (action == 'skip') {
      await conflictRepo.resolve(id, 'resolved_skipped');
      return 'Conflict $id: resolved (skipped).';
    }

    final conflict = await conflictRepo.getById(id);
    if (conflict == null) return 'Conflict $id: not found.';

    final studentRepo = StudentRepositorySupabase(client);
    final existing = await studentRepo.findByLrn(conflict.lrn);
    if (existing == null) {
      return 'Conflict $id: cannot update — no existing student with LRN ${conflict.lrn}.';
    }

    final incomingMap = jsonDecode(conflict.incomingDataJson) as Map<String, Object?>;
    final merged = Student.fromMap({
      ...incomingMap,
      'id': existing.id,
      'school_id': existing.schoolId,
    });

    try {
      await studentRepo.update(merged);
    } catch (e) {
      return 'Conflict $id: update failed: $e';
    }

    String enrollNote = '';
    if (conflict.sectionId != null) {
      final sectionRepo = SectionRepositorySupabase(client);
      final section = await sectionRepo.getById(conflict.sectionId!);
      if (section != null) {
        await studentRepo.enroll(
          studentId: existing.id!,
          sectionId: conflict.sectionId!,
          schoolYear: section.schoolYear,
        );
        enrollNote = ', enrolled into section ${conflict.sectionId} (${section.schoolYear})';

        final localSection = await localSectionRepo.getById(conflict.sectionId!);
        await localStudentRepo.upsertWithId(Student.fromMap({
          ...incomingMap,
          'id': existing.id,
          'school_id': localSection?.schoolId ?? existing.schoolId,
        }));
      } else {
        enrollNote = ' (section ${conflict.sectionId} not found — enrollment skipped)';
      }
    } else {
      enrollNote = ' (no section on record — enrollment skipped)';
    }

    await conflictRepo.resolve(id, 'resolved_updated');
    return 'Conflict $id: student ${existing.id} updated$enrollNote.';
  }
  

  registry.register(ConsoleCommand(
    name: 'import-preview',
    description: 'import-preview <file.xlsx> <rowIndex> — dump raw column values to verify mapping (requires sign-in)',
    handler: (args) async {
      final guardError = authVm.requireActiveSession();
      if (guardError != null) return guardError;
      if (args.length < 2) return 'Usage: import-preview <file.xlsx> <rowIndex>';
      final row = int.tryParse(args[1]);
      if (row == null) return 'rowIndex must be a number';
      final cells = await _buildImporter().previewRow(args[0], row);
      return cells.asMap().entries.map((e) => '[${e.key}] ${e.value ?? "(empty)"}').join('\n');
    },
  ));

  registry.register(ConsoleCommand(
    name: 'import-students',
    description: 'import-students <file.xlsx> — import an SF1 roster (admin/coordinator only)',
    handler: (args) async {
      final guardError = authVm.requireActiveSession();
      if (guardError != null) return guardError;
      final forbidden = _forbiddenUnlessAdminOrCoordinator();
      if (forbidden != null) return forbidden;
      if (args.isEmpty) return 'Usage: import-students <file.xlsx>';
      try {
        final result = await _buildImporter().import(args[0]);
        return 'Inserted: ${result.inserted}, Conflicts: ${result.conflicts}, Skipped: ${result.skippedBlankOrTotal}';
      } catch (e) {
        return 'Import failed: $e';
      }
    },
  ));

  registry.register(ConsoleCommand(
    name: 'list-conflicts',
    description: 'list-conflicts — show pending import conflicts (admin/coordinator only)',
    handler: (_) async {
      final guardError = authVm.requireActiveSession();
      if (guardError != null) return guardError;
      final forbidden = _forbiddenUnlessAdminOrCoordinator();
      if (forbidden != null) return forbidden;
      final conflictRepo = ImportConflictRepositorySupabase(authVm.client!);
      final pending = await conflictRepo.getPending();
      if (pending.isEmpty) return '(no pending conflicts)';
      return pending.map((c) => '${c.id}: LRN ${c.lrn} — ${c.reason}').join('\n');
    },
  ));

  registry.register(ConsoleCommand(
    name: 'show-conflict',
    description: 'show-conflict <id> — show full incoming data for a conflict, including its section (admin/coordinator only)',
    handler: (args) async {
      final guardError = authVm.requireActiveSession();
      if (guardError != null) return guardError;
      final forbidden = _forbiddenUnlessAdminOrCoordinator();
      if (forbidden != null) return forbidden;
      final id = int.tryParse(args.isNotEmpty ? args[0] : '');
      if (id == null) return 'Usage: show-conflict <id>';

      final client = authVm.client!;
      final conflictRepo = ImportConflictRepositorySupabase(client);
      final c = await conflictRepo.getById(id);
      if (c == null) return 'No conflict with id $id';

      String sectionInfo = '(no section on record)';
      if (c.sectionId != null) {
        final sectionRepo = SectionRepositorySupabase(client);
        final section = await sectionRepo.getById(c.sectionId!);
        sectionInfo = section != null ? '${section.id} | $section' : '${c.sectionId} (not found)';
      }

      return 'LRN: ${c.lrn}\nSection: $sectionInfo\nStatus: ${c.status}\nReason: ${c.reason}\nIncoming: ${c.incomingDataJson}';
    },
  ));

  registry.register(ConsoleCommand(
    name: 'resolve-conflict',
    description:
        'resolve-conflict <id> <skip|update> — resolve one import conflict (admin/coordinator only)',
    handler: (args) async {
      final guardError = authVm.requireActiveSession();
      if (guardError != null) return guardError;
      final forbidden = _forbiddenUnlessAdminOrCoordinator();
      if (forbidden != null) return forbidden;
      if (args.length < 2) return 'Usage: resolve-conflict <id> <skip|update>';
      final id = int.tryParse(args[0]);
      if (id == null) return 'id must be a number';
      if (args[1] != 'skip' && args[1] != 'update') return 'Invalid action: "${args[1]}" (expected skip or update)';
      return _resolveOne(id, args[1]);
    },
  ));

    registry.register(ConsoleCommand(
    name: 'resolve-conflicts-all',
    description:
        'resolve-conflicts-all <skip|update> — bulk-resolve every pending conflict the same way (admin/coordinator only, for testing convenience — no per-row review)',
    handler: (args) async {
      final guardError = authVm.requireActiveSession();
      if (guardError != null) return guardError;
      final forbidden = _forbiddenUnlessAdminOrCoordinator();
      if (forbidden != null) return forbidden;
      if (args.isEmpty || (args[0] != 'skip' && args[0] != 'update')) {
        return 'Usage: resolve-conflicts-all <skip|update>';
      }
      final action = args[0];

      final conflictRepo = ImportConflictRepositorySupabase(authVm.client!);
      final pending = await conflictRepo.getPending();
      if (pending.isEmpty) return '(no pending conflicts)';

      final results = <String>[];
      for (final c in pending) {
        results.add(await _resolveOne(c.id!, action));
      }
      return results.join('\n');
    },
  ));


    registry.register(ConsoleCommand(
    name: 'student-list',
    description: 'student-list — list all students visible to you (Supabase, RLS-scoped)',
    handler: (_) async {
      final guardError = authVm.requireActiveSession();
      if (guardError != null) return guardError;
      final studentRepo = StudentRepositorySupabase(authVm.client!);
      try {
        final students = await studentRepo.getAll();
        if (students.isEmpty) return '(no students found)';
        return students.map((s) => '${s.id} | ${s.lrn} | ${s.lastName}, ${s.firstName}').join('\n');
      } catch (e) {
        return 'List failed: $e';
      }
    },
  ));

  registry.register(ConsoleCommand(
    name: 'student-list-section',
    description: 'student-list-section <sectionId> — list students in a section (Supabase, RLS-scoped)',
    handler: (args) async {
      final guardError = authVm.requireActiveSession();
      if (guardError != null) return guardError;
      if (args.isEmpty) return 'Usage: student-list-section <sectionId>';
      final sectionId = int.tryParse(args[0]);
      if (sectionId == null) return 'Invalid sectionId: "${args[0]}" (expected a number)';

      final studentRepo = StudentRepositorySupabase(authVm.client!);
      try {
        final students = await studentRepo.getBySection(sectionId);
        if (students.isEmpty) return '(no students found in this section)';
        return students.map((s) => '${s.id} | ${s.lrn} | ${s.lastName}, ${s.firstName}').join('\n');
      } catch (e) {
        return 'List failed: $e';
      }
    },
  ));
  
}