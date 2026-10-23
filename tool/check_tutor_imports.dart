// tool/check_tutor_imports.dart
// Fails when anything reachable from the tutor entry points imports an
// admin-only file. Run from the repo root after every piece:
//   dart run tool/check_tutor_imports.dart
// A new admin-only file goes in [_adminFiles]; a new admin command file is
// named *_admin_commands.dart and is caught by the pattern.
import 'dart:io';

import 'import_walk.dart';

const _entries = ['main_tutor.dart', 'console/main_tutor.dart'];

/// Admin-only files (relative to lib/). Each must exist, so a rename can't
/// leave a silent gap.
const _adminFiles = [
  'main.dart',
  'console/main.dart',
  'core/wiring/wire_admin.dart',
  // Wholly admin command files (the mixed ones were split into *_admin_commands.dart).
  'core/console/commands/admin_bootstrap_commands.dart',
  'core/console/commands/user_commands.dart',
  'core/console/commands/login_commands.dart',
  'core/console/commands/import_commands.dart',
  'core/console/commands/nla_report_commands.dart',
  'core/console/commands/aral_report_commands.dart',
  'core/console/commands/aral_export_commands.dart',
  'core/console/commands/tutor_section_commands.dart',
  'core/console/commands/report_settings_commands.dart',
  // Admin-only ViewModels, repositories and services.
  'viewmodels/sync_review_viewmodel.dart',
  'viewmodels/user_viewmodel.dart',
  'viewmodels/import_viewmodel.dart',
  'viewmodels/login_log_viewmodel.dart',
  'viewmodels/crla_import_viewmodel.dart',
  'viewmodels/aral_report_viewmodel.dart',
  'viewmodels/aral_roster_import_viewmodel.dart',
  'viewmodels/tutor_section_assignment_viewmodel.dart',
  'core/data/local/sync_review_local_sqlite.dart',
  'core/data/remote/import_conflict_repository_supabase.dart',
  'core/services/admin_bootstrap_service.dart',
  'core/services/sf1_importer.dart',
  'core/services/sf1_column_map.dart',
];

bool _isAdmin(String path) =>
    _adminFiles.contains(path) ||
    (path.startsWith('core/console/commands/') && path.endsWith('_admin_commands.dart')) ||
    RegExp(r'^core/data/\w+/import_conflict_repository_\w+\.dart$').hasMatch(path);

void main() {
  final missing = [
    for (final f in [..._entries, ..._adminFiles])
      if (!File('lib/$f').existsSync()) f,
  ];
  if (missing.isNotEmpty) {
    stderr.writeln('Listed files not found (run from the repo root; update the list after a rename):');
    for (final f in missing) {
      stderr.writeln('  lib/$f');
    }
    exit(2);
  }

  final violations = findForbiddenImports(
    packageRoot: '.',
    packageName: 'basa_capstone',
    entries: _entries,
    isForbidden: _isAdmin,
  );
  if (violations.isEmpty) {
    stdout.writeln('OK: no admin file reachable from the tutor entries');
    return;
  }
  stderr.writeln('Admin files reachable from the tutor build:');
  for (final v in violations) {
    stderr.writeln('  $v');
  }
  exit(1);
}
