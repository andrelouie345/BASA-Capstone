// lib/core/console/commands/admin_bootstrap_commands.dart
import '../console_command.dart';
import '../console_registry.dart';
import '../../../viewmodels/admin_bootstrap_viewmodel.dart';

void registerAdminBootstrapCommands(ConsoleRegistry registry, AdminBootstrapViewModel vm) {
  registry.register(ConsoleCommand(
    name: 'bootstrap-admin',
    description:
        'bootstrap-admin <cloud|lan> <email> <full name...> — create the first admin for that Supabase project (only works once)',
    handler: (args) async {
      const usage = 'Usage: bootstrap-admin <cloud|lan> <email> <full name...>';
      if (args.length < 3 || (args[0] != 'cloud' && args[0] != 'lan')) return usage;
      final target = args[0];
      final email = args[1];
      final fullName = args.sublist(2).join(' ');
      try {
        final tempPassword = await vm.bootstrap(target, email, fullName);
        return 'Bootstrapped admin on $target: $email ($fullName). '
            'Temporary password: ${tempPassword ?? "(not returned — is the bootstrap-admin function deployed?)"} '
            '(shown once; must be changed on first login).';
      } catch (e) {
        return 'Bootstrap failed: $e';
      }
    },
  ));
}
