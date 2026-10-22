// lib/core/console/commands/crla_threshold_command_helpers.dart
// Helpers shared by crla_threshold_commands.dart and crla_threshold_admin_commands.dart (no admin code here).

/// A bad argument: the handler returns the message as-is.
class CrlaThresholdUsage implements Exception {
  final String message;
  const CrlaThresholdUsage(this.message);
}

int crlaThresholdInt(String raw, String name) =>
    int.tryParse(raw) ?? (throw CrlaThresholdUsage('Invalid $name: "$raw" (expected a number)'));
