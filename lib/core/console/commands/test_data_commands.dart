// lib/core/console/commands/test_data_commands.dart
import 'package:sqflite_common/sqflite.dart';
import 'package:supabase/supabase.dart';
import '../console_command.dart';
import '../console_registry.dart';
import '../../data/local/test_repository_sqlite.dart';
import '../../data/remote/supabase_config.dart';
import '../../data/remote/test_repository_supabase.dart';
import '../../../viewmodels/test_data_viewmodel.dart';

void registerTestDataCommands(
  ConsoleRegistry registry,
  TestDataViewModel vm,
  Database localDb,
  SupabaseConfigStore config,  
) {
  registry.register(ConsoleCommand(
    name: 'db-add',
    description: 'db-add <name> — insert a row into testTable',
    handler: (args) async {
      if (args.isEmpty) return 'Usage: db-add <name>';
      await vm.add(args.join(' '));
      return 'Added. Rows: ${vm.items.length}';
    },
  ));

  registry.register(ConsoleCommand(
    name: 'db-list',
    description: 'db-list — show all rows in testTable',
    handler: (_) async {
      await vm.refresh();
      if (vm.items.isEmpty) return '(empty)';
      return vm.items.map((i) => '${i.id}: ${i.name}').join('\n');
    },
  ));

  registry.register(ConsoleCommand(
    name: 'db-delete',
    description: 'db-delete <id> — delete a row by id',
    handler: (args) async {
      final id = int.tryParse(args.firstOrNull ?? '');
      if (id == null) return 'Usage: db-delete <id>';
      await vm.delete(id);
      return 'Deleted $id. Rows: ${vm.items.length}';
    },
  ));

  registry.register(ConsoleCommand(
    name: 'db-use',
    description: 'db-use <local|cloud|lan> — switch active backend',
    handler: (args) async {
      switch (args.firstOrNull) {
        case 'local':
          vm.useRepository(TestRepositorySqlite(localDb), 'local sqlite');
          return 'Now using local SQLite.';
        case 'cloud':
          if (config.cloud.url.isEmpty) return 'cloud.url not set. Use config-set-cloud-url first.';
          final client = SupabaseClient(config.cloud.url, config.cloud.anonKey);
          vm.useRepository(TestRepositorySupabase(client), 'cloud supabase');
          return 'Now using cloud Supabase (${config.cloud.url}).';
        case 'lan':
          if (config.lan.url.isEmpty) return 'lan.url not set. Use config-set-lan-url first.';
          final client = SupabaseClient(config.lan.url, config.lan.anonKey);
          vm.useRepository(TestRepositorySupabase(client), 'LAN supabase');
          return 'Now using LAN Supabase (${config.lan.url}).';
        default:
          return 'Usage: db-use <local|cloud|lan>';
      }
    },
  ));
}