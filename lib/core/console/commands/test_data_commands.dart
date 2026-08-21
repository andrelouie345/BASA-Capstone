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
          final cfg = SupabaseConfig.cloud();
          final client = SupabaseClient(cfg.url, cfg.anonKey);
          vm.useRepository(TestRepositorySupabase(client), 'cloud supabase');
          return 'Now using cloud Supabase (${cfg.url}).';
        case 'lan':
          final cfg = SupabaseConfig.lan(); // edit the host IP in supabase_config.dart
          final client = SupabaseClient(cfg.url, cfg.anonKey);
          vm.useRepository(TestRepositorySupabase(client), 'LAN supabase');
          return 'Now using LAN Supabase (${cfg.url}).';
        default:
          return 'Usage: db-use <local|cloud|lan>';
      }
    },
  ));
}