// lib/core/data/local/aral_checkin_repository_sqlite.dart
//
// Check-in tools/items (mirror-only content) and check-ins with answers (the
// main write path, offline-first). The local triggers (aral_local_schema.dart)
// re-check the cloud's rules, number attempts and score choice items.
import 'package:sqflite_common/sqflite.dart';
import 'sync_local_writes.dart';
import 'mirror_write.dart';
import 'sqlite_values.dart';
import '../../models/aral_checkin.dart';
import '../../models/aral_enrollment.dart';
import '../../repositories/aral_checkin_repository.dart';

class AralCheckinRepositorySqlite implements AralCheckinRepository {
  final Database db;
  AralCheckinRepositorySqlite(this.db);

  static String _now() => DateTime.now().toUtc().toIso8601String();

  @override
  Future<List<AralCheckinTool>> tools() async {
    final rows = await db.query('aral_checkin_tools', where: 'is_active = 1', orderBy: 'key_stage, track, checkpoint');
    return rows.map(AralCheckinTool.fromMap).toList();
  }

  @override
  Future<AralCheckinTool?> findTool(int id) async {
    final rows = await db.query('aral_checkin_tools', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : AralCheckinTool.fromMap(rows.first);
  }

  @override
  Future<AralCheckinTool?> toolFor(AralKeyStage keyStage, AralTrack track, int checkpoint) async {
    final rows = await db.query('aral_checkin_tools',
        where: 'key_stage = ? AND track = ? AND checkpoint = ? AND is_active = 1',
        whereArgs: [keyStage.name, track.name, checkpoint],
        limit: 1);
    return rows.isEmpty ? null : AralCheckinTool.fromMap(rows.first);
  }

  @override
  Future<List<AralCheckinItem>> items(int toolId) async {
    final rows = await db.query('aral_checkin_items', where: 'tool_id = ?', whereArgs: [toolId], orderBy: 'item_no');
    return rows.map(AralCheckinItem.fromMap).toList();
  }

  @override
  Future<List<AralCheckin>> checkins(int enrollmentId) async {
    final rows = await db.query('aral_checkins',
        where: 'enrollment_id = ?', whereArgs: [enrollmentId], orderBy: 'tool_id, attempt_no');
    return rows.map(AralCheckin.fromMap).toList();
  }

  @override
  Future<AralCheckin?> findCheckin(int id) async {
    final rows = await db.query('aral_checkins', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : AralCheckin.fromMap(rows.first);
  }

  @override
  Future<AralCheckin> insertCheckin(AralCheckin checkin) async {
    final now = _now();
    final row = toSqliteRow(checkin.toMap())
      ..['id'] = await nextLocalId(db)
      ..remove('attempt_no') // 0 = the trigger assigns the next number
      ..['created_at'] = now
      ..['updated_at'] = now;
    final id = await db.insert('aral_checkins', row);
    return (await findCheckin(id))!; // re-read: the trigger set attempt_no
  }

  @override
  Future<AralCheckin> updateCheckin(AralCheckin checkin) async {
    if (checkin.id == null) throw ArgumentError('updateCheckin needs an id');
    final n = await db.update(
        'aral_checkins', {'taken_on': checkin.takenOn, 'notes': checkin.notes, 'updated_at': _now()},
        where: 'id = ?', whereArgs: [checkin.id]);
    if (n == 0) throw StateError('No check-in ${checkin.id}');
    return (await findCheckin(checkin.id!))!;
  }

  @override
  Future<void> deleteCheckin(int id) async {
    // Local foreign keys are off: the answers go too (the cloud cascades).
    await db.transaction((txn) async {
      await txn.delete('aral_checkin_answers', where: 'checkin_id = ?', whereArgs: [id]);
      await txn.delete('aral_checkins', where: 'id = ?', whereArgs: [id]);
    });
  }

  @override
  Future<List<AralCheckinAnswer>> answers(int checkinId) async {
    final rows = await db.query('aral_checkin_answers', where: 'checkin_id = ?', whereArgs: [checkinId]);
    return rows.map(AralCheckinAnswer.fromMap).toList();
  }

  Future<AralCheckinAnswer?> _findAnswer(int checkinId, int itemId) async {
    final rows = await db.query('aral_checkin_answers',
        where: 'checkin_id = ? AND item_id = ?', whereArgs: [checkinId, itemId], limit: 1);
    return rows.isEmpty ? null : AralCheckinAnswer.fromMap(rows.first);
  }

  @override
  Future<AralCheckinAnswer> saveAnswer(AralCheckinAnswer answer) async {
    // Same clean-up as the cloud's trigger: trimmed, empty = no answer, a
    // choice letter upper-cased.
    final kind = (await db.query('aral_checkin_items', columns: ['kind'], where: 'id = ?', whereArgs: [answer.itemId]))
        .firstOrNull?['kind'];
    var response = answer.response?.trim();
    if (response != null && response.isEmpty) response = null;
    if (kind == 'choice') response = response?.toUpperCase();

    final now = _now();
    final existing = await _findAnswer(answer.checkinId, answer.itemId);
    if (existing == null) {
      await db.insert('aral_checkin_answers', {
        'id': await nextLocalId(db),
        'checkin_id': answer.checkinId,
        'item_id': answer.itemId,
        'response': response,
        'is_correct': answer.isCorrect ? 1 : 0,
        'created_at': now,
        'updated_at': now,
      });
    } else {
      await db.update('aral_checkin_answers',
          {'response': response, 'is_correct': answer.isCorrect ? 1 : 0, 'updated_at': now},
          where: 'id = ?', whereArgs: [existing.id]);
    }
    return (await _findAnswer(answer.checkinId, answer.itemId))!; // re-read: the trigger scored it
  }

  @override
  Future<void> deleteAnswer(int checkinId, int itemId) async {
    await db.delete('aral_checkin_answers', where: 'checkin_id = ? AND item_id = ?', whereArgs: [checkinId, itemId]);
  }

  @override
  Future<AralCheckinTool> upsertToolWithId(AralCheckinTool tool) async {
    await upsertById(db, 'aral_checkin_tools', toSqliteRow(tool.toMap()));
    return (await findTool(tool.id))!;
  }

  @override
  Future<AralCheckinItem> upsertItemWithId(AralCheckinItem item) async {
    await upsertById(db, 'aral_checkin_items', toSqliteRow(item.toMap()));
    final rows = await db.query('aral_checkin_items', where: 'id = ?', whereArgs: [item.id]);
    return AralCheckinItem.fromMap(rows.first);
  }

  @override
  Future<AralCheckin> upsertCheckinWithId(AralCheckin checkin) async {
    if (checkin.id == null) throw ArgumentError('Cannot upsertCheckinWithId an AralCheckin with no id');
    await mirrorSyncedRow(db, 'aral_checkins', {...toSqliteRow(checkin.toMap()), 'origin': 'cloud'});
    return (await findCheckin(checkin.id!))!;
  }

  @override
  Future<AralCheckinAnswer> upsertAnswerWithId(AralCheckinAnswer answer) async {
    if (answer.id == null) throw ArgumentError('Cannot upsertAnswerWithId an AralCheckinAnswer with no id');
    await mirrorSyncedRow(db, 'aral_checkin_answers', toSqliteRow(answer.toMap()));
    final rows = await db.query('aral_checkin_answers', where: 'id = ?', whereArgs: [answer.id]);
    return AralCheckinAnswer.fromMap(rows.first);
  }
}
