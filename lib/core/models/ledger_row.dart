// lib/core/models/ledger_row.dart

/// One row of the server's basa_migrations ledger: a migration applied to
/// that database.
class LedgerRow {
  final String id; // filename timestamp, e.g. '20261019060000'
  final String name;
  final bool appUpdateRequired;

  const LedgerRow({required this.id, required this.name, required this.appUpdateRequired});

  factory LedgerRow.fromMap(Map<String, Object?> m) => LedgerRow(
        id: m['id'] as String,
        name: m['name'] as String,
        appUpdateRequired: m['app_update_required'] as bool,
      );
}
