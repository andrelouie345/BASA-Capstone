// lib/core/console/commands/phil_iri_command_helpers.dart
// Helpers shared by phil_iri_commands.dart and phil_iri_admin_commands.dart (no admin code here).

import '../../models/phil_iri_assessment.dart';

/// A bad argument: the handler returns the message as-is.
class PhilIriUsage implements Exception {
  final String message;
  const PhilIriUsage(this.message);
}

int philIriInt(String raw, String name) =>
    int.tryParse(raw) ?? (throw PhilIriUsage('Invalid $name: "$raw" (expected a number)'));

PhilIriRound philIriRound(String raw) {
  try {
    return PhilIriRound.fromString(raw.toLowerCase());
  } on ArgumentError {
    throw PhilIriUsage('Round is bosy, mosy1, mosy2, mosy3 or eosy (got "$raw")');
  }
}
