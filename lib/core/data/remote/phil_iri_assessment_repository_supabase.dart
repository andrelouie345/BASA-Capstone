// lib/core/data/remote/phil_iri_assessment_repository_supabase.dart
//
// Same interface as the SQLite repository (the main write path today); used
// online and by the future sync. The database stamps attempt_no,
// administered_by, status times and is_correct; client values for those are
// dropped or ignored. Deletes cascade in Postgres.
import 'package:supabase/supabase.dart';
import '../../models/phil_iri_answer.dart';
import '../../models/phil_iri_assessment.dart';
import '../../models/phil_iri_miscue.dart';
import '../../models/phil_iri_reading.dart';
import '../../models/phil_iri_rubric_score.dart';
import '../../repositories/phil_iri_assessment_repository.dart';

class PhilIriAssessmentRepositorySupabase implements PhilIriAssessmentRepository {
  final SupabaseClient client;
  PhilIriAssessmentRepositorySupabase(this.client);

  static PhilIriAssessment _a(Object? r) => PhilIriAssessment.fromMap(r as Map<String, Object?>);
  static PhilIriReading _r(Object? r) => PhilIriReading.fromMap(r as Map<String, Object?>);
  static PhilIriMiscue _m(Object? r) => PhilIriMiscue.fromMap(r as Map<String, Object?>);
  static PhilIriAnswer _n(Object? r) => PhilIriAnswer.fromMap(r as Map<String, Object?>);
  static PhilIriRubricScore _s(Object? r) => PhilIriRubricScore.fromMap(r as Map<String, Object?>);

  static void _requireOne(List rows, String what) {
    if (rows.isEmpty) throw Exception('No $what changed — check the id or your permissions (or it is finalized)');
  }

  // ---- Sessions ----

  @override
  Future<PhilIriAssessment> insertAssessment(PhilIriAssessment assessment) async {
    final payload = assessment.toMap()
      ..remove('attempt_no')
      ..remove('administered_by')
      ..remove('completed_at')
      ..remove('finalized_at')
      ..remove('thresholds_snapshot');
    final rows = await client.from('phil_iri_assessments').insert(payload).select();
    return _a((rows as List).first);
  }

  @override
  Future<PhilIriAssessment?> findAssessment(int id) async {
    final rows = await client.from('phil_iri_assessments').select().eq('id', id);
    return (rows as List).isEmpty ? null : _a(rows.first);
  }

  @override
  Future<List<PhilIriAssessment>> getBySection(int sectionId, {String? schoolYear, PhilIriRound? round}) async {
    var query = client.from('phil_iri_assessments').select().eq('section_id', sectionId);
    if (schoolYear != null) query = query.eq('school_year', schoolYear);
    if (round != null) query = query.eq('round', round.name);
    final rows = await query
        .order('student_id', ascending: true)
        .order('round', ascending: true)
        .order('attempt_no', ascending: true);
    return (rows as List).map(_a).toList();
  }

  @override
  Future<List<PhilIriAssessment>> getByStudent(int studentId, {String? schoolYear}) async {
    var query = client.from('phil_iri_assessments').select().eq('student_id', studentId);
    if (schoolYear != null) query = query.eq('school_year', schoolYear);
    final rows = await query
        .order('school_year', ascending: true)
        .order('round', ascending: true)
        .order('attempt_no', ascending: true);
    return (rows as List).map(_a).toList();
  }

  @override
  Future<PhilIriAssessment?> getLatestAttempt({
    required int studentId,
    required int sectionId,
    required PhilIriRound round,
    required String schoolYear,
  }) async {
    final rows = await client
        .from('phil_iri_assessments')
        .select()
        .eq('student_id', studentId)
        .eq('section_id', sectionId)
        .eq('round', round.name)
        .eq('school_year', schoolYear)
        .order('attempt_no', ascending: false)
        .limit(1);
    return (rows as List).isEmpty ? null : _a(rows.first);
  }

  @override
  Future<PhilIriAssessment> setStatus(int assessmentId, PhilIriStatus status) async {
    if (status == PhilIriStatus.finalized) {
      throw ArgumentError('Use finalize() to finalize a Phil-IRI assessment');
    }
    final rows = await client
        .from('phil_iri_assessments')
        .update({'status': status.value})
        .eq('id', assessmentId)
        .select();
    _requireOne(rows as List, 'Phil-IRI assessment');
    return _a(rows.first);
  }

  @override
  Future<PhilIriAssessment> finalize({
    required int assessmentId,
    required Map<String, Object?> thresholdsSnapshot,
    required List<PhilIriReading> readingResults,
  }) async {
    // No transaction over PostgREST: if the status update fails, the readings
    // keep result values while the session stays completed; harmless, since
    // results are computed live until finalization and the next finalize
    // overwrites them.
    for (final r in readingResults) {
      if (r.id == null) throw ArgumentError('finalize needs reading ids');
      final all = r.toMap();
      final results = {for (final c in PhilIriReading.resultColumns) c: all[c]};
      final rows = await client
          .from('phil_iri_readings')
          .update(results)
          .eq('id', r.id!)
          .eq('assessment_id', assessmentId)
          .select('id');
      _requireOne(rows as List, 'Phil-IRI reading ${r.id}');
    }
    final rows = await client
        .from('phil_iri_assessments')
        .update({'status': PhilIriStatus.finalized.value, 'thresholds_snapshot': thresholdsSnapshot})
        .eq('id', assessmentId)
        .select();
    _requireOne(rows as List, 'Phil-IRI assessment');
    return _a(rows.first);
  }

