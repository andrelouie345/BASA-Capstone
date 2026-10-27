// lib/ui/theme/basa_colors.dart
// The app's colour names and their default values, for light and dark mode.
// The user's changes (ThemeSettingsViewModel, saved per device) are laid over
// these defaults: a name the user never changed always takes the value here,
// so the defaults can change without touching anyone's saved file.
//
// Each name is a ColorScheme role, so screens read them the usual way:
// Theme.of(context).colorScheme.primary. Roles not listed here are derived
// from `primary` by Flutter (ColorScheme.fromSeed).
//
// Look: paper and ink. Warm off-white pages, deep school-blue ink, a pencil
// ochre for highlights and a chalkboard green for "ready / done".
import 'package:flutter/material.dart';

/// One colour the user can change.
class BasaColor {
  /// Saved name (letters, digits, underscores; ThemeSettings checks it).
  final String name;

  /// What the Colours screen calls it.
  final String label;

  /// What it is used for, in a few words.
  final String usage;

  /// Defaults, ARGB (0xAARRGGBB).
  final int light;
  final int dark;

  const BasaColor(this.name, this.label, this.usage, {required this.light, required this.dark});

  int defaultFor(Brightness b) => b == Brightness.light ? light : dark;
}

/// Every colour the user can change, in the order the Colours screen shows them.
const List<BasaColor> basaColors = [
  BasaColor('primary', 'Primary', 'main buttons, selected items, links', light: 0xFF1F4E8C, dark: 0xFFA9C7F5),
  BasaColor('onPrimary', 'Text on primary', 'text and icons on primary', light: 0xFFFFFFFF, dark: 0xFF0B2547),
  BasaColor(
    'primaryContainer',
    'Primary container',
    'highlighted cards, selected chips',
    light: 0xFFD6E3FA,
    dark: 0xFF1A3D6E,
  ),
  BasaColor(
    'onPrimaryContainer',
    'Text on primary container',
    'text on highlighted cards',
    light: 0xFF0B2547,
    dark: 0xFFD6E3FA,
  ),
  BasaColor('secondary', 'Accent', 'secondary actions, badges', light: 0xFFA75F0B, dark: 0xFFF2B866),
  BasaColor('onSecondary', 'Text on accent', 'text and icons on the accent', light: 0xFFFFFFFF, dark: 0xFF3D2200),
  BasaColor('secondaryContainer', 'Accent container', 'notices, pending items', light: 0xFFFFE3BF, dark: 0xFF5C3A08),
  BasaColor('onSecondaryContainer', 'Text on accent container', 'text on notices', light: 0xFF3D2200, dark: 0xFFFFE3BF),
  BasaColor('tertiary', 'Success', 'online, done, ready', light: 0xFF2E7D5B, dark: 0xFF86D3AE),
  BasaColor('onTertiary', 'Text on success', 'text and icons on success', light: 0xFFFFFFFF, dark: 0xFF00391F),
  BasaColor('error', 'Error', 'errors and refusals', light: 0xFFB3261E, dark: 0xFFF2B8B5),
  BasaColor('onError', 'Text on error', 'text and icons on error', light: 0xFFFFFFFF, dark: 0xFF601410),
  BasaColor('surface', 'Background', 'the page behind everything', light: 0xFFFBF8F2, dark: 0xFF16181C),
  BasaColor('onSurface', 'Text', 'normal text and icons', light: 0xFF1C1B1A, dark: 0xFFE6E2DC),
  BasaColor('onSurfaceVariant', 'Muted text', 'labels, hints, secondary text', light: 0xFF4E4A44, dark: 0xFFC2BCB2),
  BasaColor('surfaceContainer', 'Card', 'cards, fields, menus', light: 0xFFF1ECE3, dark: 0xFF22252B),
  BasaColor('outline', 'Border', 'borders and dividers', light: 0xFF8A847A, dark: 0xFF8E8A83),
];

/// Default value of [name] in [b]; null when the app has no such colour.
int? basaDefaultColor(Brightness b, String name) {
  for (final c in basaColors) {
    if (c.name == name) return c.defaultFor(b);
  }
  return null;
}

/// The colour scheme for [b]: the defaults above with the user's [changes]
/// (name → ARGB) laid over them. Unknown names in [changes] are ignored.
ColorScheme basaColorScheme(Brightness b, Map<String, int> changes) {
  Color c(String name) => Color(changes[name] ?? basaDefaultColor(b, name)!);
  final surface = c('surface');
  final container = c('surfaceContainer');
  final onSurface = c('onSurface');
  return ColorScheme.fromSeed(seedColor: c('primary'), brightness: b).copyWith(
    primary: c('primary'),
    onPrimary: c('onPrimary'),
    primaryContainer: c('primaryContainer'),
    onPrimaryContainer: c('onPrimaryContainer'),
    secondary: c('secondary'),
    onSecondary: c('onSecondary'),
    secondaryContainer: c('secondaryContainer'),
    onSecondaryContainer: c('onSecondaryContainer'),
    tertiary: c('tertiary'),
    onTertiary: c('onTertiary'),
    error: c('error'),
    onError: c('onError'),
    surface: surface,
    onSurface: onSurface,
    onSurfaceVariant: c('onSurfaceVariant'),
    outline: c('outline'),
    outlineVariant: Color.lerp(c('outline'), surface, 0.55),
    // The container steps follow the two colours the user can set.
    surfaceContainerLowest: Color.lerp(surface, container, 0.0),
    surfaceContainerLow: Color.lerp(surface, container, 0.5),
    surfaceContainer: container,
    surfaceContainerHigh: Color.lerp(container, onSurface, 0.04),
    surfaceContainerHighest: Color.lerp(container, onSurface, 0.08),
  );
}
