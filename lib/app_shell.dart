// lib/app_shell.dart
// The app shell both builds share (admin lib/main.dart, tutor lib/main_tutor.dart):
// the ViewModels for every screen (BasaScope), the placeholder home screen, the
// debug console around it (debug builds only), and the screen shown when the
// data folder can't be prepared.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'core/console/console_session.dart';
import 'ui/basa_scope.dart';
import 'ui/debug/debug_overlay.dart';
import 'viewmodels/app_viewmodels.dart';
import 'viewmodels/text_viewmodel.dart';

/// Set only by tool/build_release.ps1 for its scan builds (never shipped). A
/// scan build has the console (commands + overlay) compiled in, so every
/// ViewModel method the build can call is in the binary and the admin-marker
/// scan means something. Shipped release builds have no console.
const basaScanBuild = bool.fromEnvironment('BASA_SCAN_BUILD');

/// Whether this build has the debug console.
const basaHasConsole = kDebugMode || basaScanBuild;

class BasaApp extends StatefulWidget {
  final String title;
  final ConsoleSession session;

  /// What every screen reaches through `BasaScope.of(context)`.
  final AppViewModels vms;

  /// Placeholder home and the console's text commands only (dev).
  final TextViewModel textVm;
  const BasaApp({super.key, required this.title, required this.session, required this.vms, required this.textVm});

  @override
  State<BasaApp> createState() => _BasaAppState();
}

class _BasaAppState extends State<BasaApp> {
  @override
  Widget build(BuildContext context) {
    final home = BasaHomeScreen(title: widget.title, textVm: widget.textVm);
    // Above MaterialApp, so every route sees the ViewModels.
    return BasaScope(
      vms: widget.vms,
      child: MaterialApp(
        title: widget.title,
        debugShowCheckedModeBanner: false,
        // No console in shipped release builds: basaHasConsole is a constant, so
        // the compiler drops the console from them.
        home: basaHasConsole
            ? DebugConsoleShell(
                session: widget.session,
                onCommandRun: () => setState(() {}), // rebuilds everything below
                child: home,
              )
            : home,
      ),
    );
  }
}

class BasaHomeScreen extends StatefulWidget {
  final String title;
  final TextViewModel textVm;
  const BasaHomeScreen({super.key, required this.title, required this.textVm});

  @override
  State<BasaHomeScreen> createState() => _BasaHomeScreenState();
}

class _BasaHomeScreenState extends State<BasaHomeScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Center(
        child: Text(
          widget.textVm.value.isEmpty ? '(empty)' : widget.textVm.value,
          style: const TextStyle(fontSize: 24),
        ),
      ),
    );
  }
}

/// Shown instead of the app when the data folder can't be prepared
/// (for example the one-time move out of Documents failed).
class BasaStartupErrorApp extends StatelessWidget {
  final String title;
  final String message;
  const BasaStartupErrorApp({super.key, required this.title, required this.message});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: title,
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        appBar: AppBar(title: Text(title)),
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: SelectableText(message, style: const TextStyle(fontSize: 16)),
        ),
      ),
    );
  }
}
