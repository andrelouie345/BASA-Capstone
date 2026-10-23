// lib/core/console/file_output.dart
// Files written by console commands (exports, reports). Screens save through
// their own save dialog; the console writes the path it was given.
import 'dart:io';

import 'package:path/path.dart' as p;

/// Where [path] lands: absolute and normalized (a relative path is resolved
/// against the folder the console was started from). Messages show this, so
/// the user always sees where the file went.
String outputPath(String path) => p.normalize(File(path).absolute.path);

/// Writes [text] or [bytes] to [path]. Returns null when written, otherwise
/// `Couldn't write <path>: <reason>` (missing folder, file open in another
/// program, no permission), never an exception.
Future<String?> writeOutputFile(String path, {String? text, List<int>? bytes}) async {
  try {
    final file = File(path);
    if (bytes != null) {
      await file.writeAsBytes(bytes);
    } else {
      await file.writeAsString(text ?? '');
    }
    return null;
  } on FileSystemException catch (e) {
    final reason = e.osError?.message.trim();
    return "Couldn't write ${outputPath(path)}: ${reason == null || reason.isEmpty ? e.message : reason}";
  }
}
