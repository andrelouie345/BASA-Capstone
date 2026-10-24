// tool/check_vm_boundary.dart
// Fails when a console command file or a lib/ui/ file imports something other
// than ViewModels, models and its framework (services, data, wiring, release,
// data packages). Run from the repo root after every piece:
//   dart run tool/check_vm_boundary.dart
// A screen need goes through a ViewModel method or a model getter instead.
import 'dart:io';

import 'vm_boundary.dart';

void main() {
  final missing = [
    for (final f in exemptCommandFiles)
      if (!File('lib/core/console/commands/$f').existsSync()) f,
  ];
  if (missing.isNotEmpty) {
    stderr.writeln('Exempt files not found (run from the repo root; update the list after a rename):');
    for (final f in missing) {
      stderr.writeln('  lib/core/console/commands/$f');
    }
    exit(2);
  }

  final found = findBoundaryViolations(packageRoot: '.', packageName: 'basa_capstone');
  if (found.isEmpty) {
    stdout.writeln('OK: commands and ui import only ViewModels, models and their framework');
    return;
  }
  stderr.writeln('Forbidden imports (reach it through a ViewModel or a model instead):');
  for (final v in found) {
    stderr.writeln('  ${v.line}');
  }
  exit(1);
}
