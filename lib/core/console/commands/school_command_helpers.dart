// lib/core/console/commands/school_command_helpers.dart
// Helpers shared by school_commands.dart and school_admin_commands.dart (no admin code here).

import '../../models/school.dart';
import '../../models/region.dart';

String schoolDescribe(School s) {
  final region = s.regionId != null ? Region.byId(s.regionId!) : null;
  return '${s.id} | ${s.schoolId} | ${s.schoolName} | ${region?.toString() ?? "(no region)"}';
}
