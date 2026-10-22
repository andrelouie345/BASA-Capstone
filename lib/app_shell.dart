// lib/app_shell.dart
// The app shell both builds share (admin lib/main.dart, tutor lib/main_tutor.dart):
// the placeholder home screen, the debug console around it (debug builds only),
// and the screen shown when the data folder can't be prepared.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'core/console/console_session.dart';
import 'ui/debug/debug_overlay.dart';
import 'viewmodels/text_viewmodel.dart';

class BasaApp extends StatefulWidget {
  final String title;
  final ConsoleSession session;
  final TextViewModel textVm;
  const BasaApp({super.key, required this.title, required this.session, required this.textVm});

  @override
  State<BasaApp> createState() => _BasaAppState();
}

class _BasaAppState extends State<BasaApp> {
  @override
  Widget build(BuildContext context) {
    final home = BasaHomeScreen(title: widget.title, textVm: widget.textVm);
    return MaterialApp(
      title: widget.title,
      debugShowCheckedModeBanner: false,
      // No console in release builds: kDebugMode is a constant, so the
      // compiler drops the console from them.
      home: kDebugMode
          ? DebugConsoleShell(
              session: widget.session,
              onCommandRun: () => setState(() {}), // rebuilds everything below
              child: home,
            )
          : home,
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
