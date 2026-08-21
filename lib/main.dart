// lib/main.dart
import 'package:basa_capstone/core/console/commands/debug_commands.dart';
import 'package:basa_capstone/core/console/commands/test_data_commands.dart';
import 'package:basa_capstone/core/viewmodels/viewmodel_registry.dart';
import 'package:flutter/material.dart';
import 'core/console/console_registry.dart';
import 'core/console/console_session.dart';
import 'core/console/commands/text_commands.dart';
import 'viewmodels/text_viewmodel.dart';
import 'ui/debug/debug_overlay.dart';
import 'dart:io';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqflite_common/sqflite.dart';
import 'package:path_provider/path_provider.dart';
import 'core/data/local/local_database.dart';
import 'core/data/local/test_repository_sqlite.dart';
import 'viewmodels/test_data_viewmodel.dart';

Future <void> main() async{

  // Desktop needs FFI explicitly. Android/iOS get sqflite's native
  // factory automatically via the Flutter plugin system — do NOT set
  // databaseFactory yourself there, or you'll fight the plugin.
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }
    final docsDir = await getApplicationDocumentsDirectory();
    final localDb = await LocalDatabase.instance(docsDir.path);
    final registry = ConsoleRegistry();
    final session = ConsoleSession(registry);
    final vmRegistry = ViewModelRegistry();

final textVm = TextViewModel(logger: session);
vmRegistry.register('TextViewModel', textVm);


  registerTextCommands(registry, textVm);
  registerDebugCommands(registry, session, vmRegistry);
  final testDataVm = TestDataViewModel(repo: TestRepositorySqlite(localDb), logger: session);
  vmRegistry.register('TestDataViewModel', testDataVm);
  registerTestDataCommands(registry, testDataVm, localDb);

  runApp(BasaApp(session: session, textVm: textVm));
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