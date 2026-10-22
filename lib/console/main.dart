// lib/console/main.dart
// Admin console (plain `dart run`, no Flutter). Wiring lives in core/wiring;
// the tutor console is lib/console/main_tutor.dart.
import 'dart:convert';
import 'dart:io';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../core/console/console_session.dart';
import '../core/wiring/app_context.dart';
import '../core/wiring/wire_admin.dart';
import '../core/wiring/wire_shared.dart';
import '../core/wiring/wire_tutor.dart';

Future<void> main() async {
  // Pure `dart run` has no Flutter engine, so we MUST use the FFI
  // factory here — the native `sqflite` plugin would throw
  // MissingPluginException since there's no platform channel at all.
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  // No path_provider here (it needs Flutter). Use a local ./data folder.
  final dir = Directory('${Directory.current.path}/data');
  if (!dir.existsSync()) dir.createSync(recursive: true);
  final ctx = await AppContext.open(dataDir: dir.path);
  final shared = wireShared(ctx);
  final tutor = wireTutor(ctx, shared);
  final admin = await wireAdmin(ctx, shared, tutor);
  registerSharedCommands(ctx, shared);
  registerTutorCommands(ctx, shared, tutor);
  registerAdminCommands(ctx, shared, tutor, admin);
  registerDevCommands(ctx, shared);
  final session = ctx.session;

  // Headless REPL: lets the console run from a terminal or a piped script.
  stdout.writeln('BASA console ready. Type "help", or "exit" to quit.');
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