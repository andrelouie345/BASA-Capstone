// lib/core/console/commands/aral_checkin_command_helpers.dart
// Helpers shared by aral_checkin_commands.dart and aral_checkin_admin_commands.dart (no admin code here).

import '../../services/aral_checkin_rules.dart';

class AralCheckinUsage implements Exception {
  final String message;
  const AralCheckinUsage(this.message);
}

int aralCheckinInt(String raw, String what) =>
    int.tryParse(raw) ?? (throw AralCheckinUsage('Invalid $what: "$raw" (expected a number)'));

String aralCheckinPct(AralCheckinScore s) => '${s.percent.toStringAsFixed(0)}%';

String aralCheckinVerdict(AralCheckinScore s, int passPct) => s.passes(passPct) ? 'Met' : 'Not met';
