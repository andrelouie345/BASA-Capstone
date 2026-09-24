// lib/core/console/commands/school_commands.dart

/// Commands for schools
library;

import '../console_command.dart';
import '../console_registry.dart';
import '../logger.dart';
import '../../models/user_role.dart';
import '../../data/remote/school_repository_supabase.dart';
import '../../../viewmodels/auth_viewmodel.dart';
import '../../models/school.dart';

void registerSchoolCommands(ConsoleRegistry registry, AuthViewModel authVm, Logger? logger) {
  registry.register(ConsoleCommand(
    name: 'school-list',
    description: 'school-list — list all schools (admin/coordinator only)',
    handler: (_) async {
      final guardError = authVm.requireActiveSession();
      if (guardError != null) return guardError;
      final client = authVm.client!;

      final actingRole = authVm.currentUser?.role;
      if (actingRole != UserRole.admin && actingRole != UserRole.coordinator) {
        return 'Forbidden: admin or coordinator only.';
      }

      final repo = SchoolRepositorySupabase(client);
      try {
        final schools = await repo.getAll();
        if (schools.isEmpty) return '(no schools found)';
        return schools
            .map((s) => '${s.id} | ${s.schoolId} | ${s.schoolName}${s.region != null ? " | ${s.region}" : ""}')
            .join('\n');
      } catch (e) {
        return 'List failed: $e';
      }
    },
  ));

   registry.register(ConsoleCommand(
    name: 'school-create',
    description:
        'school-create <schoolId> <region|-> <division|-> <full school name...> — create a school (admin/coordinator only). Use "-" for region/division to leave them null.',
    handler: (args) async {
      final guardError = authVm.requireActiveSession();
      if (guardError != null) return guardError;
      final client = authVm.client!;

      final actingUser = authVm.currentUser;
      final isSuperadmin = actingUser?.role == UserRole.admin && actingUser?.schoolId == null;
      if (!isSuperadmin) {
        return 'Forbidden: superadmin only.';
      }

      final actingRole = authVm.currentUser?.role;
      if (actingRole != UserRole.admin && actingRole != UserRole.coordinator) {
        return 'Forbidden: admin or coordinator only.';
      }

      if (args.length < 4) {
        return 'Usage: school-create <schoolId> <region|-> <division|-> <full school name...>';
      }

      final schoolIdCode = args[0];
      final region = args[1] == '-' ? null : args[1];
      final division = args[2] == '-' ? null : args[2];
      final schoolName = args.sublist(3).join(' ');

      final repo = SchoolRepositorySupabase(client);
      try {
        final school = await repo.getOrCreate(School(
          schoolId: schoolIdCode,
          schoolName: schoolName,
          region: region,
          division: division,
        ));
        return 'OK: ${school.id} | ${school.schoolId} | ${school.schoolName}';
      } catch (e) {
        return 'Create failed: $e';
      }
    },
  ));

    registry.register(ConsoleCommand(
    name: 'school-update',
    description:
        'school-update <id> <schoolIdCode> <region|-> <division|-> <full school name...> — update a school (admin/coordinator, own school only; superadmin any)',
    handler: (args) async {
      final guardError = authVm.requireActiveSession();
      if (guardError != null) return guardError;
      if (args.length < 4) return 'Usage: school-update <id> <schoolIdCode> <region|-> <division|-> <full school name...>';

      final id = int.tryParse(args[0]);
      if (id == null) return 'Invalid id: "${args[0]}" (expected a number)';

      final actingUser = authVm.currentUser;
      final isSuperadmin = actingUser?.role == UserRole.admin && actingUser?.schoolId == null;
      if (!isSuperadmin) {
        if (actingUser?.role != UserRole.admin && actingUser?.role != UserRole.coordinator) {
          return 'Forbidden: admin or coordinator only.';
        }
        if (actingUser?.schoolId != id) {
          return 'Forbidden: can only update your own school.';
        }
      }

      final region = args[2] == '-' ? null : args[2];
      final division = args[3] == '-' ? null : args[3];
      final schoolName = args.sublist(4).join(' ');
      if (schoolName.isEmpty) return 'Usage: school-update <id> <schoolIdCode> <region|-> <division|-> <full school name...>';

      final client = authVm.client!;
      final repo = SchoolRepositorySupabase(client);
      try {
        final updated = await repo.update(School(
          id: id,
          schoolId: args[1],
          schoolName: schoolName,
          region: region,
          division: division,
        ));
        return 'Updated: ${updated.id} | ${updated.schoolId} | ${updated.schoolName}';
      } catch (e) {
        return 'Update failed: $e';
      }
    },
  ));
}