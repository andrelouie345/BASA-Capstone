// lib/core/console/commands/user_commands.dart


/// Commands for the user
library;


import '../console_command.dart';
import '../console_registry.dart';
import '../../models/user_role.dart';
import '../../../viewmodels/user_viewmodel.dart';

void registerUserCommands(ConsoleRegistry registry, UserViewModel vm) {
  registry.register(ConsoleCommand(
    name: 'user-create',
    description:
        'user-create <email> <role:admin|coordinator|tutor> <schoolId|-> <full name...> — create a new account (admin/coordinator only)',
    handler: (args) async {
      if (args.length < 4) {
        return 'Usage: user-create <email> <role:admin|coordinator|tutor> <schoolId|-> <full name...>';
      }
      final UserRole role;
      try {
        role = UserRole.fromString(args[1]);
      } catch (_) {
        return 'Invalid role: "${args[1]}" (expected admin, coordinator, or tutor)';
      }
      final schoolId = args[2] == '-' ? null : int.tryParse(args[2]);
      if (args[2] != '-' && schoolId == null) {
        return 'Invalid schoolId: "${args[2]}" (expected a number or "-")';
      }

      try {
        final tempPassword = await vm.create(
          email: args[0],
          fullName: args.sublist(3).join(' '),
          role: role,
          schoolId: schoolId,
        );
        final warn = vm.lastMirrorWarning;
        return 'Created: ${args[0]} as ${role.name} at school ${schoolId ?? "- (regional)"}.\n'
            'Temporary password: ${tempPassword ?? "(not returned — is the create-user function deployed?)"} '
            '(shown once; must be changed on first login).${warn == null ? '' : '\n$warn'}';
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
      final activeArg = args[1].toLowerCase();
      if (activeArg != 'true' && activeArg != 'false') {
        return 'Invalid value: "${args[1]}" (expected true or false)';
      }
      try {
        await vm.setActive(args[0], activeArg == 'true');
        final warn = vm.lastMirrorWarning;
        return 'Set ${args[0]} active=$activeArg.${warn == null ? '' : '\n$warn'}';
      } catch (e) {
        return 'Update failed: $e';
      }
    },
  ));

  registry.register(ConsoleCommand(
    name: 'user-list',
    description: 'user-list — list user accounts, by full name (admin/coordinator only)',
    handler: (_) async {
      try {
        await vm.loadAll();
        if (vm.items.isEmpty) return '(no users found)';
        return vm.items
            .map((u) =>
                '${u.id} | ${u.email} | ${u.fullName} | ${u.role.name} | '
                '${u.schoolId == null ? "school -" : "school ${u.schoolId}"} | ${u.isActive ? "active" : "inactive"}')
            .join('\n');
      } catch (e) {
        return 'List failed: $e';
      }
    },
  ));
}
