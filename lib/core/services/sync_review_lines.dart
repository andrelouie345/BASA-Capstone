// lib/core/services/sync_review_lines.dart
//
// An upload's payload as plain lines for the approver (sync spec 5.2, S6
// decision 5): one line per owner record, its items folded in, names from the
// approver's own copy ("DELA CRUZ, JUAN (G7 PLARIDEL): CRLA bosy mt, new, with
// Part 1"). A row this device doesn't hold prints its id instead.
import 'dart:convert';

import '../data/pull_tables.dart' show syncedTables, syncedParents;
import '../models/aral_class.dart' show AralClassProgram;

/// Rows this device holds, by table and key (as text).
class SyncReviewContext {
  final Map<String, Map<String, Map<String, Object?>>> rows;
  const SyncReviewContext(this.rows);

  Map<String, Object?>? row(String table, Object? key) => key == null ? null : rows[table]?['$key'];
}

/// The rows [describeUpload] would read from this device and [ctx] lacks
/// (table -> keys). New (negative) keys are never asked: they are in the
/// package. Ask again after adding them: a found row can name another one
/// (a deleted mark names its session).
Map<String, Set<String>> referencedKeys(List<Map<String, Object?>> records, SyncReviewContext ctx) =>
    (_Describer(records, ctx)..lines()).misses;

/// One line per owner record, in package order.
List<String> describeUpload(List<Map<String, Object?>> records, SyncReviewContext ctx) =>
    _Describer(records, ctx).lines();

/// Columns that are not news to an approver.
const _ignoredColumns = {'updated_at', 'updated_by', 'row_version', 'origin', 'created_at'};

/// Items counted under their record: (singular, plural), in display order.
const _itemNouns = <String, (String, String)>{
  'phil_iri_readings': ('reading', 'readings'),
  'phil_iri_answers': ('answer', 'answers'),
  'phil_iri_miscues': ('miscue', 'miscues'),
  'phil_iri_rubric_scores': ('rubric score', 'rubric scores'),
  'aral_attendance': ('attendance mark', 'attendance marks'),
  'aral_checkin_answers': ('answer', 'answers'),
};

/// CRLA parts: one per assessment, named rather than counted.
const _partNames = {
  'crla_part1_standard': 'Part 1',
  'crla_part1_english': 'Part 1 English',
  'crla_part2_fluency': 'Part 2',
};

class _Rec {
  final String table, op, key;
  final int? base;
  final Map<String, Object?>? row;
  _Rec(Map<String, Object?> m)
      : table = m['table'] as String,
        op = m['op'] as String,
        key = '${(m['key'] as Map).values.first}',
        base = (m['base_version'] as num?)?.toInt(),
        row = (m['row'] as Map?)?.cast<String, Object?>();

  bool get isFollowUp => op == 'update' && base == null;
}

/// What the package holds for one owner record.
class _Owner {
  final String table, key;
  _Rec? own; // the record's own insert / update / delete
  final followUps = <_Rec>[];
  final items = <_Rec>[];
  _Owner(this.table, this.key);
}

class _Describer {
  final List<_Rec> _recs;
  final SyncReviewContext _ctx;
  final misses = <String, Set<String>>{};

  /// Rows the package itself writes (inserts and updates), by table and key.
  final _pkgRows = <String, Map<String, Map<String, Object?>>>{};

  _Describer(List<Map<String, Object?>> records, this._ctx) : _recs = [for (final r in records) _Rec(r)] {
    for (final r in _recs) {
      if (r.row != null && !r.isFollowUp) (_pkgRows[r.table] ??= {})[r.key] = r.row!;
    }
  }

  List<String> lines() {
    final owners = <String, _Owner>{};
    for (final r in _recs) {
      final (table, key) = _ownerOf(r);
      final o = owners.putIfAbsent('$table $key', () => _Owner(table, key));
      if (table == r.table && key == r.key) {
        if (r.isFollowUp) {
          o.followUps.add(r);
        } else {
          o.own ??= r;
        }
      } else {
        o.items.add(r);
      }
    }
    return [for (final o in owners.values) _line(o)];
  }

