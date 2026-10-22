// lib/core/console/commands/sync_command_helpers.dart
// Helpers shared by sync_commands.dart and sync_admin_commands.dart (no admin code here).

/// Local time, to the minute.
String syncWhen(DateTime t) => t.toLocal().toString().substring(0, 16);
