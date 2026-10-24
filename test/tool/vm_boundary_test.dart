// The ViewModel-boundary check behind tool/check_vm_boundary.dart, on small fixture packages.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../../tool/vm_boundary.dart';

void main() {
  late Directory root;

  setUp(() => root = Directory.systemTemp.createTempSync('basa_boundary_'));
  tearDown(() => root.deleteSync(recursive: true));

  void lib(String path, String content) {
    final f = File(p.join(root.path, 'lib', path));
    f.parent.createSync(recursive: true);
    f.writeAsStringSync(content);
  }

  List<String> scan() =>
      [for (final v in findBoundaryViolations(packageRoot: root.path, packageName: 'fx')) v.line];

  test('command file importing a service is a violation', () {
    lib('core/console/commands/a_commands.dart', "import '../../services/x_rules.dart';\n");

    expect(scan(), ['core/console/commands/a_commands.dart -> core/services/x_rules.dart']);
  });

  test('viewmodels, models, console framework and dart:io are allowed', () {
    lib('core/console/commands/a_commands.dart', '''
import 'dart:io';
import '../../../viewmodels/a_viewmodel.dart';
import 'package:fx/viewmodels/b_viewmodel.dart';
import '../../models/m.dart';
import 'package:fx/core/models/n.dart';
import '../console_command.dart';
import 'a_command_helpers.dart';
''');

    expect(scan(), isEmpty);
  });

  test('package import of a data package is a violation in commands', () {
    lib('core/console/commands/a_commands.dart', "import 'package:supabase/supabase.dart';\n");

    expect(scan(), ['core/console/commands/a_commands.dart -> package:supabase/supabase.dart']);
  });

  test('data, wiring, core viewmodels and release are forbidden in commands', () {
    lib('core/console/commands/a_commands.dart', '''
import '../../data/remote/r.dart';
import '../../wiring/w.dart';
import '../../viewmodels/viewmodel_registry.dart';
import '../../release.dart';
''');

    expect(scan(), [
      'core/console/commands/a_commands.dart -> core/data/remote/r.dart',
      'core/console/commands/a_commands.dart -> core/release.dart',
      'core/console/commands/a_commands.dart -> core/viewmodels/viewmodel_registry.dart',
      'core/console/commands/a_commands.dart -> core/wiring/w.dart',
    ]);
  });

  test('ui may import flutter but not sqflite', () {
    lib('ui/mobile/x.dart', '''
import 'package:flutter/material.dart';
import 'package:sqflite_common/sqflite.dart';
import '../../viewmodels/a_viewmodel.dart';
import '../windows/y.dart';
''');

    expect(scan(), ['ui/mobile/x.dart -> package:sqflite_common/sqflite.dart']);
  });

  test('ui may not import services, data or the console framework', () {
    lib('ui/mobile/x.dart', '''
import '../../core/services/s.dart';
import 'package:fx/core/data/local/d.dart';
import '../../core/console/console_session.dart';
''');

    expect(scan(), [
      'ui/mobile/x.dart -> core/console/console_session.dart',
      'ui/mobile/x.dart -> core/data/local/d.dart',
      'ui/mobile/x.dart -> core/services/s.dart',
    ]);
  });

  test('ui/debug may import the console framework', () {
    lib('ui/debug/overlay.dart', "import '../../core/console/console_session.dart';\n");

    expect(scan(), isEmpty);
  });

  test('ui may not touch .client', () {
    lib('ui/mobile/x.dart', 'void f(dynamic auth) { final c = auth.client; }\n');

    expect(scan(), ['ui/mobile/x.dart -> .client']);
  });

  test('ui may use .clientName', () {
    lib('ui/mobile/x.dart', 'void f(dynamic s) { final n = s.clientName; }\n');

    expect(scan(), isEmpty);
  });

  test('exempt command files are skipped', () {
    lib('core/console/commands/test_data_commands.dart', "import '../../data/local/t.dart';\n");
    lib('core/console/commands/debug_commands.dart', "import '../../viewmodels/viewmodel_registry.dart';\n");

    expect(scan(), isEmpty);
  });

  test('re-export through a model file is allowed', () {
    lib('core/models/m.dart', "export '../services/x_rules.dart' show XLevel;\n");
    lib('core/console/commands/a_commands.dart', "import '../../models/m.dart';\n");

    expect(scan(), isEmpty);
  });

  test('export directives are checked too', () {
    lib('core/console/commands/a_commands.dart', "export '../../services/x_rules.dart';\n");

    expect(scan(), ['core/console/commands/a_commands.dart -> core/services/x_rules.dart']);
  });

  test('compareToBaseline reports added and gone lines, ignoring blanks and comments', () {
    final found = [BoundaryViolation('a.dart', 'x.dart'), BoundaryViolation('b.dart', 'y.dart')];

    final r = compareToBaseline(found, ['b.dart -> y.dart', 'c.dart -> z.dart', '# note', '']);

    expect(r.added, ['a.dart -> x.dart']);
    expect(r.gone, ['c.dart -> z.dart']);
  });
}
