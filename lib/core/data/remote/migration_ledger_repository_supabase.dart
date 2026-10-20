// lib/core/data/remote/migration_ledger_repository_supabase.dart
import 'package:supabase/supabase.dart';
import '../../models/ledger_row.dart';
import '../../repositories/migration_ledger_repository.dart';

class MigrationLedgerRepositorySupabase implements MigrationLedgerRepository {
  final SupabaseClient client;
  MigrationLedgerRepositorySupabase(this.client);

  @override
  Future<List<LedgerRow>> fetchAll() async {
    final rows = await client.from('basa_migrations').select('id, name, app_update_required');
    return [for (final r in rows as List) LedgerRow.fromMap(r as Map<String, Object?>)];
  }
}
