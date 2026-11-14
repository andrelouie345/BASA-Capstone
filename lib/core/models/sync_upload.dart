// lib/core/models/sync_upload.dart
//
// What an upload sends, finds and gets back (sync spec sections 4-5,
// docs/superpowers/specs/2026-10-20-sync-design.md). The package shape is the
// one the server's sync_check_payload accepts
// (supabase/migrations/20261020020000_sync_uploads.sql).
import 'sync_pull.dart';

/// One record of a package: a new row (insert, negative id), or a change to
/// a server row (update / delete, with the server version it was based on).
class SyncRecord {
  final String table;
  final String op; // insert | update | delete
  final String keyColumn;
  final Object key; // the record's key (an int for every synced table since v37)
  final int? baseVersion;
  final Map<String, Object?>? row;

  const SyncRecord({
    required this.table,
    required this.op,
    required this.keyColumn,
    required this.key,
    this.baseVersion,
    this.row,
  });

  /// The key as sync_pending / sync_changes store it.
  String get rowKey => '$key';

  /// An update without a base version: it follows the same record earlier
  /// in the package (migration 20261021010000).
  bool get isFollowUp => op == 'update' && baseVersion == null;

  Map<String, Object?> toJson() => {
        'table': table,
        'op': op,
        'key': {keyColumn: key},
        if (baseVersion != null) 'base_version': baseVersion,
        if (row != null) 'row': row,
      };

  @override
  String toString() => '$table $key $op';
}

/// Everything this device would upload now.
class SyncPackage {
  final String release;
  final String deviceId;
  final List<SyncRecord> records;

  /// Counts per kind and section (the pull's local-work lines, without the
  /// records already waiting in an upload).
  final List<LocalWorkLine> summary;

  const SyncPackage({required this.release, required this.deviceId, required this.records, required this.summary});

  bool get isEmpty => records.isEmpty;

  /// Rows sent, each once (a follow-up update is not another row).
  int get rowCount => records.where((r) => !r.isFollowUp).length;

  Map<String, Object?> toJson() => {
        'format': 1,
        'release': release,
        'device_id': deviceId,
        'records': [for (final r in records) r.toJson()],
      };

  /// What sync_uploads.summary holds; approvers' listings read only this.
  Map<String, Object?> summaryJson() => {
        'total': summary.fold<int>(0, (n, l) => n + l.count),
        'rows': rowCount,
        'lines': [
          for (final l in summary)
            {
              'kind': l.kind,
              'section_id': l.sectionId,
              'grade_level': l.gradeLevel,
              'section_name': l.sectionName,
              'school_year': l.schoolYear,
              'count': l.count,
            },
        ],
      };
}

/// Something that stops an upload until resolved (sync-resolve).
class SyncProblem {
  final String table;
  final String key;

  /// 'conflict' (server version moved on), 'server_deleted' (the server no
  /// longer gives this record) or [learnerArchivedKind] (a new record of a
  /// learner archived that school year: the server refuses it).
  final String kind;
  final int? baseVersion;
  final int? serverVersion;

  /// For [learnerArchivedKind]: the learner, e.g. "Cruz, J. (archived on
  /// 2026-11-12, dropped out)".
  final String? learner;

  /// For [learnerArchivedKind]: the learner was transferred to another
  /// school that year (SF1 leavers D15): nobody here can restore them.
  final bool transferred;

  const SyncProblem(
      {required this.table,
      required this.key,
      required this.kind,
      this.baseVersion,
      this.serverVersion,
      this.learner,
      this.transferred = false});

  @override
  String toString() => switch (kind) {
        'conflict' => '$table $key: changed on the server (yours from version $baseVersion, server now $serverVersion)',
        'server_deleted' => '$table $key: no longer on the server for you (deleted, or out of your sections)',
        learnerArchivedKind when transferred => '$table $key: a new record of $learner; the server refuses it. '
            'Drop it with sync-resolve $table $key server',
        learnerArchivedKind => '$table $key: a new record of $learner; the server refuses it. '
            'Ask the coordinator to restore the learner, or drop it with sync-resolve $table $key server',
        _ => '$table $key: $kind',
      };
}

/// [SyncProblem.kind] of a new record whose learner was archived in that
/// school year (SF1 leavers D11): only "server" (drop it) resolves it.
const learnerArchivedKind = 'learner_archived';

/// Tables whose new records follow a moved learner or stop on an archived
/// one at upload (sync_apply, SF1 leavers D11).
const syncLearnerTables = {'crla_assessments', 'phil_iri_assessments', 'phil_iri_gst_results'};

