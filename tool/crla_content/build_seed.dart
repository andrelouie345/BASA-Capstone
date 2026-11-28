// Builds the CRLA content seed from the typed JSON:
//   dart run tool/crla_content/build_seed.dart supabase/seeds/crla_content/region10.json supabase/seeds/crla_content_region10.sql
// Run tool/crla_content/check.dart first: the seed is built only from checked content.
import 'dart:convert';
import 'dart:io';

import 'content.dart';

void main(List<String> args) {
  if (args.length != 2) {
    stderr.writeln('Usage: dart run tool/crla_content/build_seed.dart <content.json> <seed.sql>');
    exit(64);
  }
  final content = CrlaContent.fromJson(jsonDecode(File(args[0]).readAsStringSync()) as Map<String, Object?>);
  File(args[1]).writeAsStringSync(crlaContentSeed(content));
  stdout.writeln('Wrote ${args[1]}: ${content.forms.length} form(s).');
}
