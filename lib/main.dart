// lib/main.dart
/// Admin app entry (admins and coordinators). Wiring lives in core/wiring;
/// the tutor app is lib/main_tutor.dart.
library;

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'core/console/console_session.dart';
import 'core/wiring/app_context.dart';
import 'core/wiring/wire_admin.dart';
import 'core/wiring/wire_shared.dart';
import 'core/wiring/wire_tutor.dart';
import 'ui/debug/debug_overlay.dart';
import 'viewmodels/text_viewmodel.dart';

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
  final docsDir = await getApplicationDocumentsDirectory();
  final ctx = await AppContext.open(dataDir: docsDir.path);
  final shared = wireShared(ctx);
  final tutor = wireTutor(ctx, shared);
  final admin = await wireAdmin(ctx, shared, tutor);
  registerSharedCommands(ctx, shared);
  registerTutorCommands(ctx, shared, tutor);
  registerAdminCommands(ctx, shared, tutor, admin);
  registerDevCommands(ctx, shared);

  runApp(BasaApp(session: ctx.session, textVm: shared.textVm));
}

class BasaApp extends StatefulWidget {
  final ConsoleSession session;
  final TextViewModel textVm;
  const BasaApp({super.key, required this.session, required this.textVm});

  @override
  State<BasaApp> createState() => _BasaAppState();
}

class _BasaAppState extends State<BasaApp> {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BASA',
      debugShowCheckedModeBanner: false,
      home: DebugConsoleShell(
        session: widget.session,
        onCommandRun: () => setState(() {}),   // rebuilds everything below
        child: BasaHomeScreen(textVm: widget.textVm),
      ),
    );
  }
}

class BasaHomeScreen extends StatefulWidget {
  final TextViewModel textVm;
  const BasaHomeScreen({super.key, required this.textVm});

  @override
  State<BasaHomeScreen> createState() => _BasaHomeScreenState();
}

class _BasaHomeScreenState extends State<BasaHomeScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('BASA')),
      body: Center(
        child: Text(
          widget.textVm.value.isEmpty ? '(empty)' : widget.textVm.value,
          style: const TextStyle(fontSize: 24),
        ),
      ),
    );
  }
}