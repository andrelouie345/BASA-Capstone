// lib/viewmodels/theme_settings_viewmodel.dart
// The colour settings screen: light / dark / follow the device, and the
// colours a user changed for each mode. Stored per device in
// <data dir>/theme_settings.json (not per user, never synced). Works before
// sign-in. The UI decides which colour names exist and their defaults; this
// ViewModel only keeps the changes.
import '../core/console/logger.dart';
import '../core/data/local/theme_settings_store.dart';
import '../core/models/theme_settings.dart';
import 'viewmodel_exception.dart';

class ThemeSettingsViewModel {
  final ScopedLogger _log;
  final ThemeSettingsStore _store;

  ThemeSettingsViewModel({required ThemeSettingsStore store, Logger? logger})
      : _store = store,
        _log = ScopedLogger(logger, 'ThemeSettingsViewModel');

  /// The saved choices; [ThemeSettings.defaults] when nothing was changed.
  ThemeSettings current() => _store.current;

  Future<ThemeSettings> setMode(ThemeModeChoice mode) async {
    _log('setMode(${mode.name})');
    final next = _store.current.copyWith(mode: mode);
    await _store.save(next);
    return next;
  }

  /// Saves one colour of light or dark mode. [argb] is 0xAARRGGBB (Flutter's
  /// `Color.toARGB32()`).
  Future<ThemeSettings> setColor(ThemeBrightness brightness, String name, int argb) async {
    _log('setColor(${brightness.name}, $name, 0x${argb.toRadixString(16)})');
    if (!ThemeSettings.isValidColorName(name)) {
      throw ViewModelException(
          'Colour name "$name" is not valid: use letters, digits and underscores, starting with a letter.');
    }
    if (!ThemeSettings.isValidArgb(argb)) {
      throw const ViewModelException('Colour value is not valid: it must be between 0x00000000 and 0xFFFFFFFF.');
    }
    final next = _with(brightness, (colors) => colors[name] = argb);
    await _store.save(next);
    return next;
  }

  /// Puts one colour back to the app's default.
  Future<ThemeSettings> clearColor(ThemeBrightness brightness, String name) async {
    _log('clearColor(${brightness.name}, $name)');
    final next = _with(brightness, (colors) => colors.remove(name));
    await _store.save(next);
    return next;
  }

  /// Everything back to the defaults: follow the device, every colour at its default.
  Future<ThemeSettings> reset() async {
    _log('reset()');
    await _store.reset();
    return _store.current;
  }

  ThemeSettings _with(ThemeBrightness b, void Function(Map<String, int>) change) {
    final cur = _store.current;
    final colors = Map<String, int>.of(cur.colorsFor(b));
    change(colors);
    return b == ThemeBrightness.light ? cur.copyWith(light: colors) : cur.copyWith(dark: colors);
  }
}
