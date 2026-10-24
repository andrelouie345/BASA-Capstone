// tool/check_vm_boundary.dart
// Fails when a console command file or a lib/ui/ file imports something other
// than ViewModels, models and its framework (services, data, wiring, release,
// data packages). Run from the repo root after every piece:
//   dart run tool/check_vm_boundary.dart
// tool/vm_boundary_baseline.txt lists the violations left from before the rule
// (shrink-only): a fix removes its line; a new violation or a stale line fails.
// A screen need goes through a ViewModel method or a model getter instead.
import 'dart:io';

import 'vm_boundary.dart';

const _baseline = 'tool/vm_boundary_baseline.txt';

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
  final baselineFile = File(_baseline);
  if (!baselineFile.existsSync()) {
    stderr.writeln('$_baseline not found (run from the repo root).');
    exit(2);
  }

  final found = findBoundaryViolations(packageRoot: '.', packageName: 'basa_capstone');
  final r = compareToBaseline(found, baselineFile.readAsLinesSync());
  if (r.added.isEmpty && r.gone.isEmpty) {
    stdout.writeln('OK: no new ViewModel-boundary imports (${found.length} baseline lines left)');
    return;
  }
  if (r.added.isNotEmpty) {
    stderr.writeln('New forbidden imports (reach it through a ViewModel or a model instead):');
    for (final l in r.added) {
      stderr.writeln('  $l');
    }
  }
  if (r.gone.isNotEmpty) {
    stderr.writeln('Baseline lines no longer found (remove them from $_baseline):');
    for (final l in r.gone) {
      stderr.writeln('  $l');
    }
  }
  exit(1);
}
