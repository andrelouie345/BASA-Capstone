// lib/core/console/commands/aral_material_command_helpers.dart
// Helpers shared by aral_material_commands.dart and aral_material_admin_commands.dart (no admin code here).

import '../../../viewmodels/aral_material_viewmodel.dart';
import '../../models/aral_material.dart';

class AralMaterialUsage implements Exception {
  final String message;
  const AralMaterialUsage(this.message);
}

int aralMaterialInt(String raw, String what) =>
    int.tryParse(raw) ?? (throw AralMaterialUsage('Invalid $what: "$raw" (expected a number)'));

String aralMaterialLine(AralMaterial m) => '#${m.id} | ${m.title} | ${m.programLabel} | ${m.kind.label} | ${m.language} | '
    'Grades ${m.minGrade}-${m.maxGrade} | ${m.schoolId == null ? 'region-wide' : 'school ${m.schoolId}'}'
    '${m.isActive ? '' : ' | RETIRED'} | file: ${m.fileName ?? '-'} | link: ${m.link ?? '-'}';

/// [names] = AralViewModel.learnerNames of the learner's section (studentId ->
/// "Last, First"); a learner whose name isn't on this device shows as
/// `student 191` (F23: `191: Last, First` otherwise).
String aralMaterialRecommendation(AralRecommendation r, Map<int, String> names) {
  final e = r.enrollment;
  final name = names[e.studentId];
  final who = name == null ? 'student ${e.studentId}' : '${e.studentId}: $name';
  final head = '#${e.id} | $who | Grade ${r.grade} | ${e.programLabel}';
  if (r.materials.isEmpty) return '$head\n  ${r.note ?? 'nothing'}';
  return [
    head,
    for (final x in r.materials)
      '  - ${x.material.title} (${x.material.kind.label}, ${x.material.language})'
          '${x.material.fileName == null ? '' : ' | file: ${x.material.fileName}'}'
          ' | link: ${x.link == null ? 'none yet' : '${x.link}${x.schoolLink ? ' (school link)' : ''}'}',
  ].join('\n');
}