  // ---- Lookups ----

  /// The package's row, else this device's (a miss is recorded).
  Map<String, Object?>? _row(String table, Object? key) {
    if (key == null) return null;
    return _pkgRows[table]?['$key'] ?? _local(table, key);
  }

  /// This device's row; remembers what it lacks (never a new, negative key).
  Map<String, Object?>? _local(String table, Object? key) {
    if (key == null) return null;
    final found = _ctx.row(table, key);
    if (found == null && (int.tryParse('$key') ?? 1) > 0) (misses[table] ??= {}).add('$key');
    return found;
  }

  /// The owner record a record belongs to: itself, or up its parents as far
  /// as the rows tell.
  (String, String) _ownerOf(_Rec r) {
    var table = r.table;
    var key = r.key;
    var row = r.row ?? _local(table, key);
    while (syncedParents.containsKey(table)) {
      final (parentTable, column) = syncedParents[table]!;
      final parentKey = syncedTables[table] == column ? key : row?[column];
      if (parentKey == null) break;
      table = parentTable;
      key = '$parentKey';
      // The parent's row only matters when it has a parent of its own.
      row = syncedParents.containsKey(table) ? _row(table, key) : null;
    }
    return (table, key);
  }

  // ---- Text ----

  String _line(_Owner o) {
    final own = o.own;
    final parts = <String>[];
    if (own != null) {
      parts.add(switch (own.op) {
        'insert' => 'new',
        'delete' => 'deleted',
        _ => _changed(own),
      });
    }
    final items = _itemsText(o, under: own?.op == 'insert');
    if (items != null) parts.add(items);
    if (o.followUps.isNotEmpty) {
      final status = o.followUps.last.row?['status'];
      if (status != null) parts.add('$status');
    }
    if (parts.isEmpty) parts.add('changed');
    final (who, what) = _label(o.table, o.key);
    return who == null ? '$what: ${parts.join(', ')}' : '$who: ${[what, ...parts].join(', ')}';
  }

  String _changed(_Rec r) {
    final local = _local(r.table, r.key);
    if (local == null) return 'changed';
    final cols = [
      for (final e in r.row!.entries)
        if (!_ignoredColumns.contains(e.key) && _norm(e.value) != _norm(local[e.key])) e.key,
    ];
    return cols.isEmpty ? 'changed' : 'changed (${cols.join(', ')})';
  }

