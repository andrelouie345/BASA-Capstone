// lib/core/console/commands/login_commands.dart

import '../console_command.dart';
import '../console_registry.dart';
import '../../models/login_log.dart';
import '../../models/login_method.dart';
import '../../../viewmodels/login_log_viewmodel.dart';
import '../../../viewmodels/viewmodel_exception.dart';

/// The sign-in and admin/coordinator checks are in [LoginLogViewModel].
void registerLoginCommands(ConsoleRegistry registry, LoginLogViewModel vm) {
  registry.register(ConsoleCommand(
    name: 'login-log',
    description:
        'login-log <email> <true|false> <online|cachedSession> [failureReason] — record a test login attempt locally (admin/coordinator only; dev tool)',
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
      try {
        await vm.record(LoginLog(
          emailAttempted: args[0],
          success: success,
          method: method,
          timestamp: DateTime.now(),
          failureReason: args.length > 3 ? args.sublist(3).join(' ') : null,
        ));
      } on ViewModelException catch (e) {
        return e.message;
      }
      return 'Logged: ${args[0]} success=$success method=${method.name}';
    },
  ));

  registry.register(ConsoleCommand(
    name: 'login-recent',
    description: 'login-recent [limit] — recent login attempts from this device and the cloud, tagged by source (default 50; admin/coordinator only)',
    handler: (args) async {
      final limit = args.isNotEmpty ? int.tryParse(args[0]) ?? 50 : 50;
      try {
        await vm.loadRecent(limit: limit);
      } on ViewModelException catch (e) {
        return e.message;
      }
      if (vm.items.isEmpty) return 'No login attempts recorded.';
      return _formatLogs(vm);
    },
  ));

  registry.register(ConsoleCommand(
    name: 'login-history',
    description: 'login-history <userId> — login attempts for one user from this device and the cloud, tagged by source (admin/coordinator only)',
    handler: (args) async {
      if (args.isEmpty) return 'Usage: login-history <userId>';
      try {
        await vm.loadForUser(args[0]);
      } on ViewModelException catch (e) {
        return e.message;
      }
      if (vm.items.isEmpty) return 'No login attempts for user "${args[0]}".';
      return _formatLogs(vm);
    },
  ));
}

String _formatLogs(LoginLogViewModel vm) {
  final lines = vm.items.map((s) {
    final l = s.log;
    return '[${l.timestamp.toLocal()}] [${s.sourceLabel}] ${l.emailAttempted} - '
        '${l.success ? "OK" : "FAILED"} (${l.method.name})'
        '${l.failureReason != null ? " - ${l.failureReason}" : ""}';
  }).toList();
  if (vm.cloudError != null) lines.add('(cloud log unavailable, showing local only: ${vm.cloudError})');
  return lines.join('\n');
}
