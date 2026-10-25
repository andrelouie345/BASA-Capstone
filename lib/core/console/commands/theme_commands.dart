// lib/core/console/commands/theme_commands.dart
import '../console_command.dart';
import '../console_registry.dart';
import '../../models/theme_settings.dart';
import '../../../viewmodels/theme_settings_viewmodel.dart';
import '../../../viewmodels/viewmodel_exception.dart';

void registerThemeCommands(ConsoleRegistry registry, ThemeSettingsViewModel vm) {
  registry.register(ConsoleCommand(
    name: 'theme-show',
    description: 'theme-show — the colour mode and the colours changed on this device',
    handler: (_) async => _show(vm.current()),
  ));

  registry.register(ConsoleCommand(
    name: 'theme-mode',
    description: 'theme-mode <system|light|dark> — light, dark, or follow the device',
    handler: (args) async {
      final mode = args.length == 1 ? _byName(ThemeModeChoice.values, args.first) : null;
      if (mode == null) return 'Usage: theme-mode <system|light|dark>';
      await vm.setMode(mode);
      return 'Mode set to ${mode.name}.';
    },
  ));

  registry.register(ConsoleCommand(
    name: 'theme-set',
    description: 'theme-set <light|dark> <name> <#RRGGBB|#AARRGGBB> — change one colour',
    handler: (args) async {
      const usage = 'Usage: theme-set <light|dark> <name> <#RRGGBB|#AARRGGBB>';
      if (args.length != 3) return usage;
      final b = _byName(ThemeBrightness.values, args[0]);
      final argb = _parseHex(args[2]);
      if (b == null) return usage;
      if (argb == null) return 'Colour must be #RRGGBB or #AARRGGBB, e.g. #1E88E5.';
      try {
        await vm.setColor(b, args[1], argb);
      } on ViewModelException catch (e) {
        return e.message;
      }
      return '${b.name}.${args[1]} set to ${_hex(argb)}.';
    },
  ));

  registry.register(ConsoleCommand(
    name: 'theme-clear',
    description: 'theme-clear <light|dark> <name> — put one colour back to the default',
    handler: (args) async {
      final b = args.length == 2 ? _byName(ThemeBrightness.values, args[0]) : null;
      if (b == null) return 'Usage: theme-clear <light|dark> <name>';
      await vm.clearColor(b, args[1]);
      return '${b.name}.${args[1]} back to the default.';
    },
  ));

  registry.register(ConsoleCommand(
    name: 'theme-reset',
    description: 'theme-reset — every colour back to the default, mode follows the device',
    handler: (_) async {
      await vm.reset();
      return 'Colours reset to the defaults.';
    },
  ));
}

T? _byName<T extends Enum>(List<T> values, String name) {
  for (final v in values) {
    if (v.name == name.toLowerCase()) return v;
  }
  return null;
}

/// #RRGGBB (opaque) or #AARRGGBB; the # is optional.
int? _parseHex(String s) {
  final h = s.startsWith('#') ? s.substring(1) : s;
  if (!RegExp(r'^([0-9A-Fa-f]{6}|[0-9A-Fa-f]{8})$').hasMatch(h)) return null;
  final v = int.parse(h, radix: 16);
  return h.length == 6 ? 0xFF000000 | v : v;
}

String _hex(int argb) => '#${argb.toRadixString(16).padLeft(8, '0').toUpperCase()}';

String _show(ThemeSettings t) {
  String colors(Map<String, int> m) => m.isEmpty
      ? '  (all defaults)'
      : (m.keys.toList()..sort()).map((k) => '  $k: ${_hex(m[k]!)}').join('\n');
  return 'mode: ${t.mode.name}\nlight:\n${colors(t.light)}\ndark:\n${colors(t.dark)}';
}
