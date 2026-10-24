// lib/core/console/commands/version_commands.dart
import '../console_command.dart';
import '../console_registry.dart';
import '../../../viewmodels/auth_viewmodel.dart';
import '../../../viewmodels/viewmodel_exception.dart';

void registerVersionCommands(ConsoleRegistry registry, AuthViewModel authVm) {
  registry.register(ConsoleCommand(
    name: 'version-app',
    description: 'version-app — list the database migrations this build of BASA was made for (offline)',
    handler: (_) async {
      final lines = authVm.appRelease();
      return [...lines, '${lines.length} migrations, latest ${lines.last}'].join('\n');
    },
  ));

  registry.register(ConsoleCommand(
    name: 'version-check',
    description: "version-check — compare this app's migrations with the signed-in database's ledger (reports only)",
    handler: (_) async {
      try {
        final r = await authVm.versionReport();
        if (r.label.isEmpty) return r.message; // the fetch failed
        return r.message.isEmpty ? r.label : '${r.label}\n${r.message}';
      } on ViewModelException catch (e) {
        return e.message;
      }
    },
  ));
}
