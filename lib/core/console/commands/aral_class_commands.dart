// lib/core/console/commands/aral_class_commands.dart

/// ARAL classes, both builds: read the classes (a tutor sees the classes they
/// teach). One action per command; the ViewModel does the checks. Changing
/// classes is in aral_class_admin_commands.dart (admin build).
library;

import '../console_command.dart';
import '../console_registry.dart';
import '../../../viewmodels/aral_class_viewmodel.dart';
import 'aral_command_helpers.dart';

void registerAralClassCommands(ConsoleRegistry registry, AralClassViewModel vm) {
  void add(String name, String description, Future<String> Function(List<String> args) handler) {
    registry.register(ConsoleCommand(
      name: name,
      description: description,
      handler: (args) async {
        try {
          return await handler(args);
        } on AralUsage catch (e) {
          return e.message;
        } catch (e) {
          return '$name failed: $e';
        }
      },
    ));
  }

  add('aral-classes', 'aral-classes <schoolId> <schoolYear> — the school\'s ARAL classes (a tutor: their own)',
      (args) async {
    if (args.length != 2) throw const AralUsage('Usage: aral-classes <schoolId> <schoolYear>');
    final list = await vm.classes(schoolId: aralInt(args[0], 'schoolId'), schoolYear: args[1]);
    if (list.isEmpty) return 'No ARAL classes for that school and year on this device.';
    return list.map(aralClassLine).join('\n');
  });

  add('aral-class-show', 'aral-class-show <classId> — one ARAL class', (args) async {
    if (args.length != 1) throw const AralUsage('Usage: aral-class-show <classId>');
    final c = await vm.getClass(aralInt(args[0], 'classId'));
    return [
      aralClassLine(c),
      'school ${c.schoolId}, ${c.schoolYear}',
      if (c.notes != null) 'notes: ${c.notes}',
    ].join('\n');
  });
}
