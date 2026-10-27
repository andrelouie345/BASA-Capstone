// lib/app_shell.dart
// The app shell both builds share (admin lib/main.dart, tutor lib/main_tutor.dart):
// the ViewModels for every screen (BasaScope), sign-in, the home screen and its
// navigation (lib/ui/home/), the debug console around it (debug builds only),
// and the screen shown when the data folder can't be prepared.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'core/console/console_session.dart';
import 'ui/auth/change_password_screen.dart';
import 'ui/auth/sign_in_screen.dart';
import 'ui/basa_scope.dart';
import 'ui/debug/debug_overlay.dart';
import 'ui/home/home_screen.dart';
import 'ui/home/home_sections.dart';
import 'ui/theme/basa_theme.dart';
import 'viewmodels/app_viewmodels.dart';

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

  /// The home screen's navigation: basaHomeSections() in the tutor build,
  /// adminHomeSections() (lib/ui/admin/) in the admin build, handed in by the
  /// entry point so this shell never imports an admin file.
  final List<HomeSection> homeSections;

  /// The tutor build: its debug console is dark green. A bool on purpose: the
  /// console's theme (and its title, a [debug] marker in
  /// tool/admin_markers.txt) is chosen only inside the basaHasConsole branch,
  /// so shipped builds don't keep it.
  final bool isTutorBuild;
  const BasaApp({
    super.key,
    required this.title,
    required this.session,
    required this.vms,
    required this.homeSections,
    this.isTutorBuild = false,
  });

  @override
  State<BasaApp> createState() => _BasaAppState();
}

class _BasaAppState extends State<BasaApp> {
  @override
  Widget build(BuildContext context) {
    // Not signed in: the sign-in screen. Signing in or out rebuilds here, and
    // so does a console command (sign-in from the console shows the home).
    // An admin-made account's first sign-in must set a password before anything else.
    final auth = widget.vms.auth;
    void refresh() => setState(() {});
    final Widget home = !auth.isSignedIn
        ? SignInScreen(appTitle: widget.title, onSignedIn: refresh)
        : auth.mustChangePassword
        ? ChangePasswordScreen(forced: true, onChanged: refresh, onSignedOut: refresh)
        : HomeScreen(title: widget.title, sections: widget.homeSections, onSignedOut: refresh);
    // Read on every build (a synchronous read of the saved file's copy), so a
    // change from the Colours screen or a theme-* console command both show.
    final theme = widget.vms.theme.current();
    // Above MaterialApp, so every route sees the ViewModels.
    return BasaScope(
      vms: widget.vms,
      child: BasaThemeScope(
        settings: theme,
        apply: (_) => setState(() {}),
        child: MaterialApp(
          title: widget.title,
          debugShowCheckedModeBanner: false,
          theme: basaThemeData(Brightness.light, theme.light),
          darkTheme: basaThemeData(Brightness.dark, theme.dark),
          themeMode: basaThemeMode(theme.mode),
          // No console in shipped release builds: basaHasConsole is a constant, so
          // the compiler drops the console from them.
          home: basaHasConsole
              ? DebugConsoleShell(
                  session: widget.session,
                  theme: widget.isTutorBuild ? ConsoleTheme.tutor : ConsoleTheme.admin,
                  onCommandRun: () => setState(() {}), // rebuilds everything below
                  child: home,
                )
              : home,
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
    // No saved settings can be read here: the default colours, following the device.
    return MaterialApp(
      title: title,
      debugShowCheckedModeBanner: false,
      theme: basaThemeData(Brightness.light),
      darkTheme: basaThemeData(Brightness.dark),
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
