// lib/console/main_tutor.dart
// Tutor console (plain `dart run`, no Flutter): only the commands the tutor
// app has. Data in ./data_tutor, so it never shares a database with the
// admin console (./data). Must not import anything admin-only
// (dart run tool/check_tutor_imports.dart).
import 'dart:convert';
import 'dart:io';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../core/console/console_session.dart';
import '../core/wiring/app_context.dart';
import '../core/wiring/wire_shared.dart';
import '../core/wiring/wire_tutor.dart';

Future<void> main() async {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  final dir = Directory('${Directory.current.path}/data_tutor');
  if (!dir.existsSync()) dir.createSync(recursive: true);
  final ctx = await AppContext.open(dataDir: dir.path);
  final shared = wireShared(ctx);
  final tutor = wireTutor(ctx, shared);
  registerSharedCommands(ctx, shared);
  registerTutorCommands(ctx, shared, tutor);
  registerDevCommands(ctx, shared);
  final session = ctx.session;

  stdout.writeln('BASA tutor console ready. Type "help", or "exit" to quit.');
  var printed = session.entries.length;
  while (true) {
    stdout.write('> ');
    final line = stdin.readLineSync(encoding: utf8); // not the Windows codepage
    if (line == null || line.trim() == 'exit') break; // null = end of piped input
    await session.run(line);
    for (final e in session.entries.skip(printed)) {
      if (e.type == ConsoleEntryType.input) continue;
      stdout.writeln(e.type == ConsoleEntryType.log ? '[${e.source}] ${e.message}' : e.message);
    }
    printed = session.entries.length;
  }
  exit(0); // the Supabase client can keep the process alive otherwise
}
