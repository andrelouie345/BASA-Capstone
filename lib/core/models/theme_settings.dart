// lib/core/models/theme_settings.dart
// The app's colour choices on this device (not per user, never synced):
// the mode, and the colours the user changed for light and dark mode.
// The UI owns the colour names and their defaults; a name missing here
// means "use the app's default". Colours are ARGB ints (0xAARRGGBB), the
// value Flutter's Color(int) takes, so this file needs no Flutter import.

/// Which mode the app shows. [system] follows the phone's or computer's setting.
enum ThemeModeChoice { system, light, dark }

/// Light or dark: which set of colours a change applies to.
enum ThemeBrightness { light, dark }

class ThemeSettings {
  final ThemeModeChoice mode;

  /// Colour name → ARGB, light mode. Only the colours the user changed.
  final Map<String, int> light;

  /// Colour name → ARGB, dark mode. Only the colours the user changed.
  final Map<String, int> dark;

  const ThemeSettings({
    this.mode = ThemeModeChoice.system,
    this.light = const {},
    this.dark = const {},
  });

  /// Nothing changed: follow the device, every colour at the app's default.
  static const defaults = ThemeSettings();

  Map<String, int> colorsFor(ThemeBrightness b) => b == ThemeBrightness.light ? light : dark;

  ThemeSettings copyWith({ThemeModeChoice? mode, Map<String, int>? light, Map<String, int>? dark}) =>
      ThemeSettings(
        mode: mode ?? this.mode,
        light: Map.unmodifiable(light ?? this.light),
        dark: Map.unmodifiable(dark ?? this.dark),
      );

  Map<String, Object?> toMap() => {'mode': mode.name, 'light': light, 'dark': dark};

  /// Lenient on purpose: an unknown mode becomes [ThemeModeChoice.system] and
  /// an entry that isn't a name → int pair is dropped, so a hand-edited or
  /// older file never stops the app from starting.
  factory ThemeSettings.fromMap(Map<String, Object?> m) {
    Map<String, int> colors(Object? raw) => {
          if (raw is Map)
            for (final e in raw.entries)
              if (e.key is String && e.value is int && isValidColorName(e.key as String) && isValidArgb(e.value as int))
                e.key as String: e.value as int,
        };
    return ThemeSettings(
      mode: ThemeModeChoice.values.firstWhere((v) => v.name == m['mode'], orElse: () => ThemeModeChoice.system),
      light: Map.unmodifiable(colors(m['light'])),
      dark: Map.unmodifiable(colors(m['dark'])),
    );
  }

  /// Letters, digits and underscores, starting with a letter (e.g. primary, onSurface).
  static bool isValidColorName(String name) => RegExp(r'^[A-Za-z][A-Za-z0-9_]{0,63}$').hasMatch(name);

  static bool isValidArgb(int argb) => argb >= 0 && argb <= 0xFFFFFFFF;
}
