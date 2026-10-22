// lib/core/console/commands/aral_export_commands.dart

/// ARAL-Reading exports (IE4): the implementation report into its template
/// and as CSV, the roster and the check-in report as CSV. Admins and
/// coordinators of the school. Paths with spaces go in double quotes.
library;


import '../console_command.dart';
import '../console_registry.dart';
import '../../../viewmodels/aral_viewmodel.dart';
import 'aral_export_command_helpers.dart';

void registerAralExportCommands(ConsoleRegistry registry, AralViewModel aral) {
  void add(String name, String description, Future<String> Function(List<String> args) handler) {
    registry.register(ConsoleCommand(
      name: name,
      description: description,
      handler: (args) async {
        try {
          return await handler(args);
        } on AralExportUsage catch (e) {
          return e.message;
        } catch (e) {
          return '$name failed: $e';
        }
      },
    ));
  }

  add('aral-export-roster',
      'aral-export-roster <schoolId> <schoolYear> <out.csv> [sectionId] — the ARAL roster as CSV', (args) async {
    const usage = 'Usage: aral-export-roster <schoolId> <schoolYear> <out.csv> [sectionId]';
    if (args.length < 3) throw const AralExportUsage(usage);
    final (sectionId, asOf) = aralExportOptions(args.skip(3), usage);
    if (asOf != null) throw const AralExportUsage(usage);
    final csv = await aral.rosterCsv(schoolId: aralExportInt(args[0], 'schoolId'), schoolYear: args[1], sectionId: sectionId);
    return 'Wrote ${await aralExportWrite(args[2], aralExportUtf8(csv))}.';
  });
}
