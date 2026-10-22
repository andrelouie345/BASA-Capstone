// lib/core/console/commands/aral_export_command_helpers.dart
// Helpers shared by aral_export_commands.dart and aral_export_admin_commands.dart (no admin code here).

import 'dart:convert';
import 'dart:io';

class AralExportUsage implements Exception {
  final String message;
  const AralExportUsage(this.message);
}

int aralExportInt(String raw, String what) =>
    int.tryParse(raw) ?? (throw AralExportUsage('Invalid $what: "$raw" (expected a number)'));

/// Splits trailing options: a number = sectionId, asof=YYYY-MM-DD.
(int?, DateTime?) aralExportOptions(Iterable<String> args, String usage) {
  int? sectionId;
  DateTime? asOf;
  for (final a in args) {
    if (a.startsWith('asof=')) {
      asOf = DateTime.tryParse(a.substring(5)) ?? (throw AralExportUsage('Invalid date in "$a" (YYYY-MM-DD)'));
    } else if (int.tryParse(a) != null) {
      sectionId = int.parse(a);
    } else {
      throw AralExportUsage('Unknown option "$a".\n$usage');
    }
  }
  return (sectionId, asOf);
}

Future<String> aralExportWrite(String path, List<int> bytes) async {
  final f = File(path);
  await f.writeAsBytes(bytes);
  return f.path;
}

List<int> aralExportUtf8(String s) => utf8.encode(s);
