// lib/core/console/commands/school_commands.dart

/// Commands for schools
library;

import '../console_command.dart';
import '../console_registry.dart';
import '../../models/school.dart';
import '../../models/region.dart';
import '../../../viewmodels/school_viewmodel.dart';

void registerSchoolCommands(ConsoleRegistry registry, SchoolViewModel vm) {
  registry.register(ConsoleCommand(
    name: 'school-list',
    description: 'school-list — list all schools (admin/coordinator only)',
    handler: (_) async {
      try {
        await vm.loadAll();
        if (vm.items.isEmpty) return '(no schools found)';
        return vm.items.map((s) {
          final region = s.regionId != null ? Region.byId(s.regionId!) : null;
          return '${s.id} | ${s.schoolId} | ${s.schoolName} | ${region?.toString() ?? "(no region)"}';
        }).join('\n');
      } catch (e) {
        return 'List failed: $e';
      }
    },
  ));

  registry.register(ConsoleCommand(
    name: 'school-create',
    description:
        'school-create <schoolId> <regionId|-> <division|-> <full school name...> — create a school (superadmin only). Use "-" for region/division to leave them null.\n\t.:REGIONS:.\n\t1. Ilocos Region (Region I)\n\t2. Cagayan Valley (Region II)\n\t3. Central Luzon (Region III)\n\t4. CALABARZON (Region IV-A)\n\t5. MIMAROPA (Region IV-B)\n\t6. Bicol Region (Region V)\n\t7. National Capital Region (NCR / Metro Manila)\n\t8. Cordillera Administrative Region (CAR)\n\t9. Western Visayas (Region VI)\n\t10. Central Visayas (Region VII)\n\t11. Eastern Visayas (Region VIII)\n\t12. Zamboanga Peninsula (Region IX)\n\t13. Northern Mindanao (Region X)\n\t14. Davao Region (Region XI)\n\t15. SOCCSKSARGEN (Region XII)\n\t16. Caraga (Region XIII)\n\t17. Bangsamoro Autonomous Region in Muslim Mindanao (BARMM)\n\t18. Negros Island Region (NIR)',
    handler: (args) async {
      if (args.length < 4) {
        return 'Usage: school-create <schoolId> <regionId|-> <division|-> <full school name...>';
      }
      final regionId = args[1] == '-' ? null : int.tryParse(args[1]);
      if (args[1] != '-' && regionId == null) {
        return 'Invalid regionId: "${args[1]}" (expected a number 1-18, or "-").';
      }
      try {
        final result = await vm.create(
          schoolCode: args[0],
          regionId: regionId,
          division: args[2] == '-' ? null : args[2],
          schoolName: args.sublist(3).join(' '),
        );
        final s = result.school;
        return result.created
            ? 'OK: ${s.id} | ${s.schoolId} | ${s.schoolName}'
            : 'Already exists (unchanged): ${s.id} | ${s.schoolId} | ${s.schoolName}';
      } catch (e) {
        return 'Create failed: $e';
      }
    },
  ));

  registry.register(ConsoleCommand(
    name: 'school-update',
    description:
        'school-update <id> <schoolIdCode> <regionId|-> <division|-> <full school name...> — update a school (admin/coordinator, own school only; superadmin any)',
    handler: (args) async {
      const usage = 'Usage: school-update <id> <schoolIdCode> <regionId|-> <division|-> <full school name...>';
      if (args.length < 5) return usage;
      final id = int.tryParse(args[0]);
      if (id == null) return 'Invalid id: "${args[0]}" (expected a number)';
      final regionId = args[2] == '-' ? null : int.tryParse(args[2]);
      if (args[2] != '-' && regionId == null) {
        return 'Invalid regionId: "${args[2]}" (expected a number 1-18, or "-").';
      }
      try {
        final updated = await vm.update(School(
          id: id,
          schoolId: args[1],
          regionId: regionId,
          division: args[3] == '-' ? null : args[3],
          schoolName: args.sublist(4).join(' '),
        ));
        return 'Updated: ${updated.id} | ${updated.schoolId} | ${updated.schoolName}';
      } catch (e) {
        return 'Update failed: $e';
      }
    },
  ));
}
