// lib/core/repositories/migration_ledger_repository.dart
import '../models/ledger_row.dart';

/// Reads the server's basa_migrations ledger (cloud or LAN only; there is no
/// local copy). Throws on any error, including a missing table; the caller
/// decides how to report it.
abstract class MigrationLedgerRepository {
  Future<List<LedgerRow>> fetchAll();
}
