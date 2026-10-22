// The app's data folder per build (<documents>/BASA/<variant>) and the
// one-time move of the old desktop files out of Documents.
import 'dart:io';

import 'package:basa_capstone/core/wiring/data_dir.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory docs;

  setUp(() => docs = Directory.systemTemp.createTempSync('basa_docs_'));
  tearDown(() => docs.deleteSync(recursive: true));

  void put(String dir, String name, String content) {
    Directory(dir).createSync(recursive: true);
    File(p.join(dir, name)).writeAsStringSync(content);
  }

  String? read(String dir, String name) {
    final f = File(p.join(dir, name));
    return f.existsSync() ? f.readAsStringSync() : null;
  }

  test('moves legacy files into BASA/admin', () async {
    put(docs.path, 'basa_local.db', 'db');
    put(docs.path, 'supabase_config.json', 'cfg');
    put(docs.path, 'sf1_column_map.json', 'map');

    final dir = await prepareDataDir(documentsPath: docs.path, variant: 'admin', moveLegacy: true);

    expect(p.equals(dir, p.join(docs.path, 'BASA', 'admin')), isTrue);
    expect(read(dir, 'basa_local.db'), 'db');
    expect(read(dir, 'supabase_config.json'), 'cfg');
    expect(read(dir, 'sf1_column_map.json'), 'map');
    for (final name in ['basa_local.db', 'supabase_config.json', 'sf1_column_map.json']) {
      expect(read(docs.path, name), isNull, reason: '$name should have left Documents');
    }
  });

  test('retry after a failed move finishes it', () async {
    put(docs.path, 'basa_local.db', 'db');
    put(docs.path, 'supabase_config.json', 'cfg');

    Future<void> failOnDb(File from, String to) async {
      if (p.basename(from.path) == 'basa_local.db') throw const FileSystemException('locked');
      await from.rename(to);
    }

    await expectLater(
      prepareDataDir(documentsPath: docs.path, variant: 'admin', moveLegacy: true, mover: failOnDb),
      throwsA(isA<DataDirMoveException>()),
    );
    final target = p.join(docs.path, 'BASA', 'admin');
    expect(read(target, 'supabase_config.json'), 'cfg');
    expect(read(docs.path, 'basa_local.db'), 'db');

    final dir = await prepareDataDir(documentsPath: docs.path, variant: 'admin', moveLegacy: true);
    expect(read(dir, 'basa_local.db'), 'db');
    expect(read(docs.path, 'basa_local.db'), isNull);
  });

  test('both present: nothing moved, one warning', () async {
    final target = p.join(docs.path, 'BASA', 'admin');
    put(docs.path, 'basa_local.db', 'old');
    put(docs.path, 'supabase_config.json', 'old cfg');
    put(target, 'basa_local.db', 'new');
    final warnings = <String>[];

    await prepareDataDir(documentsPath: docs.path, variant: 'admin', moveLegacy: true, warn: warnings.add);

    expect(read(docs.path, 'basa_local.db'), 'old');
    expect(read(docs.path, 'supabase_config.json'), 'old cfg');
    expect(read(target, 'basa_local.db'), 'new');
    expect(warnings, hasLength(1));
    expect(warnings.single, contains('basa_local.db'));
  });

  test('moveLegacy false leaves documents alone', () async {
    put(docs.path, 'basa_local.db', 'db');

    final dir = await prepareDataDir(documentsPath: docs.path, variant: 'admin', moveLegacy: false);

    expect(read(docs.path, 'basa_local.db'), 'db');
    expect(read(dir, 'basa_local.db'), isNull);
  });

  test('tutor variant creates BASA/tutor only', () async {
    put(docs.path, 'basa_local.db', 'db');

    final dir = await prepareDataDir(documentsPath: docs.path, variant: 'tutor', moveLegacy: false);

    expect(p.equals(dir, p.join(docs.path, 'BASA', 'tutor')), isTrue);
    expect(Directory(dir).existsSync(), isTrue);
    expect(Directory(p.join(docs.path, 'BASA', 'admin')).existsSync(), isFalse);
    expect(read(docs.path, 'basa_local.db'), 'db');
  });
}
