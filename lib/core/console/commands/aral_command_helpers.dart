// lib/core/console/commands/aral_command_helpers.dart
// Helpers shared by aral_commands.dart and aral_admin_commands.dart (no admin code here).

import '../../models/aral_enrollment.dart';

class AralUsage implements Exception {
  final String message;
  const AralUsage(this.message);
}

int aralInt(String raw, String what) =>
    int.tryParse(raw) ?? (throw AralUsage('Invalid $what: "$raw" (expected a number)'));

String aralLine(AralEnrollment e, Map<int, String> names) {
  final who = names[e.studentId] ?? 'student ${e.studentId}';
  final status = e.isActive ? 'active' : 'exited ${e.exitedOn} (${e.exitReason?.value})';
  final suggested = e.suggestedKeyStage == null
      ? 'added by hand'
      : 'suggested ${e.suggestedTrack == null ? e.suggestedKeyStage!.label : '${e.suggestedKeyStage!.label} ${e.suggestedTrack!.label}'}';
  final basis = e.basisLevel == null ? e.basisSource.value : '${e.basisSource.value} ${e.basisRound ?? ''} ${e.basisLevel}';
  return '#${e.id} | $who (${e.studentId}) | ${e.programLabel} | $status | tutor ${e.tutorId ?? '-'} | '
      'basis: ${basis.trim()} | $suggested${e.notes == null ? '' : ' | notes: ${e.notes}'}';
}
