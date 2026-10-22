// lib/core/console/commands/aral_material_command_helpers.dart
// Helpers shared by aral_material_commands.dart and aral_material_admin_commands.dart (no admin code here).

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
