// lib/core/data/remote/aral_checkin_repository_supabase.dart
//
// Same interface as the SQLite repository (the main write path today); used
// online and by the future sync. The database numbers attempts, scores choice
// items and stamps created_by and the times.
import 'package:supabase/supabase.dart';
import '../../models/aral_checkin.dart';
import '../../models/aral_enrollment.dart';
import '../../repositories/aral_checkin_repository.dart';

class AralCheckinRepositorySupabase implements AralCheckinRepository {
  final SupabaseClient client;
  AralCheckinRepositorySupabase(this.client);

  static AralCheckinTool _t(Object? r) => AralCheckinTool.fromMap(r as Map<String, Object?>);
  static AralCheckin _c(Object? r) => AralCheckin.fromMap(r as Map<String, Object?>);
  static AralCheckinAnswer _a(Object? r) => AralCheckinAnswer.fromMap(r as Map<String, Object?>);

  @override
  Future<List<AralCheckinTool>> tools() async {
    final rows = await client
        .from('aral_checkin_tools')
        .select()
        .eq('is_active', true)
        .order('key_stage')
        .order('track')
        .order('checkpoint');
    return (rows as List).map(_t).toList();
  }

  @override
  Future<AralCheckinTool?> findTool(int id) async {
    final rows = await client.from('aral_checkin_tools').select().eq('id', id);
    return (rows as List).isEmpty ? null : _t(rows.first);
  }

  @override
  Future<AralCheckinTool?> toolFor(AralKeyStage keyStage, AralTrack track, int checkpoint) async {
    final rows = await client
        .from('aral_checkin_tools')
        .select()
        .eq('key_stage', keyStage.name)
        .eq('track', track.name)
        .eq('checkpoint', checkpoint)
        .eq('is_active', true);
    return (rows as List).isEmpty ? null : _t(rows.first);
  }

  @override
  Future<List<AralCheckinItem>> items(int toolId) async {
    final rows = await client.from('aral_checkin_items').select().eq('tool_id', toolId).order('item_no');
    return (rows as List).map((r) => AralCheckinItem.fromMap(r as Map<String, Object?>)).toList();
  }

  @override
  Future<List<AralCheckin>> checkins(int enrollmentId) async {
    final rows = await client
        .from('aral_checkins')
        .select()
        .eq('enrollment_id', enrollmentId)
        .order('tool_id')
        .order('attempt_no');
    return (rows as List).map(_c).toList();
  }

  @override
  Future<AralCheckin?> findCheckin(int id) async {
    final rows = await client.from('aral_checkins').select().eq('id', id);
    return (rows as List).isEmpty ? null : _c(rows.first);
  }

  @override
  Future<AralCheckin> insertCheckin(AralCheckin checkin) async {
    final payload = checkin.toMap()
      ..remove('id')
      ..remove('attempt_no')
      ..remove('created_by')
      ..remove('created_at')
      ..remove('updated_at');
    final rows = await client.from('aral_checkins').insert(payload).select();
    return _c((rows as List).first);
  }

  @override
  Future<AralCheckin> updateCheckin(AralCheckin checkin) async {
    if (checkin.id == null) throw ArgumentError('updateCheckin needs an id');
    final rows = await client
        .from('aral_checkins')
        .update({'taken_on': checkin.takenOn, 'notes': checkin.notes})
        .eq('id', checkin.id!)
        .select();
    if ((rows as List).isEmpty) throw Exception('No check-in changed — check the id or your permissions');
    return _c(rows.first);
  }

  @override
  Future<void> deleteCheckin(int id) async {
    final rows = await client.from('aral_checkins').delete().eq('id', id).select();
    if ((rows as List).isEmpty) throw Exception('No check-in deleted — check the id or your permissions');
  }

  @override
  Future<List<AralCheckinAnswer>> answers(int checkinId) async {
    final rows = await client.from('aral_checkin_answers').select().eq('checkin_id', checkinId);
    return (rows as List).map(_a).toList();
  }

  @override
  Future<AralCheckinAnswer> saveAnswer(AralCheckinAnswer answer) async {
    final rows = await client
        .from('aral_checkin_answers')
        .upsert({
          'checkin_id': answer.checkinId,
          'item_id': answer.itemId,
          'response': answer.response,
          'is_correct': answer.isCorrect,
        }, onConflict: 'checkin_id,item_id')
        .select();
    if ((rows as List).isEmpty) throw Exception('Answer not saved — check your permissions');
    return _a(rows.first);
  }

  @override
  Future<void> deleteAnswer(int checkinId, int itemId) async {
    await client.from('aral_checkin_answers').delete().eq('checkin_id', checkinId).eq('item_id', itemId);
  }

  @override
  Future<AralCheckinTool> upsertToolWithId(AralCheckinTool tool) =>
      throw UnimplementedError('upsertToolWithId is for local mirroring only');

  @override
  Future<AralCheckinItem> upsertItemWithId(AralCheckinItem item) =>
      throw UnimplementedError('upsertItemWithId is for local mirroring only');

  @override
  Future<AralCheckin> upsertCheckinWithId(AralCheckin checkin) =>
      throw UnimplementedError('upsertCheckinWithId is for local mirroring only');

  @override
  Future<AralCheckinAnswer> upsertAnswerWithId(AralCheckinAnswer answer) =>
      throw UnimplementedError('upsertAnswerWithId is for local mirroring only');
}
