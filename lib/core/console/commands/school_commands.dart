// lib/core/console/commands/school_commands.dart

/// Commands for schools
library;

import '../console_command.dart';
import '../console_registry.dart';
import '../../models/school.dart';
import '../../models/region.dart';
import '../../../viewmodels/school_viewmodel.dart';

// Regions are typed the way people write them ("X", "Region10", "10",
// "IV-A", "NCR", "BARMM") and resolved by Region.resolve, the same matcher
// the SF1 importer uses. Internal region ids are never typed: id 10 is
// Central Visayas, which is exactly the "Region 10" mix-up this avoids.
const _regionHelp = 'Region: a code, number or quoted name, e.g. X, 10, IV-A, NCR, BARMM, '
    '"Northern Mindanao"; "-" for none.';

void registerSchoolCommands(ConsoleRegistry registry, SchoolViewModel vm) {
  registry.register(ConsoleCommand(
    name: 'school-list',
    description: 'school-list — list the schools visible to you (superadmin: all; others: their own)',
    handler: (_) async {
      try {
        await vm.loadAll();
        if (vm.items.isEmpty) return '(no schools found)';
        return vm.items.map(_describe).join('\n');
      } catch (e) {
        return 'List failed: $e';
      }
    },
  ));

  registry.register(ConsoleCommand(
    name: 'school-create',
    description: 'school-create <schoolId> <region|-> <division|-> <full school name...> — create a school '
        '(superadmin only). Use "-" for division to leave it null. $_regionHelp',
    handler: (args) async {
      if (args.length < 4) {
        return 'Usage: school-create <schoolId> <region|-> <division|-> <full school name...>';
      }
      final region = _parseRegion(args[1]);
      if (region.error != null) return region.error!;
      try {
        final result = await vm.create(
          schoolCode: args[0],
          regionId: region.id,
          division: args[2] == '-' ? null : args[2],
          schoolName: args.sublist(3).join(' '),
        );
        return result.created
            ? 'OK: ${_describe(result.school)}'
            : 'Already exists (unchanged): ${_describe(result.school)}';
      } catch (e) {
        return 'Create failed: $e';
      }
    },
  ));

  registry.register(ConsoleCommand(
    name: 'school-update',
    description: 'school-update <id> <schoolIdCode> <region|-> <division|-> <full school name...> — update a school '
        '(admin/coordinator, own school only; superadmin any). $_regionHelp',
    handler: (args) async {
      const usage = 'Usage: school-update <id> <schoolIdCode> <region|-> <division|-> <full school name...>';
      if (args.length < 5) return usage;
      final id = int.tryParse(args[0]);
      if (id == null) return 'Invalid id: "${args[0]}" (expected a number)';
      final region = _parseRegion(args[2]);
      if (region.error != null) return region.error!;
      try {
        final updated = await vm.update(School(
          id: id,
          schoolId: args[1],
          regionId: region.id,
          division: args[3] == '-' ? null : args[3],
          schoolName: args.sublist(4).join(' '),
        ));
        return 'Updated: ${_describe(updated)}';
      } catch (e) {
        return 'Update failed: $e';
      }
    },
  ));

  registry.register(ConsoleCommand(
    name: 'school-delete',
    description: 'school-delete <id> — delete an empty school (superadmin only; refused while anything references it)',
    handler: (args) async {
      final id = int.tryParse(args.isEmpty ? '' : args[0]);
      if (id == null) return 'Usage: school-delete <id>';
      try {
        await vm.delete(id);
        return 'Deleted school $id.';
      } catch (e) {
        return 'Delete failed: $e';
      }
    },
  ));
}

({int? id, String? error}) _parseRegion(String raw) {
  if (raw == '-') return (id: null, error: null);
  final id = Region.resolve(raw);
  if (id == null) {
    return (id: null, error: 'Unknown region "$raw". $_regionHelp');
  }
  return (id: id, error: null);
}

String _describe(School s) {
  final region = s.regionId != null ? Region.byId(s.regionId!) : null;
  return '${s.id} | ${s.schoolId} | ${s.schoolName} | ${region?.toString() ?? "(no region)"}';
}
