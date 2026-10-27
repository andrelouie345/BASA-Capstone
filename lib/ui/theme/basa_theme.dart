// lib/ui/theme/basa_theme.dart
// Builds the app's ThemeData for light and dark mode from the colours in
// basa_colors.dart plus the user's saved changes, and hands the saved
// settings to the Colours screen (BasaThemeScope).
import 'package:flutter/material.dart';

import '../../core/models/theme_settings.dart';
import 'basa_colors.dart';

/// The whole theme for [b] with the user's [changes] (name → ARGB).
ThemeData basaThemeData(Brightness b, [Map<String, int> changes = const {}]) {
  final scheme = basaColorScheme(b, changes);
  final rounded = RoundedRectangleBorder(borderRadius: BorderRadius.circular(12));
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    visualDensity: VisualDensity.standard,
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      foregroundColor: scheme.onSurface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 1,
      centerTitle: false,
    ),
    cardTheme: CardThemeData(
      color: scheme.surfaceContainer,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: scheme.outlineVariant),
      ),
    ),
    inputDecorationTheme: InputDecorationThemeData(
      filled: true,
      fillColor: scheme.surfaceContainerLow,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(64, 48),
        shape: rounded,
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(minimumSize: const Size(64, 44), shape: rounded),
    ),
    dividerTheme: DividerThemeData(color: scheme.outlineVariant, space: 1),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
}

ThemeMode basaThemeMode(ThemeModeChoice choice) => switch (choice) {
  ThemeModeChoice.system => ThemeMode.system,
  ThemeModeChoice.light => ThemeMode.light,
  ThemeModeChoice.dark => ThemeMode.dark,
};

/// The saved colour settings and how to apply new ones. The app shell puts it
/// above MaterialApp; the Colours screen calls [apply] with what
/// ThemeSettingsViewModel returned, and the whole app rebuilds with it.
class BasaThemeScope extends InheritedWidget {
  final ThemeSettings settings;
  final ValueChanged<ThemeSettings> apply;

  const BasaThemeScope({super.key, required this.settings, required this.apply, required super.child});

  static BasaThemeScope of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<BasaThemeScope>();
    if (scope == null) throw StateError('No BasaThemeScope above this widget (BasaApp puts it at the root).');
    return scope;
  }

  @override
  bool updateShouldNotify(BasaThemeScope oldWidget) => !identical(settings, oldWidget.settings);
}
