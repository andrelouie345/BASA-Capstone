// The import walk behind tool/check_tutor_imports.dart, on small fixture packages.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../../tool/import_walk.dart';

void main() {
  late Directory root;

  setUp(() => root = Directory.systemTemp.createTempSync('basa_walk_'));
  tearDown(() => root.deleteSync(recursive: true));

  void lib(String path, String content) {
    final f = File(p.join(root.path, 'lib', path));
    f.parent.createSync(recursive: true);
    f.writeAsStringSync(content);
  }

  List<ImportViolation> walk(List<String> entries) => findForbiddenImports(
        packageRoot: root.path,
        packageName: 'fx',
        entries: entries,
        isForbidden: (path) => path.endsWith('_admin_commands.dart'),
      );

  test('finds a forbidden file through a chain', () {
    lib('entry.dart', "import 'a.dart';\nvoid main() {}\n");
    lib('a.dart', "import 'package:fx/b_admin_commands.dart';\n");
    lib('b_admin_commands.dart', '');

    final v = walk(['entry.dart']);

    expect(v, hasLength(1));
    expect(v.single.forbidden, 'b_admin_commands.dart');
    expect(v.single.chain, ['entry.dart', 'a.dart', 'b_admin_commands.dart']);
  });

  test('clean tree has no violations', () {
    lib('entry.dart', "import 'core/a.dart';\n");
    lib('core/a.dart', "export '../b.dart';\n");
    lib('b.dart', '');

    expect(walk(['entry.dart']), isEmpty);
  });

  test('cycles terminate', () {
    lib('entry.dart', "import 'a.dart';\n");
    lib('a.dart', "import 'b.dart';\n");
    lib('b.dart', "import 'a.dart';\nimport 'x_admin_commands.dart';\n");
    lib('x_admin_commands.dart', '');

    final v = walk(['entry.dart']);

    expect(v, hasLength(1));
    expect(v.single.chain, ['entry.dart', 'a.dart', 'b.dart', 'x_admin_commands.dart']);
  });

  test('dart: and other packages are ignored', () {
    lib('entry.dart', "import 'dart:io';\nimport 'package:other/y_admin_commands.dart';\n");

    expect(walk(['entry.dart']), isEmpty);
  });

  test('relative paths resolve from the importing file', () {
    lib('console/main_x.dart', "import '../core/c.dart';\n");
    lib('core/c.dart', "import 'commands/z_admin_commands.dart';\n");
    lib('core/commands/z_admin_commands.dart', '');

    final v = walk(['console/main_x.dart']);

    expect(v.single.chain, ['console/main_x.dart', 'core/c.dart', 'core/commands/z_admin_commands.dart']);
  });
}
