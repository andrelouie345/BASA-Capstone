// lib/core/console/commands/srp_command_helpers.dart
// Helpers shared by srp_commands.dart and srp_admin_commands.dart (no admin code here).

import '../../../viewmodels/srp_viewmodel.dart';

class SrpUsage implements Exception {
  final String message;
  const SrpUsage(this.message);
}

int srpInt(String raw, String what) =>
    int.tryParse(raw) ?? (throw SrpUsage('Invalid $what: "$raw" (expected a number)'));

// ---- classes (part 2) ----

String srpClassesText(List<SrpClassView> classes, String header) {
  final out = StringBuffer(header);
  if (classes.isEmpty) out.write('\n(no SRP classes)');
  for (final c in classes) {
    final k = c.srpClass;
    out.write('\n${k.className} (#${k.id}) · ${k.assessedLabel} · ${c.learners.length} learner(s)'
        ' · room ${k.room ?? '-'} · ${k.schedule ?? 'no schedule'} · tutor ${c.tutor?.fullName ?? (k.tutorId == null ? '-' : k.tutorId!)}');
    for (final (i, l) in c.learners.indexed) {
      out.write('\n  ${i + 1}. ${l.name} (#${l.member.studentId}${l.student == null ? '' : ', ${l.student!.lrn}'})'
          '${l.section == null ? '' : ' · G${l.section!.gradeLevel} ${l.section!.sectionName}'}');
    }
  }
  return out.toString();
}
