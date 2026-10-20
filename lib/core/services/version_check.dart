// lib/core/services/version_check.dart
//
// Rule A (docs/superpowers/specs/2026-10-20-version-check-design.md): compare
// the migrations an app was built for with the server's basa_migrations ledger.
// Pure: no I/O. AuthViewModel runs it at sign-in.

import '../models/ledger_row.dart';

enum VersionVerdict { ok, warn, blockServerOld, blockAppOld, noLedger, unreadable }

class VersionCheck {
  final VersionVerdict verdict;

  /// Migrations the app needs that the server doesn't have (id → name), oldest first.
  final Map<String, String> missingOnServer;

  /// Server migrations this app doesn't know, oldest first.
  final List<LedgerRow> unknownToApp;

  const VersionCheck(this.verdict, {this.missingOnServer = const {}, this.unknownToApp = const []});

  /// Sign-in is refused for every verdict except ok and warn.
  bool get blocks => verdict != VersionVerdict.ok && verdict != VersionVerdict.warn;
}

const _ledgerId = '20261020010000';
const _ledgerFile = '${_ledgerId}_basa_migrations.sql';

/// [server] null = the ledger table doesn't exist; empty = it exists but no
/// row is readable (it always holds at least the baseline and itself).
/// When the server is both older and newer, server-old wins: the server must
/// be fixed first.
VersionCheck checkVersion(Map<String, String> appKnown, List<LedgerRow>? server) {
  if (server == null) return const VersionCheck(VersionVerdict.noLedger);
  if (server.isEmpty) return const VersionCheck(VersionVerdict.unreadable);

  final onServer = {for (final r in server) r.id};
  final missingIds = appKnown.keys.where((id) => !onServer.contains(id)).toList()..sort();
  final unknown = server.where((r) => !appKnown.containsKey(r.id)).toList()
    ..sort((a, b) => a.id.compareTo(b.id));
  final missing = {for (final id in missingIds) id: appKnown[id]!};

  final VersionVerdict verdict;
  if (missing.isNotEmpty) {
    verdict = VersionVerdict.blockServerOld;
  } else if (unknown.any((r) => r.appUpdateRequired)) {
    verdict = VersionVerdict.blockAppOld;
  } else if (unknown.isNotEmpty) {
    verdict = VersionVerdict.warn;
  } else {
    verdict = VersionVerdict.ok;
  }
  return VersionCheck(verdict, missingOnServer: missing, unknownToApp: unknown);
}

/// The text shown to the user ('' for ok). Console and UI show it as-is.
String versionMessage(VersionCheck c) {
  String unknownLine(LedgerRow r) =>
      '  ${r.id}_${r.name}${r.appUpdateRequired ? ' (app update required)' : ''}';
  switch (c.verdict) {
    case VersionVerdict.ok:
      return '';
    case VersionVerdict.blockServerOld:
      return [
        'Sign-in refused: the database is older than this BASA app.',
        'Ask the person who manages the database to apply these files from',
        'supabase/migrations/, in this order (README section 2b):',
        for (final e in c.missingOnServer.entries) '  ${e.key}_${e.value}.sql',
      ].join('\n');
    case VersionVerdict.noLedger:
      return [
        'Sign-in refused: the database is older than this BASA app.',
        'Ask the person who manages the database to apply these files from',
        'supabase/migrations/, in this order (README section 2b):',
        '  $_ledgerFile',
        'and any earlier file from section 2b not yet applied.',
      ].join('\n');
    case VersionVerdict.blockAppOld:
      return [
        'Sign-in refused: this BASA app is too old for the database.',
        "Update BASA on this device. The database has changes this app can't work with:",
        for (final r in c.unknownToApp) unknownLine(r),
      ].join('\n');
    case VersionVerdict.warn:
      final ids = c.unknownToApp.map((r) => '${r.id}_${r.name}').join(', ');
      return "Note: the database has additions this app doesn't use yet\n"
          '($ids). Update BASA on this device when you can.';
    case VersionVerdict.unreadable:
      return 'Sign-in refused: the basa_migrations table is empty or not readable.\n'
          'Check its select policy (migration ${_ledgerId}_basa_migrations).';
  }
}

/// The login_logs.failure_reason for a refused sign-in.
String versionFailureReason(VersionCheck c) => switch (c.verdict) {
      VersionVerdict.blockServerOld => 'version check: server missing ${c.missingOnServer.keys.join(', ')}',
      VersionVerdict.blockAppOld => 'version check: app missing ${c.unknownToApp.map((r) => r.id).join(', ')}',
      VersionVerdict.noLedger => 'version check: no ledger table',
      VersionVerdict.unreadable => 'version check: ledger unreadable',
      VersionVerdict.ok || VersionVerdict.warn => '',
    };

/// Short label for the console's version-check.
String versionLabel(VersionVerdict v) => switch (v) {
      VersionVerdict.ok => 'OK',
      VersionVerdict.warn => 'WARN',
      VersionVerdict.blockServerOld => 'BLOCK: server older',
      VersionVerdict.blockAppOld => 'BLOCK: app older',
      VersionVerdict.noLedger => 'BLOCK: no ledger table',
      VersionVerdict.unreadable => 'BLOCK: ledger unreadable',
    };

/// The ledger couldn't be fetched after sign-in: refuse (fail closed).
const fetchFailedReason = 'version check: fetch failed';
String fetchFailedMessage(Object error) =>
    "Sign-in refused: couldn't check the database version ($error). Try again.";
