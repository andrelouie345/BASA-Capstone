// lib/main.dart
/// Admin app entry (admins and coordinators). Wiring lives in core/wiring;
/// the tutor app is lib/main_tutor.dart.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'app_shell.dart';
import 'core/wiring/app_context.dart';
import 'core/wiring/data_dir.dart';
import 'core/wiring/wire_admin.dart';
import 'core/wiring/wire_shared.dart';
import 'core/wiring/wire_tutor.dart';

const _title = 'BASA';

Future <void> main() async{
  // Must come first: on Android/iOS sqflite and path_provider talk to the
  // platform over channels, which need the binding. Desktop (FFI) never
  // noticed; without this the phone crashes before runApp (black screen).
  WidgetsFlutterBinding.ensureInitialized();

  // FFI on every platform, so every device runs the SQLite that
  // package:sqlite3 bundles (its build hook compiles it into the app), not
  // the phone's system SQLite. Android 10 ships 3.22: its fixed parser stack
  // overflows on the Phil-IRI no-repeat trigger (26 nested replace() calls)
  // and JSON1 depends on the vendor. Same engine as desktop and the console.
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  // <documents>/BASA/admin. Older desktop builds wrote straight into
  // Documents; those files move here once (on a phone the documents folder
  // was already private to the app, and the new app id starts fresh).
  final String dataDir;
  try {
    dataDir = await prepareDataDir(
      documentsPath: (await getApplicationDocumentsDirectory()).path,
      variant: 'admin',
      moveLegacy: Platform.isWindows || Platform.isLinux || Platform.isMacOS,
      warn: debugPrint,
    );
  } on DataDirMoveException catch (e) {
    runApp(BasaStartupErrorApp(title: _title, message: e.message));
    return;
  }

  final ctx = await AppContext.open(dataDir: dataDir);
  final shared = wireShared(ctx);
  final tutor = wireTutor(ctx, shared);
  final admin = await wireAdmin(ctx, shared, tutor);
  // Console commands exist in debug (and scan) builds only: basaHasConsole is
  // a constant written here, at the call site, so the compiler drops every
  // command file from shipped release builds.
  if (basaHasConsole) {
    registerSharedCommands(ctx, shared);
    registerTutorCommands(ctx, shared, tutor);
    registerAdminCommands(ctx, shared, tutor, admin);
    registerDevCommands(ctx, shared);
  }

  runApp(BasaApp(title: _title, session: ctx.session, textVm: shared.textVm));
}
