// lib/core/console/commands/aral_session_command_helpers.dart
// Helpers for aral_session_commands.dart (no admin code here).

class AralSessionUsage implements Exception {
  final String message;
  const AralSessionUsage(this.message);
}
