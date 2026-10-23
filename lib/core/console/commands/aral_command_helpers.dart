// lib/core/console/commands/aral_command_helpers.dart
// Helpers shared by aral_commands.dart and aral_admin_commands.dart (no admin code here).

import '../../models/aral_class.dart';
import '../../models/aral_enrollment.dart';
import '../../services/aral_rules.dart' show aralClassCap;

class AralUsage implements Exception {
  final String message;
  const AralUsage(this.message);
}

int aralInt(String raw, String what) =>
    int.tryParse(raw) ?? (throw AralUsage('Invalid $what: "$raw" (expected a number)'));

/// One roster entry. [classNames] names the classes (AralViewModel.classNames).
String aralLine(AralEnrollment e, Map<int, String> names, [Map<int, String> classNames = const {}]) {
  final who = names[e.studentId] ?? 'student ${e.studentId}';
  final cls = e.classId == null ? 'unplaced' : 'class "${classNames[e.classId] ?? '#${e.classId}'}"';
  final status = e.isActive ? 'active' : 'exited ${e.exitedOn} (${e.exitReason?.value})';
  final suggested = e.suggestedKeyStage == null
      ? (e.basisSource == AralBasisSource.referral ? 'referred' : 'added by hand')
      : 'suggested ${e.suggestedTrack == null ? e.suggestedKeyStage!.label : '${e.suggestedKeyStage!.label} ${e.suggestedTrack!.label}'}';
  final basis = e.basisSource == AralBasisSource.referral
      ? 'referral by ${e.referredBy}: ${e.referralReason}'
      : e.basisLevel == null
          ? e.basisSource.value
          : '${e.basisSource.value} ${e.basisRound ?? ''} ${e.basisLevel}';
  return '#${e.id} | $who (${e.studentId}) | ${e.programLabel} | $status | $cls | '
      'basis: ${basis.trim()} | $suggested${e.notes == null ? '' : ' | notes: ${e.notes}'}';
}

/// One ARAL class: `#id | name | program | Grades band | tutor id` (+ room
/// and schedule when set, and `n/15 active` when [active] is given).
String aralClassLine(AralClass c, {int? active}) =>
    '#${c.id} | ${c.className} | ${c.program.label} | Grades ${c.gradeBand.value} | '
    'tutor ${c.tutorId ?? '-'}${c.room == null ? '' : ' | room ${c.room}'}'
    '${c.schedule == null ? '' : ' | ${c.schedule}'}${active == null ? '' : ' | $active/$aralClassCap active'}';
