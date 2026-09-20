// lib/core/console/commands/login_commands.dart

import 'package:basa_capstone/viewmodels/auth_viewmodel.dart';
import 'package:basa_capstone/core/models/user_role.dart';
import '../console_command.dart';
import '../console_registry.dart';
import '../../models/login_log.dart';
import '../../models/login_method.dart';
import '../../../viewmodels/login_log_viewmodel.dart';

void registerLoginCommands(ConsoleRegistry registry, LoginLogViewModel vm, AuthViewModel authVm) {
  registry.register(ConsoleCommand(
    name: 'login-log',
    description:
        'login-log <email> <true|false> <online|cachedSession> [failureReason] — record a login attempt',
    handler: (args) async {
      if (args.length < 3) {
        return 'Usage: login-log <email> <true|false> <online|cachedSession> [failureReason]';
      }
      final successArg = args[1].toLowerCase();
      if (successArg != 'true' && successArg != 'false') {
        return 'Invalid success value: "${args[1]}" (expected "true" or "false")';
      }
      final success = successArg == 'true';
      LoginMethod method;
      try {
        method = LoginMethod.fromString(args[2]);
      } catch (_) {
        return 'Invalid method: "${args[2]}" (expected "online" or "cachedSession")';
      }
      await vm.record(LoginLog(
        emailAttempted: args[0],
        success: success,
        method: method,
        timestamp: DateTime.now(),
        failureReason: args.length > 3 ? args.sublist(3).join(' ') : null,
      ));
      return 'Logged: ${args[0]} success=$success method=${method.name}';
    },
  ));

  registry.register(ConsoleCommand(
    name: 'login-recent',
    description: 'login-recent [limit] — show recent login attempts (default 50)',
    handler: (args) async {
      final guardError = authVm.requireActiveSession();
      if (guardError != null) return guardError;
      final client = authVm.client!;
      final actingRole = authVm.currentUser?.role;
      if (actingRole != UserRole.admin && actingRole != UserRole.coordinator) {
        return 'Forbidden: admin or coordinator only.';
      }
      final limit = args.isNotEmpty ? int.tryParse(args[0]) ?? 50 : 50;
      await vm.loadRecent(limit: limit);
      if (vm.items.isEmpty) return 'No login attempts recorded.';
      return vm.items
          .map((l) =>
              '[${l.timestamp}] ${l.emailAttempted} - ${l.success ? "OK" : "FAILED"} (${l.method.name})'
              '${l.failureReason != null ? " - ${l.failureReason}" : ""}')
          .join('\n');
    },
  ));

  registry.register(ConsoleCommand(
    name: 'login-history',
    description: 'login-history <userId> — show login attempts for a specific user',
    handler: (args) async {
      if (args.isEmpty) return 'Usage: login-history <userId>';
      await vm.loadForUser(args[0]);
      if (vm.items.isEmpty) return 'No login attempts for user "${args[0]}".';
      return vm.items
          .map((l) =>
              '[${l.timestamp}] ${l.emailAttempted} - ${l.success ? "OK" : "FAILED"} (${l.method.name})')
          .join('\n');
    },
  ));
}