// lib/core/console/commands/auth_commands.dart
import '../console_command.dart';
import '../console_registry.dart';
import '../../../viewmodels/auth_viewmodel.dart';

void registerAuthCommands(ConsoleRegistry registry, AuthViewModel authVm) {
  registry.register(ConsoleCommand(
    name: 'sign-in',
    description: 'sign-in <cloud|lan> <email> <password> — sign in and start a session',
    handler: (args) async {
      if (args.length < 3) return 'Usage: sign-in <cloud|lan> <email> <password>';
      final error = await authVm.signIn(
        target: args[0], email: args[1], password: args.sublist(2).join(' '));
      if (error != null) return error;
      final note = authVm.mustChangePassword ? ' (must change password)' : '';
      return 'Signed in as ${authVm.currentUser?.email} (${authVm.currentUser?.role.name})$note';
    },
  ));

  registry.register(ConsoleCommand(
    name: 'sign-out',
    description: 'sign-out — end the current session',
    handler: (_) async {
      await authVm.signOut();
      return 'Signed out.';
    },
  ));

  registry.register(ConsoleCommand(
    name: 'whoami',
    description: 'whoami — show the currently signed-in session, if any',
    handler: (_) async {
      if (!authVm.isSignedIn) return 'Not signed in.';
      final u = authVm.currentUser!;
      return 'Signed in as ${u.email} (${u.role.name})${authVm.mustChangePassword ? " — must change password" : ""}';
    },
  ));

  registry.register(ConsoleCommand(
    name: 'change-password',
    description: "change-password <new password...> — change the current session's password",
    handler: (args) async {
      if (args.isEmpty) return 'Usage: change-password <new password...>';
      if (!authVm.isSignedIn) return 'Not signed in.';
      final error = await authVm.changePassword(args.join(' '));
      return error ?? 'Password changed.';
    },
  ));
}