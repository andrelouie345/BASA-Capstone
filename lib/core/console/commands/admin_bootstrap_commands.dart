// lib/core/console/commands/admin_bootstrap_commands.dart
import 'package:supabase/supabase.dart' hide User;
import '../console_command.dart';
import '../console_registry.dart';
import '../logger.dart';
import '../../data/remote/supabase_config.dart';
import '../../services/admin_bootstrap_service.dart';
import '../../../viewmodels/admin_bootstrap_viewmodel.dart';

void registerAdminBootstrapCommands(
  ConsoleRegistry registry,
  SupabaseConfigStore config,
  Logger? logger,
) {
  registry.register(ConsoleCommand(
    name: 'bootstrap-admin',
    description:
        'bootstrap-admin <cloud|lan> <email> <full name...> — create the first admin for that Supabase project (only works once)',
    handler: (args) async {
      if (args.length < 3) {
        return 'Usage: bootstrap-admin <cloud|lan> <email> <full name...>';
      }
      final target = args[0];
      final email = args[1];
      final fullName = args.sublist(2).join(' ');

      final profile = switch (target) {
        'cloud' => config.cloud,
        'lan' => config.lan,
        _ => null,
      };
      if (profile == null) return 'Usage: bootstrap-admin <cloud|lan> <email> <full name...>';
      if (profile.url.isEmpty) return '$target.url not set. Use config-set-$target-url first.';

      final client = SupabaseClient(profile.url, profile.anonKey);
      final vm = AdminBootstrapViewModel(service: AdminBootstrapService(client), logger: logger);

      try {
        await vm.bootstrap(email, fullName);
        return 'Bootstrapped admin on $target: $email ($fullName). Default password is "password" — change it on first login.';
      } catch (e) {
        return 'Bootstrap failed: $e';
      }
    },
  ));
}