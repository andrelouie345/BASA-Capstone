// lib/core/console/commands/config_commands.dart
import '../console_command.dart';
import '../console_registry.dart';
import '../../../viewmodels/server_config_viewmodel.dart';

void registerConfigCommands(ConsoleRegistry registry, ServerConfigViewModel vm) {
  registry.register(ConsoleCommand(
    name: 'config-show',
    description: 'config-show — display current cloud/LAN Supabase settings',
    handler: (_) async {
      final c = vm.show();
      return '''
cloud.url:     ${c.cloudUrl.isEmpty ? '(not set)' : c.cloudUrl}
cloud.anonKey: ${c.cloudKeyMasked}
lan.url:       ${c.lanUrl.isEmpty ? '(not set)' : c.lanUrl}
lan.anonKey:   ${c.lanKeyMasked}''';
    },
  ));

  registry.register(ConsoleCommand(
    name: 'config-set-cloud-url',
    description: 'config-set-cloud-url <url>',
    handler: (args) async {
      if (args.isEmpty) return 'Usage: config-set-cloud-url <url>';
      await vm.setCloud(url: args.first);
      return 'cloud.url set to ${args.first}';
    },
  ));

  registry.register(ConsoleCommand(
    name: 'config-set-cloud-key',
    description: 'config-set-cloud-key <anonKey>',
    handler: (args) async {
      if (args.isEmpty) return 'Usage: config-set-cloud-key <anonKey>';
      await vm.setCloud(anonKey: args.first);
      return 'cloud.anonKey updated.';
    },
  ));

  registry.register(ConsoleCommand(
    name: 'config-set-lan-url',
    description: 'config-set-lan-url <url>',
    handler: (args) async {
      if (args.isEmpty) return 'Usage: config-set-lan-url <url>';
      await vm.setLan(url: args.first);
      return 'lan.url set to ${args.first}';
    },
  ));

  registry.register(ConsoleCommand(
    name: 'config-set-lan-key',
    description: 'config-set-lan-key <anonKey>',
    handler: (args) async {
      if (args.isEmpty) return 'Usage: config-set-lan-key <anonKey>';
      await vm.setLan(anonKey: args.first);
      return 'lan.anonKey updated.';
    },
  ));
}
