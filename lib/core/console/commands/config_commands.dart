// lib/core/console/commands/config_commands.dart
import '../console_command.dart';
import '../console_registry.dart';
import '../../data/remote/supabase_config.dart';

void registerConfigCommands(ConsoleRegistry registry, SupabaseConfigStore config) {
  registry.register(ConsoleCommand(
    name: 'config-show',
    description: 'config-show — display current cloud/LAN Supabase settings',
    handler: (_) async => '''
cloud.url:     ${config.cloud.url.isEmpty ? '(not set)' : config.cloud.url}
cloud.anonKey: ${_mask(config.cloud.anonKey)}
lan.url:       ${config.lan.url.isEmpty ? '(not set)' : config.lan.url}
lan.anonKey:   ${_mask(config.lan.anonKey)}''',
  ));

  registry.register(ConsoleCommand(
    name: 'config-set-cloud-url',
    description: 'config-set-cloud-url <url>',
    handler: (args) async {
      if (args.isEmpty) return 'Usage: config-set-cloud-url <url>';
      await config.setCloud(url: args.first);
      return 'cloud.url set to ${args.first}';
    },
  ));

  registry.register(ConsoleCommand(
    name: 'config-set-cloud-key',
    description: 'config-set-cloud-key <anonKey>',
    handler: (args) async {
      if (args.isEmpty) return 'Usage: config-set-cloud-key <anonKey>';
      await config.setCloud(anonKey: args.first);
      return 'cloud.anonKey updated.';
    },
  ));

  registry.register(ConsoleCommand(
    name: 'config-set-lan-url',
    description: 'config-set-lan-url <url>',
    handler: (args) async {
      if (args.isEmpty) return 'Usage: config-set-lan-url <url>';
      await config.setLan(url: args.first);
      return 'lan.url set to ${args.first}';
    },
  ));

  registry.register(ConsoleCommand(
    name: 'config-set-lan-key',
    description: 'config-set-lan-key <anonKey>',
    handler: (args) async {
      if (args.isEmpty) return 'Usage: config-set-lan-key <anonKey>';
      await config.setLan(anonKey: args.first);
      return 'lan.anonKey updated.';
    },
  ));
}

String _mask(String key) {
  if (key.isEmpty) return '(not set)';
  if (key.length <= 8) return '*' * key.length;
  return '${key.substring(0, 4)}...${key.substring(key.length - 4)}';
}