  /// "with Part 1, Part 2" / "with 2 attendance marks" under a new record;
  /// "1 attendance mark new, 1 changed" under a server record.
  String? _itemsText(_Owner o, {required bool under}) {
    if (o.items.isEmpty) return null;
    final byTable = <String, List<_Rec>>{};
    for (final r in o.items) {
      (byTable[r.table] ??= []).add(r);
    }
    final ordered = [
      ..._partNames.keys.where(byTable.containsKey),
      ..._itemNouns.keys.where(byTable.containsKey),
      ...byTable.keys.where((t) => !_partNames.containsKey(t) && !_itemNouns.containsKey(t)),
    ];
    if (under) {
      return 'with ${[
        for (final t in ordered)
          _partNames[t] ?? _count(byTable[t]!.length, _itemNouns[t] ?? (t, t)),
      ].join(', ')}';
    }
    return [
      for (final t in ordered) _opsText(t, byTable[t]!),
    ].join('; ');
  }

  String _opsText(String table, List<_Rec> recs) {
    final counts = <String, int>{};
    for (final r in recs) {
      final word = switch (r.op) { 'insert' => 'new', 'delete' => 'deleted', _ => 'changed' };
      counts[word] = (counts[word] ?? 0) + 1;
    }
    final entries = counts.entries.toList();
    final part = _partNames[table];
    if (part != null) return '$part ${entries.map((e) => e.key).join(', ')}';
    final noun = _itemNouns[table] ?? (table, table);
    return [
      for (var i = 0; i < entries.length; i++)
        i == 0 ? '${_count(entries[i].value, noun)} ${entries[i].key}' : '${entries[i].value} ${entries[i].key}',
    ].join(', ');
  }

  /// The learner (null for records that aren't a learner's) and what the
  /// record is.
  (String?, String) _label(String table, String key) {
    final row = _row(table, key);
    if (row == null) {
      return (null, table == 'aral_sessions' ? 'ARAL session (id $key)' : '$table $key');
    }
    return switch (table) {
      'crla_assessments' => (_learner(row), 'CRLA ${row['round']} ${row['subject_variant']}'),
      'phil_iri_gst_results' => (_learner(row), 'Phil-IRI GST ${row['total_score']}/${row['max_score']}'),
      'phil_iri_assessments' => (_learner(row), 'Phil-IRI ${row['round']}'),
      'aral_classes' => (null, 'ARAL class "${row['class_name']}" (G${row['grade_band']}, ${_program(row['program'])}, '
          'tutor ${row['tutor_id'] == null ? '-' : _user('${row['tutor_id']}')})'),
      'aral_enrollments' => (
          _learner(row),
          ['ARAL', row['key_stage'], if (row['track'] != null) row['track']].join(' ') + _placedIn(row['class_id'])
        ),
      'aral_sessions' => (
          null,
          row['session_no'] == null
              ? 'ARAL session (id $key)'
              : 'ARAL session ${row['session_no']} (${row['held_on'] ?? '?'})'
        ),
      'aral_tutor_settings' => (null, 'ARAL tutor setting (${_user(key)})'),
      'aral_irip_weeks' =>
        (_enrollmentLearner(row), 'IRIP cycle ${row['cycle_no']} week ${row['week_no']} ${row['strand']}'),
      'aral_checkins' => (_enrollmentLearner(row), 'ARAL check-in attempt ${row['attempt_no']}'),
      'aral_readability_logs' => (_enrollmentLearner(row), 'readability "${row['title']}"'),
      _ => (null, '$table $key'),
    };
  }

  /// ' placed in class "7-Rose"' for a roster entry with a class, else ''.
  String _placedIn(Object? classId) {
    if (classId == null) return '';
    final c = _row('aral_classes', classId);
    return ' placed in class ${c == null ? '#$classId' : '"${c['class_name']}"'}';
  }

  static String _program(Object? value) {
    try {
      return AralClassProgram.fromString('$value').label;
    } on ArgumentError {
      return '$value';
    }
  }

  String _enrollmentLearner(Map<String, Object?> row) {
    final e = _row('aral_enrollments', row['enrollment_id']);
    return e == null ? 'enrollment ${row['enrollment_id']}' : _learner(e);
  }

  /// "DELA CRUZ, JUAN (G7 PLARIDEL)", or ids where this device lacks the rows.
  String _learner(Map<String, Object?> row) {
    final s = _local('students', row['student_id']);
    final sec = _local('sections', row['section_id']);
    final name = s == null ? 'learner ${row['student_id'] ?? '?'}' : '${s['last_name']}, ${s['first_name']}';
    final section =
        sec == null ? 'section ${row['section_id'] ?? '?'}' : 'G${sec['grade_level']} ${sec['section_name']}';
    return '$name ($section)';
  }

  String _user(String id) {
    final u = _local('users', id);
    final name = u?['full_name'] as String?;
    return name != null && name.trim().isNotEmpty ? name : (u?['email'] as String?) ?? id;
  }
}

String _count(int n, (String, String) noun) => '$n ${n == 1 ? noun.$1 : noun.$2}';

/// One form for both sides of a comparison: SQLite keeps booleans as 0/1
/// and JSON as text, the package as true/false and decoded values.
Object? _norm(Object? v) => switch (v) {
      true => 1,
      false => 0,
      num n => n.toDouble(),
      Map() || List() => jsonEncode(v),
      String s when s.startsWith('{') || s.startsWith('[') => _reencode(s),
      _ => v,
    };

Object _reencode(String s) {
  try {
    return jsonEncode(jsonDecode(s));
  } catch (_) {
    return s;
  }
}
