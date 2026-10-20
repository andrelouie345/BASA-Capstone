// lib/core/console/commands/auth_commands.dart
import '../console_command.dart';
import '../console_registry.dart';
import '../../../viewmodels/auth_viewmodel.dart';
import '../../services/offline_signin_rules.dart';

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
      final warning = authVm.versionWarning == null ? '' : '\n${authVm.versionWarning}';
      final offline = authVm.offlineWarning == null ? '' : '\n${authVm.offlineWarning}';
      return 'Signed in as ${authVm.currentUser?.email} (${authVm.currentUser?.role.name})$note$warning$offline';
    },
  ));

  registry.register(ConsoleCommand(
    name: 'sign-in-offline',
    description: "sign-in-offline <email> <password> — sign in without a connection (this device's owner, within the offline window)",
    handler: (args) async {
      if (args.length < 2) return 'Usage: sign-in-offline <email> <password>';
      final error = await authVm.signInOffline(email: args[0], password: args.sublist(1).join(' '));
      if (error != null) return error;
      return 'Signed in offline as ${authVm.currentUser?.email} (${authVm.currentUser?.role.name}). '
          'Server work needs an online sign-in.';
    },
  ));

  registry.register(ConsoleCommand(
    name: 'offline-status',
    description: 'offline-status — whose offline sign-in this device holds, its window and failed attempts (no password shown)',
    handler: (_) async {
      final c = await authVm.offlineCredential();
      if (c == null) return 'Offline sign-in: not set up on this device.';
      final user = await authVm.offlineCredentialUser();
      final days = await authVm.offlineWindowDays(user?.schoolId);
      final until = DateTime.parse(c.lastOnlineAt).add(Duration(days: days));
      return 'Offline sign-in: ${c.email}, last online ${c.lastOnlineAt}, window $days days '
          '(until ${until.toIso8601String()}), failed attempts ${c.failedAttempts}/$offlineMaxFailedAttempts';
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
      return 'Signed in as ${u.email} (${u.role.name})${authVm.mustChangePassword ? " — must change password" : ""}'
          '${authVm.isOffline ? " — offline" : ""}';
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