  @override
  Future<void> deleteAssessment(int assessmentId) async {
    final rows = await client.from('phil_iri_assessments').delete().eq('id', assessmentId).select('id');
    if ((rows as List).isEmpty) {
      throw Exception('No Phil-IRI assessment discarded — only an in-progress one you can write can be ("$assessmentId")');
    }
  }

  // ---- Readings ----

  @override
  Future<PhilIriReading> insertReading(PhilIriReading reading) async {
    final payload = reading.toMap();
    for (final c in PhilIriReading.resultColumns) {
      payload.remove(c);
    }
    final rows = await client.from('phil_iri_readings').insert(payload).select();
    return _r((rows as List).first);
  }

  @override
  Future<PhilIriReading> updateReading(PhilIriReading reading) async {
    if (reading.id == null) throw ArgumentError('Cannot update a PhilIriReading with no id');
    final payload = reading.toMap()..remove('id');
    for (final c in PhilIriReading.resultColumns) {
      payload.remove(c);
    }
    final rows = await client.from('phil_iri_readings').update(payload).eq('id', reading.id!).select();
    _requireOne(rows as List, 'Phil-IRI reading');
    return _r(rows.first);
  }

  @override
  Future<void> deleteReading(int readingId) async {
    final rows = await client.from('phil_iri_readings').delete().eq('id', readingId).select('id');
    _requireOne(rows as List, 'Phil-IRI reading');
  }

  @override
  Future<List<PhilIriReading>> getReadings(int assessmentId) async {
    final rows = await client
        .from('phil_iri_readings')
        .select()
        .eq('assessment_id', assessmentId)
        .order('sequence_no', ascending: true);
    return (rows as List).map(_r).toList();
  }

  // ---- Miscues ----

  @override
  Future<PhilIriMiscue> insertMiscue(PhilIriMiscue miscue) async {
    final rows = await client.from('phil_iri_miscues').insert(miscue.toMap()).select();
    return _m((rows as List).first);
  }

  @override
  Future<PhilIriMiscue> updateMiscue(PhilIriMiscue miscue) async {
    if (miscue.id == null) throw ArgumentError('Cannot update a PhilIriMiscue with no id');
    final rows = await client
        .from('phil_iri_miscues')
        .update(miscue.toMap()..remove('id'))
        .eq('id', miscue.id!)
        .select();
    _requireOne(rows as List, 'Phil-IRI miscue');
    return _m(rows.first);
  }

  @override
  Future<void> deleteMiscue(int miscueId) async {
    final rows = await client.from('phil_iri_miscues').delete().eq('id', miscueId).select('id');
    _requireOne(rows as List, 'Phil-IRI miscue');
  }

  @override
  Future<List<PhilIriMiscue>> getMiscues(int readingId) async {
    final rows = await client
        .from('phil_iri_miscues')
        .select()
        .eq('reading_id', readingId)
        .order('word_index', ascending: true)
        .order('id', ascending: true);
    return (rows as List).map(_m).toList();
  }

  // ---- Answers ----

  @override
  Future<PhilIriAnswer> saveAnswer(PhilIriAnswer answer) async {
    final payload = answer.toMap()
      ..remove('id')
      ..remove('is_correct');
    final rows = await client
        .from('phil_iri_answers')
        .upsert(payload, onConflict: 'reading_id,question_id')
        .select();
    return _n((rows as List).first);
  }

  @override
  Future<void> deleteAnswer(int answerId) async {
    final rows = await client.from('phil_iri_answers').delete().eq('id', answerId).select('id');
    _requireOne(rows as List, 'Phil-IRI answer');
  }

  @override
  Future<List<PhilIriAnswer>> getAnswers(int readingId) async {
    final rows = await client
        .from('phil_iri_answers')
        .select()
        .eq('reading_id', readingId)
        .order('question_id', ascending: true);
    return (rows as List).map(_n).toList();
  }

  // ---- Rubric scores ----

  @override
  Future<PhilIriRubricScore> saveRubricScore(PhilIriRubricScore score) async {
    final rows = await client
        .from('phil_iri_rubric_scores')
        .upsert(score.toMap()..remove('id'), onConflict: 'assessment_id,criterion_id')
        .select();
    return _s((rows as List).first);
  }

  @override
  Future<List<PhilIriRubricScore>> getRubricScores(int assessmentId) async {
    final rows = await client
        .from('phil_iri_rubric_scores')
        .select()
        .eq('assessment_id', assessmentId)
        .order('criterion_id', ascending: true);
    return (rows as List).map(_s).toList();
  }

  @override
  Future<PhilIriAssessment> upsertAssessmentWithId(PhilIriAssessment assessment) async {
    throw UnimplementedError('upsertAssessmentWithId is a local-mirroring operation — not meaningful against Supabase');
  }
}
