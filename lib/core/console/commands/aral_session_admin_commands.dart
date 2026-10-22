// lib/core/console/commands/aral_session_admin_commands.dart
// Admin build only: the admin half of aral_session_commands.dart (tutor build split, 2026-10-22).

import '../console_command.dart';
import '../console_registry.dart';
import '../../../viewmodels/aral_session_viewmodel.dart';
import 'aral_session_command_helpers.dart';

void registerAralSessionAdminCommands(ConsoleRegistry registry, AralSessionViewModel vm) {
  void add(String name, String description, Future<String> Function(List<String> args) handler) {
    registry.register(ConsoleCommand(
      name: name,
      description: description,
      handler: (args) async {
        try {
          final out = await handler(args);
          final warning = vm.lastWarning;
          return warning == null ? out : '$out\nNote: $warning';
        } on AralSessionUsage catch (e) {
          return e.message;
        } catch (e) {
          return '$name failed: $e';
        }
      },
    ));
  }

  add('aral-tutor-multi',
      'aral-tutor-multi <tutorId> [on|off] — allow (on) or stop allowing (off) a tutor several ARAL sessions on '
          'one date; without on/off shows the current setting (default: one per day)', (args) async {
    const usage = 'Usage: aral-tutor-multi <tutorId> [on|off]';
    if (args.isEmpty) throw const AralSessionUsage(usage);
    vm.lastWarning = null;
    if (args.length == 1) {
      final allowed = await vm.allowsMultipleSessionsPerDay(args[0]);
      return 'Tutor ${args[0]}: ${allowed ? 'several sessions per day allowed' : 'one session per day'}.';
    }
    final allowed = switch (args[1]) {
      'on' => true,
      'off' => false,
      _ => throw const AralSessionUsage(usage),
    };
    final s = await vm.setMultipleSessionsPerDay(args[0], allowed);
    return 'Tutor ${s.tutorId}: ${s.multipleSessionsPerDay ? 'several sessions per day allowed' : 'one session per day'}'
        '${allowed ? '' : ' (sessions already on the same date stay)'}.';
  });
}
