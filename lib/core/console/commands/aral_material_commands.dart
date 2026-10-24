// lib/core/console/commands/aral_material_commands.dart

/// Commands for the ARAL material catalog (online: add/change/delete) and the
/// recommendations (offline, from this device's copy). One action per
/// command; the ViewModel does the checks. Materials are named by the #id
/// aral-materials shows; learners by their ARAL enrollment id (aral-roster).
library;

import '../console_command.dart';
import '../console_registry.dart';
import '../../../viewmodels/aral_material_viewmodel.dart';
import '../../../viewmodels/aral_viewmodel.dart';
import 'aral_material_command_helpers.dart';

/// [aral] only gives the learners' names for the recommendation lines.
void registerAralMaterialCommands(ConsoleRegistry registry, AralMaterialViewModel vm, AralViewModel aral) {
  void add(String name, String description, Future<String> Function(List<String> args) handler) {
    registry.register(ConsoleCommand(
      name: name,
      description: description,
      handler: (args) async {
        try {
          return await handler(args);
        } on AralMaterialUsage catch (e) {
          return e.message;
        } catch (e) {
          return '$name failed: $e';
        }
      },
    ));
  }

  add('aral-materials', 'aral-materials [active] — the ARAL material catalog on this device', (args) async {
    final list = await vm.catalog(activeOnly: args.isNotEmpty && args.first == 'active');
    if (list.isEmpty) return 'No ARAL materials on this device (add some, or pull-cloud).';
    return list.map(aralMaterialLine).join('\n');
  });

  add('aral-recommend', 'aral-recommend <enrollmentId> — the materials for one ARAL learner (offline)', (args) async {
    if (args.length != 1) throw const AralMaterialUsage('Usage: aral-recommend <enrollmentId>');
    final r = await vm.recommendations(aralMaterialInt(args[0], 'enrollmentId'));
    return aralMaterialRecommendation(r, await aral.learnerNames(r.enrollment.sectionId));
  });
}
