// lib/ui/theme/basa_theme.dart
// Builds the app's ThemeData for light and dark mode from the colours in
// basa_colors.dart plus the user's saved changes, and hands the saved
// settings to the Colours screen (BasaThemeScope).
import 'package:flutter/material.dart';

import '../../core/models/theme_settings.dart';
import 'basa_colors.dart';

/// Corner radii, shared by the theme and the screens that draw their own boxes.
abstract final class BasaRadius {
  static const double small = 10;
  static const double medium = 14;
  static const double large = 20;
}

/// The whole theme for [b] with the user's [changes] (name → ARGB).
ThemeData basaThemeData(Brightness b, [Map<String, int> changes = const {}]) {
  final scheme = basaColorScheme(b, changes);
  final rounded = RoundedRectangleBorder(borderRadius: BorderRadius.circular(BasaRadius.medium));
  final base = ThemeData(useMaterial3: true, colorScheme: scheme);
  final text = _textTheme(base.textTheme);
  OutlineInputBorder field(Color c, [double w = 1]) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(BasaRadius.medium),
    borderSide: BorderSide(color: c, width: w),
  );
  return base.copyWith(
    textTheme: text,
    scaffoldBackgroundColor: scheme.surface,
    visualDensity: VisualDensity.standard,
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
      },
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      foregroundColor: scheme.onSurface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0.5,
      shadowColor: scheme.shadow.withValues(alpha: 0.25),
      centerTitle: false,
      titleTextStyle: text.titleLarge?.copyWith(color: scheme.onSurface),
    ),
    cardTheme: CardThemeData(
      color: scheme.surfaceContainerLowest,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(BasaRadius.large),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.7)),
      ),
    ),
    inputDecorationTheme: InputDecorationThemeData(
      filled: true,
      fillColor: scheme.surfaceContainerLow,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: field(scheme.outlineVariant),
      enabledBorder: field(scheme.outlineVariant),
      focusedBorder: field(scheme.primary, 2),
      errorBorder: field(scheme.error),
      focusedErrorBorder: field(scheme.error, 2),
      prefixIconColor: scheme.onSurfaceVariant,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(64, 48),
        padding: const EdgeInsets.symmetric(horizontal: 22),
        shape: rounded,
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15, letterSpacing: 0.1),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(minimumSize: const Size(64, 44), shape: rounded, elevation: 0),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(64, 44),
        padding: const EdgeInsets.symmetric(horizontal: 18),
        shape: rounded,
        side: BorderSide(color: scheme.outlineVariant),
        textStyle: const TextStyle(fontWeight: FontWeight.w600),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(shape: rounded, textStyle: const TextStyle(fontWeight: FontWeight.w600)),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: scheme.primary,
      foregroundColor: scheme.onPrimary,
      elevation: 2,
      highlightElevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(BasaRadius.large)),
      extendedTextStyle: const TextStyle(fontWeight: FontWeight.w600),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        shape: rounded,
        side: BorderSide(color: scheme.outlineVariant),
        selectedBackgroundColor: scheme.primaryContainer,
        selectedForegroundColor: scheme.onPrimaryContainer,
      ),
    ),
    chipTheme: ChipThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(BasaRadius.small)),
      side: BorderSide(color: scheme.outlineVariant),
      backgroundColor: scheme.surfaceContainerLow,
      selectedColor: scheme.primaryContainer,
    ),
    listTileTheme: ListTileThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(BasaRadius.medium)),
      iconColor: scheme.onSurfaceVariant,
    ),
    expansionTileTheme: ExpansionTileThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(BasaRadius.medium)),
      collapsedShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(BasaRadius.medium)),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: scheme.surfaceContainerLowest,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(BasaRadius.large + 4)),
      titleTextStyle: text.headlineSmall?.copyWith(fontSize: 22, color: scheme.onSurface),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: scheme.surfaceContainerLowest,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(BasaRadius.large + 8)),
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: scheme.surfaceContainerLowest,
      surfaceTintColor: Colors.transparent,
      elevation: 6,
      shadowColor: scheme.shadow.withValues(alpha: 0.2),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(BasaRadius.medium),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.6)),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: scheme.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      indicatorColor: scheme.primaryContainer,
      elevation: 0,
      height: 68,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (s) => text.labelMedium?.copyWith(
          fontWeight: s.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
        ),
      ),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: scheme.surfaceContainerLow,
      indicatorColor: scheme.primaryContainer,
      selectedIconTheme: IconThemeData(color: scheme.onPrimaryContainer),
      unselectedIconTheme: IconThemeData(color: scheme.onSurfaceVariant),
      selectedLabelTextStyle: text.labelLarge?.copyWith(color: scheme.onSurface, fontWeight: FontWeight.w700),
      unselectedLabelTextStyle: text.labelLarge?.copyWith(color: scheme.onSurfaceVariant),
    ),
    navigationDrawerTheme: NavigationDrawerThemeData(
      backgroundColor: scheme.surfaceContainerLowest,
      surfaceTintColor: Colors.transparent,
      indicatorColor: scheme.primaryContainer,
    ),
    tabBarTheme: TabBarThemeData(
      labelColor: scheme.primary,
      unselectedLabelColor: scheme.onSurfaceVariant,
      indicatorColor: scheme.primary,
      dividerColor: scheme.outlineVariant,
      labelStyle: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
      unselectedLabelStyle: text.titleSmall,
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: scheme.primary,
      linearTrackColor: scheme.surfaceContainerHighest,
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(color: scheme.inverseSurface, borderRadius: BorderRadius.circular(8)),
      textStyle: text.bodySmall?.copyWith(color: scheme.onInverseSurface),
      waitDuration: const Duration(milliseconds: 400),
    ),
    dataTableTheme: DataTableThemeData(
      headingTextStyle: text.labelLarge?.copyWith(fontWeight: FontWeight.w700, color: scheme.onSurfaceVariant),
      headingRowColor: WidgetStatePropertyAll(scheme.surfaceContainerLow),
      dividerThickness: 0.6,
    ),
    dividerTheme: DividerThemeData(color: scheme.outlineVariant.withValues(alpha: 0.7), space: 1, thickness: 1),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(BasaRadius.medium)),
    ),
  );
}

/// Tighter, bolder headings; body text a touch taller for reading.
TextTheme _textTheme(TextTheme t) => t.copyWith(
  headlineLarge: t.headlineLarge?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.8),
  headlineMedium: t.headlineMedium?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.6),
  headlineSmall: t.headlineSmall?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.4),
  titleLarge: t.titleLarge?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.2),
  titleMedium: t.titleMedium?.copyWith(fontWeight: FontWeight.w700),
  titleSmall: t.titleSmall?.copyWith(fontWeight: FontWeight.w600),
  bodyLarge: t.bodyLarge?.copyWith(height: 1.45),
  bodyMedium: t.bodyMedium?.copyWith(height: 1.4),
  labelLarge: t.labelLarge?.copyWith(fontWeight: FontWeight.w600),
);

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
