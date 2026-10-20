// lib/core/models/sync_pull.dart
//
// What a pull keeps, refuses on and reports (sync spec section 7).

/// Work on this device that is not on the server yet, per kind and section
/// (sectionId null = no section, e.g. ARAL sessions, journal lines).
class LocalWorkLine {
  final String kind;
  final int? sectionId;
  final int count;
  final String? gradeLevel;
  final String? sectionName;
  final String? schoolYear;

  const LocalWorkLine({
    required this.kind,
    required this.count,
    this.sectionId,
    this.gradeLevel,
    this.sectionName,
    this.schoolYear,
  });

  @override
  String toString() => sectionId == null
      ? '$count $kind'
      : '$count $kind in section $sectionId (grade ${gradeLevel ?? "?"} ${sectionName ?? "unknown"}, ${schoolYear ?? ""})';
}

/// The user whose data is on this device: the last successful pull.
class PullOwner {
  final String userId;
  final String? email;
  final String? pulledAt;
  const PullOwner({required this.userId, this.email, this.pulledAt});

  @override
  String toString() => '${email ?? userId} on ${pulledAt ?? "?"}';
}

/// A kept local row whose reference is missing after the merge.
class PullOrphan {
  final String table;
  final String key;
  final String column;
  final String refTable;
  final Object refValue;

  const PullOrphan({
    required this.table,
    required this.key,
    required this.column,
    required this.refTable,
    required this.refValue,
  });

  @override
  String toString() => '$table $key: $refTable $refValue ($column) is no longer on the server for you';
}

/// Thrown by a merge that found orphans; the merge was rolled back.
class PullOrphansException implements Exception {
  final List<PullOrphan> orphans;
  const PullOrphansException(this.orphans);

  @override
  String toString() => '${orphans.length} orphaned local record(s)';
}

/// What a merge wrote and kept.
class PullMerge {
  /// Server rows written, per table (pullOrder order).
  final Map<String, int> serverRows;

  /// New records (never on the server) kept, counted as localWork does: a
  /// new record's own items travel with it.
  final int keptNew;

  /// Pulled rows edited or deleted on this device (journal lines) kept.
  final int keptChanged;

  /// Records waiting in an upload kept (still locked).
  final int keptPending;

  /// Server rows not written because they hang (directly or further down)
  /// under a record deleted here.
  final int skippedUnderDeleted;

  /// Server rows not written because a kept local row has the same key
  /// or the same natural key (a tutor setting, a CRLA part added to a pulled
  /// assessment, a mark for the same session and learner, a CRLA attempt),
  /// and the server rows under them.
  final int skippedNewClash;

  /// New records deleted by discard-local (counted like [keptNew]).
  final int discarded;

  /// Changes to server records undone by discard-local (journal lines).
  final int discardedChanges;

  /// Pending lines dropped by discard-local.
  final int discardedPending;

  const PullMerge({
    required this.serverRows,
    this.keptNew = 0,
    this.keptChanged = 0,
    this.keptPending = 0,
    this.skippedUnderDeleted = 0,
    this.skippedNewClash = 0,
    this.discarded = 0,
    this.discardedChanges = 0,
    this.discardedPending = 0,
  });
}

/// What a pull would do, before it runs.
class PullPreview {
  final PullOwner? owner;
  final String? currentUserId;
  final String? currentEmail;
  final List<LocalWorkLine> localWork;

  const PullPreview({required this.owner, required this.currentUserId, required this.currentEmail, required this.localWork});

  /// Someone else's data is on this device.
  bool get ownerSwitch => owner != null && owner!.userId != currentUserId;

  int get localTotal => localWork.fold(0, (n, l) => n + l.count);
}

/// A finished pull.
class PullResult {
  final PullMerge merge;
  final bool ownerChanged;
  final String? previousOwnerEmail;

  /// "CRLA mosy2 (row 12)" for calendar rows whose round this app doesn't know.
  final List<String> unknownCalendarRounds;

  const PullResult({
    required this.merge,
    required this.ownerChanged,
    required this.previousOwnerEmail,
    required this.unknownCalendarRounds,
  });
}
