// lib/core/wiring/data_dir.dart
// Where the app keeps its local files: <documents>/BASA/<variant>, so the
// admin and tutor builds never share a database on one computer. Before the
// split, the desktop app wrote straight into Documents; the admin build moves
// those files once. Pure Dart (no Flutter): the caller passes the documents path.
import 'dart:io';

import 'package:path/path.dart' as p;

/// The files the app keeps in its data folder. The database goes last, so a
/// move that fails half-way is finished on the next start (the database still
/// in Documents is what triggers the move).
const _legacyFiles = [
  'basa_local.db-journal',
  'basa_local.db-wal',
  'basa_local.db-shm',
  'supabase_config.json',
  'sf1_column_map.json',
  'basa_local.db',
];

class DataDirMoveException implements Exception {
  final String message;
  const DataDirMoveException(this.message);

  @override
  String toString() => message;
}

/// Returns `<documentsPath>/BASA/<variant>`, creating it. With [moveLegacy],
/// files left in [documentsPath] by an older desktop build are moved there
/// first, unless that folder already has a database (then nothing moves and
/// [warn] is told once). Throws [DataDirMoveException] when a move fails.
Future<String> prepareDataDir({
  required String documentsPath,
  required String variant,
  required bool moveLegacy,
  void Function(String message)? warn,
  Future<void> Function(File from, String toPath)? mover,
}) async {
  final target = p.join(documentsPath, 'BASA', variant);
  await Directory(target).create(recursive: true);
  if (!moveLegacy) return target;

  final legacyDb = File(p.join(documentsPath, 'basa_local.db'));
  if (!await legacyDb.exists()) return target;
  if (await File(p.join(target, 'basa_local.db')).exists()) {
    warn?.call('Both ${legacyDb.path} and ${p.join(target, 'basa_local.db')} exist; '
        'nothing was moved. BASA uses the one in $target.');
    return target;
  }

  final move = mover ?? (File from, String to) => from.rename(to);
  for (final name in _legacyFiles) {
    final from = File(p.join(documentsPath, name));
    final to = p.join(target, name);
    if (!await from.exists() || await File(to).exists()) continue;
    try {
      await move(from, to);
    } catch (e) {
      throw DataDirMoveException('Could not move $name from $documentsPath to $target: $e. '
          'Close any other BASA window and start BASA again; the move picks up where it stopped.');
    }
  }
  return target;
}
