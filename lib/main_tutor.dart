// lib/main_tutor.dart
/// Tutor app entry. Same shell as lib/main.dart without the admin wiring:
/// nothing reachable from here may import an admin-only file
/// (dart run tool/check_tutor_imports.dart).
library;

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'app_shell.dart';
import 'core/wiring/app_context.dart';
import 'core/wiring/data_dir.dart';
import 'core/wiring/wire_shared.dart';
import 'core/wiring/wire_tutor.dart';

const _title = 'BASA Tutor';

Future<void> main() async {
  // Same start-up as the admin app (see lib/main.dart): binding first, then
  // the bundled SQLite through FFI on every platform.
  WidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  // <documents>/BASA/tutor. Nothing to move: older builds were admin-shaped,
  // and their data belongs to the admin build.
  final String dataDir;
  try {
    dataDir = await prepareDataDir(
      documentsPath: (await getApplicationDocumentsDirectory()).path,
      variant: 'tutor',
      moveLegacy: false,
    );
  } on DataDirMoveException catch (e) {
    runApp(BasaStartupErrorApp(title: _title, message: e.message));
    return;
  }

  final ctx = await AppContext.open(dataDir: dataDir);
  final shared = wireShared(ctx);
  final tutor = wireTutor(ctx, shared);
  // Debug (and scan) builds only, written at the call site (see lib/main.dart).
  if (basaHasConsole) {
    registerSharedCommands(ctx, shared);
    registerTutorCommands(ctx, shared, tutor);
    registerDevCommands(ctx, shared);
  }

  runApp(BasaApp(title: _title, session: ctx.session, textVm: shared.textVm));
}