/// A learner's archived enrollment in one school year, as the server holds
/// it (sync_archived_learners).
/// [schoolId] is the record's school: a learner transferred away from it
/// that year is listed too, with that school's archive (I2).
typedef SyncArchivedLearner = ({
  int studentId,
  String schoolYear,
  int schoolId,
  String status,
  String? leftOn,
  String? name,

  /// Set when the learner was transferred away from [schoolId] that year
  /// (ISO date); [status]/[leftOn] are then that school's archive.
  String? transferredOn,
});

/// (learner, school year, the record's school) of a new record.
typedef SyncLearnerKey = (int studentId, String schoolYear, int schoolId);

/// "Cruz, J. (archived on 2026-11-12, dropped out)", or "Cruz, J.
/// (transferred to another school on 2026-11-13)".
String syncArchivedLearnerText(SyncArchivedLearner a) => a.transferredOn != null
    ? '${a.name ?? 'learner ${a.studentId}'} (transferred to another school on ${a.transferredOn})'
    : '${a.name ?? 'learner ${a.studentId}'} (archived on ${a.leftOn ?? '?'}, ${a.status.replaceAll('_', ' ')})';

/// One of the signed-in user's uploads, as the server holds it (never the
/// payload).
class SyncUploadRow {
  final int id;
  final String? uploaderId;

  /// null only for a superadmin's own upload.
  final int? schoolId;

  /// pending | applied | rejected | withdrawn | conflict | error
  final String status;
  final String? reason;
  final List<SyncProblem> conflicts;

  /// {table: {"-5": 812}} after an applied upload.
  final Map<String, Map<String, int>> idMap;
  final DateTime createdAt;
  final DateTime? decidedAt;
  final Map<String, Object?> summary;

  /// What the server noted on an applied upload, e.g. "2 records followed a
  /// section move" (SF1 leavers D11); null when nothing.
  final String? note;

  /// The package; only read for one upload (SyncReviewViewModel.details).
  final Map<String, Object?>? payload;

  const SyncUploadRow({
    required this.id,
    this.uploaderId,
    this.schoolId,
    this.payload,
    required this.status,
    required this.createdAt,
    this.reason,
    this.conflicts = const [],
    this.idMap = const {},
    this.decidedAt,
    this.summary = const {},
    this.note,
  });

  int get total => (summary['total'] as num?)?.toInt() ?? 0;

  /// Rows sent (records and their items).
  int get rows => (summary['rows'] as num?)?.toInt() ?? 0;

  /// The counts per kind and section the uploader's device wrote.
  List<LocalWorkLine> get summaryLines => [
        for (final l in (summary['lines'] as List?) ?? const [])
          LocalWorkLine(
            kind: '${l['kind']}',
            count: (l['count'] as num?)?.toInt() ?? 0,
            sectionId: (l['section_id'] as num?)?.toInt(),
            gradeLevel: l['grade_level'] as String?,
            sectionName: l['section_name'] as String?,
            schoolYear: l['school_year'] as String?,
          ),
      ];

  /// The package's records (empty when it wasn't read).
  List<Map<String, Object?>> get records => [
        for (final r in (payload?['records'] as List?) ?? const []) (r as Map).cast<String, Object?>(),
      ];

  factory SyncUploadRow.fromMap(Map<String, dynamic> m) => SyncUploadRow(
        id: (m['id'] as num).toInt(),
        status: m['status'] as String,
        reason: m['reason'] as String?,
        uploaderId: m['uploader_id'] as String?,
        schoolId: (m['school_id'] as num?)?.toInt(),
        conflicts: parseSyncConflicts(m['conflicts']),
        idMap: {
          for (final e in ((m['id_map'] as Map?) ?? const {}).entries)
            e.key as String: {for (final k in (e.value as Map).entries) k.key as String: (k.value as num).toInt()},
        },
        createdAt: DateTime.parse(m['created_at'] as String),
        decidedAt: m['decided_at'] == null ? null : DateTime.parse(m['decided_at'] as String),
        summary: Map<String, Object?>.from((m['summary'] as Map?) ?? const {}),
        payload: (m['payload'] as Map?)?.cast<String, Object?>(),
        note: m['note'] as String?,
      );
}

/// sync_uploads.conflicts / sync_apply's conflicts as problems.
List<SyncProblem> parseSyncConflicts(Object? raw) => [
      for (final c in (raw as List?) ?? const [])
        SyncProblem(
          table: c['table'] as String,
          key: '${(c['key'] as Map).values.first}',
          kind: c['server_row'] == null ? 'server_deleted' : 'conflict',
          baseVersion: (c['base_version'] as num?)?.toInt(),
          serverVersion: (c['server_version'] as num?)?.toInt(),
        ),
    ];

/// What sync_apply answered.
class SyncApplyResult {
  final String status;
  final String? reason;
  final List<SyncProblem> conflicts;

  /// The server's note on an applied upload (see [SyncUploadRow.note]).
  final String? note;
  const SyncApplyResult({required this.status, this.reason, this.conflicts = const [], this.note});
}

