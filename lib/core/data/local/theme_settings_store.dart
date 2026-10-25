// lib/core/data/local/theme_settings_store.dart
// The colour choices of this device, persisted in <data dir>/theme_settings.json
// (the same way as supabase_config.json). No file = the app's defaults.
import 'dart:convert';
import 'dart:io';

import '../../models/theme_settings.dart';

class ThemeSettingsStore {
  final String _path;
  ThemeSettings _current;

  ThemeSettingsStore._(this._path, this._current);

  ThemeSettings get current => _current;

  /// A missing or unreadable file gives the defaults (nothing is written
  /// until the user changes something, so a broken file stays for a look).
  static Future<ThemeSettingsStore> load(String directory) async {
    final path = '$directory/theme_settings.json';
    final file = File(path);
    var settings = ThemeSettings.defaults;
    if (await file.exists()) {
      try {
        final data = jsonDecode(await file.readAsString());
        if (data is Map<String, Object?>) settings = ThemeSettings.fromMap(data);
      } on FormatException {
        // keep the defaults
      }
    }
    return ThemeSettingsStore._(path, settings);
  }

  Future<void> save(ThemeSettings settings) async {
    await File(_path).writeAsString(jsonEncode(settings.toMap()));
    _current = settings;
  }

  /// Back to the defaults: deletes the file.
  Future<void> reset() async {
    final file = File(_path);
    if (await file.exists()) await file.delete();
    _current = ThemeSettings.defaults;
  }
}
