// Checks the typed CRLA content against the printed forms and the stored
// stories (spec D2):
//   dart run tool/crla_content/check.dart supabase/seeds/crla_content/region10.json <stories.csv>
// stories.csv = the result of
//   select language, grade, story_no, title, word_count from crla_stories where region_id = 13
// (header row, comma-separated; a title with a comma is quoted).
import 'dart:convert';
import 'dart:io';

import 'content.dart';

Future<void> main(List<String> args) async {
  if (args.length != 2) {
    stderr.writeln('Usage: dart run tool/crla_content/check.dart <content.json> <stories.csv>');
    exit(64);
  }
  final content = CrlaContent.fromJson(jsonDecode(File(args[0]).readAsStringSync()) as Map<String, Object?>);
  final stored = readStoredStories(File(args[1]).readAsLinesSync());
  final problems = checkCrlaContent(content, stored);
  for (final f in content.forms) {
    final mine = problems.where((p) => p.startsWith('${f.name}:')).toList();
    stdout.writeln('${mine.isEmpty ? 'OK ' : 'BAD'} ${f.name}${mine.isEmpty ? '' : ' (${mine.length})'}');
    for (final p in mine) {
      stdout.writeln('    $p');
    }
  }
  final forms = {for (final f in content.forms) (f.language, f.grade)};
  final missing = {for (final k in stored.keys) (k.$1, k.$2)}.difference(forms);
  for (final (language, grade) in missing) {
    stdout.writeln('MISSING $language Grade $grade (stored, not in the file)');
  }
  for (final n in crlaContentNotes(content)) {
    stdout.writeln('NOTE $n');
  }
  stdout.writeln('${content.forms.length} form(s), ${problems.length} problem(s), ${missing.length} missing');
  exit(problems.isEmpty && missing.isEmpty ? 0 : 1);
}

/// Parses the stories CSV (header row first).
CrlaStoredStories readStoredStories(List<String> lines) {
  final out = <(String, int, int), ({String title, int wordCount})>{};
  for (final line in lines.skip(1).where((l) => l.trim().isNotEmpty)) {
    final cells = _cells(line);
    out[(cells[0], int.parse(cells[1]), int.parse(cells[2]))] = (title: cells[3], wordCount: int.parse(cells[4]));
  }
  return out;
}

List<String> _cells(String line) {
  final out = <String>[];
  final b = StringBuffer();
  var quoted = false;
  for (var i = 0; i < line.length; i++) {
    final ch = line[i];
    if (ch == '"') {
      if (quoted && i + 1 < line.length && line[i + 1] == '"') {
        b.write('"');
        i++;
      } else {
        quoted = !quoted;
      }
    } else if (ch == ',' && !quoted) {
      out.add(b.toString());
      b.clear();
    } else {
      b.write(ch);
    }
  }
  out.add(b.toString());
  return out;
}
