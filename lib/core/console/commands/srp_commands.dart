// lib/core/console/commands/srp_commands.dart

/// Summer Remediation Program (SRP), part 1: learners not grade level ready by
/// the end of the year, ranked weakest first, the weakest per section
/// recommended. Options:
///   per=N                  recommended learners per section (default 15)
///   show=all|recommended   every candidate, or only the recommended (default all)
///   sections=ID,...        only these sections (default: every Grade 4-10 section)
///   asof=YYYY-MM-DD        results assessed by that date (default today)
library;


import '../console_command.dart';
import '../console_registry.dart';
import '../../../viewmodels/srp_viewmodel.dart';
import 'srp_command_helpers.dart';

void registerSrpCommands(ConsoleRegistry registry, SrpViewModel vm) {
  void add(String name, String description, Future<String> Function(List<String> args) handler) {
    registry.register(ConsoleCommand(
      name: name,
      description: description,
      handler: (args) async {
        try {
          return await handler(args);
        } on SrpUsage catch (e) {
          return e.message;
        } catch (e) {
          return '$name failed: $e';
        }
      },
    ));
  }

  add('srp-classes', 'srp-classes <schoolId> <schoolYear> — the SRP classes on this device (a tutor: their own)',
      (args) async {
    if (args.length != 2) throw const SrpUsage('Usage: srp-classes <schoolId> <schoolYear>');
    final classes = await vm.classes(schoolId: srpInt(args[0], 'schoolId'), schoolYear: args[1]);
    return srpClassesText(classes, 'SRP classes | school ${args[0]} | ${args[1]}');
  });
}
