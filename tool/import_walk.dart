// tool/import_walk.dart
// Follows import/export/part directives through a package's lib/ folder and
// reports every forbidden file reachable from the entry points, with the
// chain that reaches it. Used by tool/check_tutor_imports.dart.
import 'dart:collection';
import 'dart:io';

import 'package:path/path.dart' as p;

class ImportViolation {
  /// The forbidden file, relative to lib/ with '/'.
  final String forbidden;

  /// Entry first, forbidden file last (all relative to lib/).
  final List<String> chain;

  const ImportViolation(this.forbidden, this.chain);

  @override
  String toString() => '$forbidden\n    via ${chain.join('\n     -> ')}';
}

final _directive = RegExp(r'''^\s*(?:import|export|part)\s+['"]([^'"]+)['"]''', multiLine: true);

/// [entries] and the paths given to [isForbidden] are relative to lib/ with '/'.
/// Breadth-first, so each chain is a shortest one; each file is read once.
List<ImportViolation> findForbiddenImports({
  required String packageRoot,
  required String packageName,
  required List<String> entries,
  required bool Function(String libPath) isForbidden,
}) {
  final libDir = p.join(packageRoot, 'lib');
  final parent = <String, String?>{for (final e in entries) e: null};
  final queue = Queue<String>.of(entries);
  final violations = <ImportViolation>[];

  List<String> chainTo(String file) {
    final chain = <String>[];
    for (String? f = file; f != null; f = parent[f]) {
      chain.insert(0, f);
    }
    return chain;
  }

  while (queue.isNotEmpty) {
    final file = queue.removeFirst();
    if (isForbidden(file)) {
      violations.add(ImportViolation(file, chainTo(file)));
      continue; // what a forbidden file imports is its own business
    }
    final source = File(p.join(libDir, file));
    if (!source.existsSync()) continue;
    for (final m in _directive.allMatches(source.readAsStringSync())) {
      final target = _resolve(m.group(1)!, file, packageName);
      if (target == null || parent.containsKey(target)) continue;
      parent[target] = file;
      queue.add(target);
    }
  }
  return violations;
}

/// lib/-relative path of [uri] imported from [from], or null when it is
/// outside this package (dart:, other packages).
String? _resolve(String uri, String from, String packageName) {
  if (uri.startsWith('dart:')) return null;
  if (uri.startsWith('package:')) {
    final prefix = 'package:$packageName/';
    return uri.startsWith(prefix) ? p.posix.normalize(uri.substring(prefix.length)) : null;
  }
  return p.posix.normalize(p.posix.join(p.posix.dirname(from), uri));
}
