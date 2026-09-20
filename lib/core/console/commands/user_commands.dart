// lib/core/console/commands/user_commands.dart


/// Commands for the user
library;


import '../console_command.dart';
import '../console_registry.dart';
import '../logger.dart';
import '../../models/user.dart';
import '../../models/user_role.dart';
import '../../data/remote/user_repository_supabase.dart';
import '../../../viewmodels/user_viewmodel.dart';
import '../../../viewmodels/auth_viewmodel.dart';

void registerUserCommands(ConsoleRegistry registry, AuthViewModel authVm, Logger? logger) {
  registry.register(ConsoleCommand(
    name: 'user-create',
    description:
        'user-create <email> <role:admin|coordinator|tutor> <full name...> — create a new account (requires sign-in)',
    handler: (args) async {
      if (args.length < 3) {
        return 'Usage: user-create <email> <role:admin|coordinator|tutor> <full name...>';
      }
      final client = authVm.client;
      if (client == null) return 'Not signed in. Use sign-in <cloud|lan> <email> <password> first.';

      final email = args[0];
      UserRole role;
      try {
        role = UserRole.fromString(args[1]);
      } catch (_) {
        return 'Invalid role: "${args[1]}" (expected admin, coordinator, or tutor)';
      }

      final vm = UserViewModel(repo: UserRepositorySupabase(client), logger: logger);
      try {
        await vm.create(User(
          id: '',
          email: email,
          fullName: args.sublist(2).join(' '),
          role: role,
          createdAt: DateTime.now(),
          createdBy: authVm.currentUser?.id, // now resolved — was null before signIn() existed
        ));
        return 'Created: $email as ${role.name}.';
      } catch (e) {
        return 'Create failed: $e';
      }
    },
  ));

  registry.register(ConsoleCommand(
    name: 'user-set-active',
    description: 'user-set-active <userId> <true|false> — activate/deactivate an account (admin/coordinator only)',
    handler: (args) async {
      if (args.length < 2) return 'Usage: user-set-active <userId> <true|false>';
      final client = authVm.client;
      if (client == null) return 'Not signed in. Use sign-in <cloud|lan> <email> <password> first.';

      final actingRole = authVm.currentUser?.role;
      if (actingRole != UserRole.admin && actingRole != UserRole.coordinator) {
        return 'Forbidden: admin or coordinator only.';
      }

      final activeArg = args[1].toLowerCase();
      if (activeArg != 'true' && activeArg != 'false') {
        return 'Invalid value: "${args[1]}" (expected true or false)';
      }

      final vm = UserViewModel(repo: UserRepositorySupabase(client), logger: logger);
      try {
        await vm.setActive(args[0], activeArg == 'true');
        return 'Set ${args[0]} active=$activeArg.';
      } catch (e) {
        return 'Update failed: $e';
      }
    },
  ));

  registry.register(ConsoleCommand(
    name: 'user-list',
    description: 'user-list — list all user accounts (admin/coordinator only)',
    handler: (_) async {
      final guardError = authVm.requireActiveSession();
      if (guardError != null) return guardError;
      final client = authVm.client!;

      final actingRole = authVm.currentUser?.role;
      if (actingRole != UserRole.admin && actingRole != UserRole.coordinator) {
        return 'Forbidden: admin or coordinator only.';
      }

      final vm = UserViewModel(repo: UserRepositorySupabase(client), logger: logger);
      try {
        await vm.refresh();
        if (vm.items.isEmpty) return '(no users found)';
        return vm.items
            .map((u) =>
                '${u.id} | ${u.email} | ${u.fullName} | ${u.role.name} | ${u.isActive ? "active" : "inactive"}')
            .join('\n');
      } catch (e) {
        return 'List failed: $e';
      }
    },
  ));
}