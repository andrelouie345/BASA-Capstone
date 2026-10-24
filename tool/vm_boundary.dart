// tool/vm_boundary.dart
// The ViewModel boundary (spec docs/superpowers/specs/2026-10-24-vm-completeness-design.md):
// console command files and lib/ui/ import only ViewModels, models and their
// framework, so every screen need is served by a ViewModel. Direct imports
// only (ViewModels themselves may import services). Used by
// tool/check_vm_boundary.dart.
import 'dart:io';

import 'package:path/path.dart' as p;

class BoundaryViolation {
  /// lib/-relative path of the importing file.
  final String file;

  /// lib/-relative path of the imported file, or the package: URI of another package.
  final String target;

  BoundaryViolation(this.file, this.target);

  String get line => '$file -> $target';
}

const _commandsDir = 'core/console/commands/';
const _uiDir = 'ui/';

/// Command files outside the rule, with the reason.
const exemptCommandFiles = [
  'test_data_commands.dart', // db-*: dev-only testTable commands, test repositories
  'debug_commands.dart', // log-filter, list-viewmodels: read the ViewModel registry
  'text_commands.dart', // dev-only text commands
];

/// Packages a screen must never reach directly (data access goes through ViewModels).
const _uiForbiddenPackages = ['supabase', 'sqflite_common', 'sqflite_common_ffi', 'sqlite3'];

final _directive = RegExp(r'''^\s*(?:import|export)\s+['"]([^'"]+)['"]''', multiLine: true);

/// Every forbidden direct import in command files and lib/ui/, sorted by line.
List<BoundaryViolation> findBoundaryViolations({required String packageRoot, required String packageName}) {
  final libDir = p.join(packageRoot, 'lib');
  final violations = <BoundaryViolation>[];
  for (final dir in [_commandsDir, _uiDir]) {
    final d = Directory(p.join(libDir, dir));
    if (!d.existsSync()) continue;
    for (final f in d.listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
      final file = p.relative(f.path, from: libDir).replaceAll(r'\', '/');
      if (file.startsWith(_commandsDir) && exemptCommandFiles.contains(file.substring(_commandsDir.length))) {
        continue;
      }
      for (final m in _directive.allMatches(f.readAsStringSync())) {
        final target = _target(m.group(1)!, file, packageName);
        if (target != null && !_allowed(file, target)) violations.add(BoundaryViolation(file, target));
      }
    }
  }
  violations.sort((a, b) => a.line.compareTo(b.line));
  return violations;
}

/// lib/-relative path for this package, the URI itself for another package, null for dart:.
String? _target(String uri, String from, String packageName) {
  if (uri.startsWith('dart:')) return null;
  if (uri.startsWith('package:')) {
    final prefix = 'package:$packageName/';
    return uri.startsWith(prefix) ? p.posix.normalize(uri.substring(prefix.length)) : uri;
  }
  return p.posix.normalize(p.posix.join(p.posix.dirname(from), uri));
}

bool _allowed(String file, String target) {
  final isUi = file.startsWith(_uiDir);
  if (target.startsWith('package:')) {
    if (!isUi) return false;
    final name = target.substring('package:'.length).split('/').first;
    return !_uiForbiddenPackages.contains(name);
  }
  if (target.startsWith('viewmodels/') || target.startsWith('core/models/')) return true;
  if (isUi) {
    return target.startsWith(_uiDir) || (file.startsWith('ui/debug/') && target.startsWith('core/console/'));
  }
  return target.startsWith('core/console/');
}

/// Lines found but not in [baseline] (new), and baseline lines no longer found (gone).
/// Blank and '#' lines of the baseline are ignored.
({List<String> added, List<String> gone}) compareToBaseline(List<BoundaryViolation> found, List<String> baseline) {
  final base = {
    for (final l in baseline.map((l) => l.trim()))
      if (l.isNotEmpty && !l.startsWith('#')) l,
  };
  final lines = {for (final v in found) v.line};
  return (
    added: [for (final l in lines) if (!base.contains(l)) l],
    gone: [for (final l in base) if (!lines.contains(l)) l],
  );
}
