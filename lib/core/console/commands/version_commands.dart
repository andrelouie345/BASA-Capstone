// lib/core/console/commands/version_commands.dart
import '../console_command.dart';
import '../console_registry.dart';
import '../../release.dart';
import '../../services/version_check.dart';
import '../../../viewmodels/auth_viewmodel.dart';

void registerVersionCommands(ConsoleRegistry registry, AuthViewModel authVm) {
  registry.register(ConsoleCommand(
    name: 'version-app',
    description: 'version-app — list the database migrations this build of BASA was made for (offline)',
    handler: (_) async {
      final lines = [for (final e in basaMigrations.entries) '${e.key}_${e.value}'];
      return [...lines, '${lines.length} migrations, latest ${lines.last}'].join('\n');
    },
  ));

  registry.register(ConsoleCommand(
    name: 'version-check',
    description: "version-check — compare this app's migrations with the signed-in database's ledger (reports only)",
    handler: (_) async {
      if (!authVm.isSignedIn) return authVm.requireActiveSession()!;
      try {
        final check = await authVm.checkVersion();
        final message = versionMessage(check);
        return message.isEmpty ? versionLabel(check.verdict) : '${versionLabel(check.verdict)}\n$message';
      } catch (e) {
        return fetchFailedMessage(e);
      }
    },
  ));
}
