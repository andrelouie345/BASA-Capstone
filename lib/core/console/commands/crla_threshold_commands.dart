// lib/core/console/commands/crla_threshold_commands.dart

/// Commands for the adjustable CRLA thresholds (online) and re-scoring.
library;

import '../console_command.dart';
import '../console_registry.dart';
import '../../../viewmodels/crla_threshold_viewmodel.dart';
import 'crla_threshold_command_helpers.dart';

void registerCrlaThresholdCommands(ConsoleRegistry registry, CrlaThresholdViewModel vm) {
  void add(String name, String description, Future<String> Function(List<String> args) handler) {
    registry.register(ConsoleCommand(
      name: name,
      description: description,
      handler: (args) async {
        try {
          return await handler(args);
        } on CrlaThresholdUsage catch (e) {
          return e.message;
        } catch (e) {
          return '$name failed: $e';
        }
      },
    ));
  }

  add('crla-thresholds', 'crla-thresholds [schoolId] — region and school CRLA threshold rows and the values that apply',
      (args) async {
    final schoolId = args.isEmpty ? null : crlaThresholdInt(args[0], 'schoolId');
    final layers = await vm.thresholdLayers(schoolId);
    final region = layers.region?.settings ?? const {};
    final school = layers.school?.settings ?? const {};
    final out = StringBuffer('Region row: ${layers.region == null ? 'none (defaults)' : '${region.length} key(s)'}');
    if (schoolId != null) {
      out.write('; school $schoolId override: ${layers.school == null ? 'none' : '${school.length} key(s)'}');
    }
    final defaults = layers.defaults.toMap();
    layers.effective.toMap().forEach((key, value) {
      final from = school.containsKey(key) ? 'school' : (region.containsKey(key) ? 'region' : 'default');
      final note = from == 'default' ? '' : '   ($from; default ${defaults[key]})';
      out.write('\n  ${key.padRight(36)} $value$note');
    });
    return out.toString();
  });
}