/// What happened to an upload since this device last looked.
class SyncOutcome {
  final int uploadId;
  final String status;
  final String? reason;
  final List<SyncProblem> conflicts;

  /// Rows of this device that it covered (records and their items).
  final int records;

  /// The server's note on an applied upload (see [SyncUploadRow.note]).
  final String? note;

  const SyncOutcome(
      {required this.uploadId,
      required this.status,
      required this.records,
      this.reason,
      this.conflicts = const [],
      this.note});

  @override
  String toString() => switch (status) {
        'applied' => 'Upload $uploadId applied: $records row(s) now on the server.${note == null ? '' : ' $note.'}',
        'rejected' => 'Upload $uploadId rejected: ${reason ?? "no reason given"}. Its $records row(s) can be changed again.',
        'error' => 'Upload $uploadId failed on the server: ${reason ?? "unknown error"}. Its $records row(s) can be changed again.',
        'withdrawn' => 'Upload $uploadId withdrawn; its $records row(s) can be changed again.',
        'conflict' => reason != null
            ? 'Upload $uploadId stopped on ${conflicts.length} conflict(s); $reason. Its $records row(s) stay '
                'locked until then:\n${conflicts.map((c) => '  $c').join('\n')}'
            : 'Upload $uploadId stopped on ${conflicts.length} conflict(s) and was withdrawn on the server; its '
                '$records row(s) can be changed again. Resolve with sync-resolve, then upload again:\n'
                '${conflicts.map((c) => '  $c').join('\n')}',
        'unknown' => 'Upload $uploadId: the server does not show it to you; its $records row(s) stay locked.',
        _ => 'Upload $uploadId: $status.',
      };
}

/// What an upload would send now, and what stops it.
class SyncPreview {
  final SyncPackage package;
  final List<SyncProblem> problems;

  /// Decisions taken in on the way (refreshStatus).
  final List<SyncOutcome> settled;

  const SyncPreview({required this.package, required this.problems, this.settled = const []});
}

enum SyncChoice { mine, server }

/// What sync-resolve did.
class SyncResolution {
  final String table;
  final String key;
  final SyncChoice choice;

  /// The server's version now, or null when the server no longer has it.
  final int? serverVersion;

  /// A new record of an archived learner, dropped from this device with its
  /// items (never on the server).
  final bool droppedNew;

  const SyncResolution(
      {required this.table, required this.key, required this.choice, this.serverVersion, this.droppedNew = false});

  @override
  String toString() => droppedNew
      ? 'Dropped $table $key and its items from this device: the server refuses new records of an archived learner. '
          'The rest of your work can be uploaded.'
      : choice == SyncChoice.mine
      ? serverVersion == null
          ? 'Kept your delete of $table $key (the server no longer has it either).'
          : 'Kept yours for $table $key (will overwrite server version $serverVersion).'
      : serverVersion == null
          ? 'Took the server\'s side for $table $key: it is gone there, so it is removed here.'
          : 'Took the server\'s copy of $table $key (version $serverVersion).';
}

/// An upload being sent: kept on the device (with its records locked under
/// upload 0) until the server's answer is known, so a lost answer can be
/// found again by [clientUploadId] instead of sending twice.
class InFlightUpload {
  final String clientUploadId;
  final Map<String, Object?> payload;
  final Map<String, Object?> summary;

  const InFlightUpload({required this.clientUploadId, required this.payload, required this.summary});

  int get recordCount => (payload['records'] as List?)?.length ?? 0;
}

/// What sync-upload did.
class SyncUploadResult {
  final int uploadId;
  final int records;

  /// Set when the upload was decided at once (auto-approve, or an
  /// admin/coordinator's own upload).
  final SyncOutcome? outcome;

  /// Why applying at once failed (e.g. the release guard); the upload stays
  /// pending.
  final String? applyError;

  /// Why the decision could not be read back after sending (the upload is
  /// on the server either way).
  final String? statusError;

  const SyncUploadResult(
      {required this.uploadId, required this.records, this.outcome, this.applyError, this.statusError});

  @override
  String toString() =>
      outcome?.toString() ??
      (statusError != null
          ? 'Upload $uploadId sent: $records row(s). Its decision could not be read ($statusError); check the upload status (sync-status).'
          : 'Upload $uploadId sent: $records row(s), waiting for approval.'
              '${applyError == null ? '' : '\nIt could not be applied at once: $applyError'}');
}

/// What sync() did: the preview, the upload (null when nothing was sent)
/// and the pull.
class SyncRunResult {
  final SyncPreview preview;
  final SyncUploadResult? upload;
  final PullResult pull;
  const SyncRunResult({required this.preview, required this.upload, required this.pull});
}
