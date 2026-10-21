// lib/core/services/sync_upload_rules.dart
//
// Turning a local row into the server's shape for an upload (sync spec
// section 4). Pure Dart.
import 'dart:convert';
import 'dart:math';

/// The pending lock's refusal (spec 3.2); the SQLite lock triggers raise it,
/// and every ViewModel shows it as is.
const pendingLockMessage = 'This record is waiting for approval. Withdraw the upload to change it.';

/// Columns that exist only on the device and never travel.
const localOnlyColumns = {'origin', 'row_version'};

/// Boolean columns of the synced tables (SQLite stores 0/1). From the
/// baseline; a new boolean column on a synced table must be added here.
const serverBoolColumns = <String, Set<String>>{
  'phil_iri_readings': {
    'obs_word_by_word', 'obs_lacks_expression', 'obs_voice_inaudible', 'obs_disregards_punctuation',
    'obs_points_to_words', 'obs_little_analysis',
  },
  'phil_iri_miscues': {'self_corrected'},
  'phil_iri_answers': {'is_correct', 'looked_back'},
  'aral_tutor_settings': {'multiple_sessions_per_day'},
  'aral_checkin_answers': {'is_correct'},
};

/// jsonb columns of the synced tables (SQLite stores JSON text). A new jsonb
/// column on a synced table must be added here.
const serverJsonColumns = <String, Set<String>>{
  'crla_assessments': {'thresholds_snapshot'},
  'phil_iri_assessments': {'thresholds_snapshot'},
};

/// The largest package one upload may carry (bytes of JSON). Measured
/// 2026-10-21 on the dev cloud: 1, 2, 4 and 8 MB inserts were all accepted
/// (8 MB took about 4 s); testing stopped there. About 80% of that, so a
/// slow phone link or a stricter self-hosted proxy still has room. A typical
/// record is well under 1 KB.
const maxPackageBytes = 6 * 1024 * 1024;

/// [local] as the server stores it: local-only columns and the key column
/// dropped, booleans and JSON converted. An insert omits nulls so the
/// server's defaults apply; an update sends every column.
Map<String, Object?> toServerRow(String table, Map<String, Object?> local, {required String keyColumn, required bool insert}) {
  final bools = serverBoolColumns[table] ?? const {};
  final jsons = serverJsonColumns[table] ?? const {};
  final out = <String, Object?>{};
  local.forEach((column, value) {
    if (localOnlyColumns.contains(column) || column == keyColumn) return;
    if (insert && value == null) return;
    out[column] = switch (value) {
      int v when bools.contains(column) => v != 0,
      String v when jsons.contains(column) => jsonDecode(v),
      _ => value,
    };
  });
  return out;
}

/// A random (version 4) uuid.
String newUuidV4([Random? random]) {
  final r = random ?? Random.secure();
  final b = List<int>.generate(16, (_) => r.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
}

/// Follow-up updates for a NEW record of [table] (migration
/// 20261021010000, S5 review C1): the server's insert trigger resets these
/// columns (a Phil-IRI session arrives in_progress, an ARAL learner active),
/// so they travel again as updates after the record and its items. The
/// server only finalizes a completed session, hence two steps. [row] is the
/// insert's server-shaped row.
List<Map<String, Object?>> followUpsForNew(String table, Map<String, Object?> row) => switch ((table, row['status'])) {
      ('phil_iri_assessments', 'completed') => [
          {'status': 'completed'},
        ],
      ('phil_iri_assessments', 'finalized') => [
          {'status': 'completed'},
          {'status': 'finalized', 'thresholds_snapshot': row['thresholds_snapshot']},
        ],
      ('aral_enrollments', 'exited') => [
          {'status': 'exited', 'exited_on': row['exited_on'], 'exit_reason': row['exit_reason']},
        ],
      _ => const [],
    };

/// A change to a server Phil-IRI session that ends finalized goes up as
/// "completed" plus a follow-up "finalized": the server only finalizes a
/// completed session, and the device can't know whether the server's copy is
/// still in progress. Returns the row for the versioned update and the
/// follow-ups (none for any other change).
(Map<String, Object?>, List<Map<String, Object?>>) splitServerUpdate(String table, Map<String, Object?> row) {
  if (table != 'phil_iri_assessments' || row['status'] != 'finalized') return (row, const []);
  return (
    {...row, 'status': 'completed', 'thresholds_snapshot': null, 'finalized_at': null},
    [
      {'status': 'finalized', 'thresholds_snapshot': row['thresholds_snapshot']},
    ],
  );
}
