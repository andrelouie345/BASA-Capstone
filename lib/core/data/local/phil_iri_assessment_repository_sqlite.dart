// lib/core/data/local/phil_iri_assessment_repository_sqlite.dart
//
// The main write path for Phil-IRI sessions (offline-first, like CRLA). The
// local triggers (phil_iri_local_schema.dart) enforce the cloud's rules for
// sessions entered on this device. Local foreign keys are off, so deletes
// remove children explicitly.
import 'dart:convert';
import 'package:sqflite_common/sqflite.dart';
import 'mirror_write.dart';
import 'sqlite_values.dart';
import '../../models/phil_iri_answer.dart';
import '../../models/phil_iri_assessment.dart';
import '../../models/phil_iri_miscue.dart';
import '../../models/phil_iri_reading.dart';
import '../../models/phil_iri_rubric_score.dart';
import '../../repositories/phil_iri_assessment_repository.dart';

class PhilIriAssessmentRepositorySqlite implements PhilIriAssessmentRepository {
  final Database db;
  PhilIriAssessmentRepositorySqlite(this.db);

  static String _now() => DateTime.now().toUtc().toIso8601String();

  // ---- Sessions ----

  @override
  Future<PhilIriAssessment> insertAssessment(PhilIriAssessment assessment) async {
    // attempt_no left out (default 0): the AFTER INSERT trigger assigns it.
    final row = toSqliteRow(assessment.toMap())..remove('attempt_no');
    final id = await db.insert('phil_iri_assessments', row);
    final stored = await findAssessment(id);
    if (stored == null) throw StateError('phil_iri_assessments row $id vanished right after insert');
    return stored;
  }

  @override
  Future<PhilIriAssessment?> findAssessment(int id) async {
    final rows = await db.query('phil_iri_assessments', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : PhilIriAssessment.fromMap(rows.first);
  }

  @override
  Future<List<PhilIriAssessment>> getBySection(int sectionId, {String? schoolYear, PhilIriRound? round}) async {
    final where = ['section_id = ?', if (schoolYear != null) 'school_year = ?', if (round != null) 'round = ?'];
    final rows = await db.query(
      'phil_iri_assessments',
      where: where.join(' AND '),
      whereArgs: [sectionId, ?schoolYear, if (round != null) round.name],
      orderBy: 'student_id, round, attempt_no',
    );
    return rows.map(PhilIriAssessment.fromMap).toList();
  }

  @override
  Future<List<PhilIriAssessment>> getByStudent(int studentId, {String? schoolYear}) async {
    final rows = await db.query(
      'phil_iri_assessments',
      where: schoolYear == null ? 'student_id = ?' : 'student_id = ? AND school_year = ?',
      whereArgs: schoolYear == null ? [studentId] : [studentId, schoolYear],
      orderBy: 'school_year, round, attempt_no',
    );
    return rows.map(PhilIriAssessment.fromMap).toList();
  }

  @override
  Future<PhilIriAssessment?> getLatestAttempt({
    required int studentId,
    required int sectionId,
    required PhilIriRound round,
    required String schoolYear,
  }) async {
    final rows = await db.query(
      'phil_iri_assessments',
      where: 'student_id = ? AND section_id = ? AND round = ? AND school_year = ?',
      whereArgs: [studentId, sectionId, round.name, schoolYear],
      orderBy: 'attempt_no DESC',
      limit: 1,
    );
    return rows.isEmpty ? null : PhilIriAssessment.fromMap(rows.first);
  }

  @override
  Future<PhilIriAssessment> setStatus(int assessmentId, PhilIriStatus status) async {
    if (status == PhilIriStatus.finalized) {
      throw ArgumentError('Use finalize() to finalize a Phil-IRI assessment');
    }
    // The repository stamps the times locally; the cloud re-stamps on upload.
    final values = <String, Object?>{
      'status': status.value,
      'thresholds_snapshot': null,
      'finalized_at': null,
    };
    final current = await findAssessment(assessmentId);
    if (current == null) throw StateError('No Phil-IRI assessment $assessmentId');
    if (status == PhilIriStatus.inProgress) {
      values['completed_at'] = null;
    } else if (current.status == PhilIriStatus.inProgress) {
      values['completed_at'] = _now();
    }
    await db.update('phil_iri_assessments', values, where: 'id = ?', whereArgs: [assessmentId]);
    return (await findAssessment(assessmentId))!;
  }

  @override
  Future<PhilIriAssessment> finalize({
    required int assessmentId,
    required Map<String, Object?> thresholdsSnapshot,
    required List<PhilIriReading> readingResults,
  }) async {
    await db.transaction((txn) async {
      for (final r in readingResults) {
        if (r.id == null) throw ArgumentError('finalize needs reading ids');
        final all = toSqliteRow(r.toMap());
        final results = {for (final c in PhilIriReading.resultColumns) c: all[c]};
        final n = await txn.update('phil_iri_readings', results,
            where: 'id = ? AND assessment_id = ?', whereArgs: [r.id, assessmentId]);
        if (n == 0) throw StateError('Reading ${r.id} is not part of assessment $assessmentId');
      }
      await txn.update(
        'phil_iri_assessments',
        {'status': PhilIriStatus.finalized.value, 'finalized_at': _now(), 'thresholds_snapshot': jsonEncode(thresholdsSnapshot)},
        where: 'id = ?',
        whereArgs: [assessmentId],
      );
    });
    return (await findAssessment(assessmentId))!;
  }

  @override
  Future<void> deleteAssessment(int assessmentId) async {
    final current = await findAssessment(assessmentId);
    if (current == null) throw StateError('No Phil-IRI assessment $assessmentId');
    if (current.status != PhilIriStatus.inProgress) {
      throw StateError('Only an in-progress Phil-IRI assessment can be discarded (this one is ${current.status.value})');
    }
    await db.transaction((txn) async {
      const readings = 'SELECT id FROM phil_iri_readings WHERE assessment_id = ?';
      await txn.delete('phil_iri_answers', where: 'reading_id IN ($readings)', whereArgs: [assessmentId]);
      await txn.delete('phil_iri_miscues', where: 'reading_id IN ($readings)', whereArgs: [assessmentId]);
      await txn.delete('phil_iri_readings', where: 'assessment_id = ?', whereArgs: [assessmentId]);
      await txn.delete('phil_iri_rubric_scores', where: 'assessment_id = ?', whereArgs: [assessmentId]);
      await txn.delete('phil_iri_assessments', where: 'id = ?', whereArgs: [assessmentId]);
    });
  }

  // ---- Readings ----

  @override
  Future<PhilIriReading> insertReading(PhilIriReading reading) async {
    final row = toSqliteRow(reading.toMap());
    for (final c in PhilIriReading.resultColumns) {
      row.remove(c); // results are written at finalization only
    }
    final id = await db.insert('phil_iri_readings', row);
    return (await _reading(id))!;
  }

  @override
  Future<PhilIriReading> updateReading(PhilIriReading reading) async {
    if (reading.id == null) throw ArgumentError('Cannot update a PhilIriReading with no id');
    final row = toSqliteRow(reading.toMap())..remove('id');
    for (final c in PhilIriReading.resultColumns) {
      row.remove(c);
    }
    final n = await db.update('phil_iri_readings', row, where: 'id = ?', whereArgs: [reading.id]);
    if (n == 0) throw StateError('No Phil-IRI reading ${reading.id}');
    return (await _reading(reading.id!))!;
  }

  @override
  Future<void> deleteReading(int readingId) async {
    await db.transaction((txn) async {
      final rows = await txn.rawQuery('''
        SELECT a.status FROM phil_iri_readings r JOIN phil_iri_assessments a ON a.id = r.assessment_id
        WHERE r.id = ?''', [readingId]);
      if (rows.isEmpty) throw StateError('No Phil-IRI reading $readingId');
      if (rows.first['status'] == PhilIriStatus.finalized.value) {
        throw StateError('This Phil-IRI assessment is finalized and cannot be changed');
      }
      await txn.delete('phil_iri_answers', where: 'reading_id = ?', whereArgs: [readingId]);
      await txn.delete('phil_iri_miscues', where: 'reading_id = ?', whereArgs: [readingId]);
      await txn.delete('phil_iri_readings', where: 'id = ?', whereArgs: [readingId]);
    });
  }

  @override
  Future<List<PhilIriReading>> getReadings(int assessmentId) async {
    final rows = await db.query('phil_iri_readings',
        where: 'assessment_id = ?', whereArgs: [assessmentId], orderBy: 'sequence_no');
    return rows.map(PhilIriReading.fromMap).toList();
  }

  Future<PhilIriReading?> _reading(int id) async {
    final rows = await db.query('phil_iri_readings', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : PhilIriReading.fromMap(rows.first);
  }

  // ---- Miscues ----

  @override
  Future<PhilIriMiscue> insertMiscue(PhilIriMiscue miscue) async {
    final id = await db.insert('phil_iri_miscues', toSqliteRow(miscue.toMap()));
    return (await _miscue(id))!;
  }

  @override
  Future<PhilIriMiscue> updateMiscue(PhilIriMiscue miscue) async {
    if (miscue.id == null) throw ArgumentError('Cannot update a PhilIriMiscue with no id');
    final n = await db.update('phil_iri_miscues', toSqliteRow(miscue.toMap())..remove('id'),
        where: 'id = ?', whereArgs: [miscue.id]);
    if (n == 0) throw StateError('No Phil-IRI miscue ${miscue.id}');
    return (await _miscue(miscue.id!))!;
  }

  @override
  Future<void> deleteMiscue(int miscueId) async {
    await _guardNotFinalized('''
      SELECT a.status FROM phil_iri_miscues m JOIN phil_iri_readings r ON r.id = m.reading_id
      JOIN phil_iri_assessments a ON a.id = r.assessment_id WHERE m.id = ?''', miscueId, 'miscue');
    await db.delete('phil_iri_miscues', where: 'id = ?', whereArgs: [miscueId]);
  }

  @override
  Future<List<PhilIriMiscue>> getMiscues(int readingId) async {
    final rows = await db.query('phil_iri_miscues',
        where: 'reading_id = ?', whereArgs: [readingId], orderBy: 'word_index, id');
    return rows.map(PhilIriMiscue.fromMap).toList();
  }

  Future<PhilIriMiscue?> _miscue(int id) async {
    final rows = await db.query('phil_iri_miscues', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : PhilIriMiscue.fromMap(rows.first);
  }

  // ---- Answers ----

  @override
  Future<PhilIriAnswer> saveAnswer(PhilIriAnswer answer) async {
    final row = toSqliteRow(answer.toMap())..remove('id');
    final existing = await db.query('phil_iri_answers',
        columns: ['id'], where: 'reading_id = ? AND question_id = ?', whereArgs: [answer.readingId, answer.questionId]);
    final int id;
    if (existing.isEmpty) {
      id = await db.insert('phil_iri_answers', row);
    } else {
      id = existing.first['id'] as int;
      await db.update('phil_iri_answers', row, where: 'id = ?', whereArgs: [id]);
    }
    final rows = await db.query('phil_iri_answers', where: 'id = ?', whereArgs: [id]);
    return PhilIriAnswer.fromMap(rows.first); // is_correct as the trigger computed it
  }

  @override
  Future<void> deleteAnswer(int answerId) async {
    await _guardNotFinalized('''
      SELECT a.status FROM phil_iri_answers n JOIN phil_iri_readings r ON r.id = n.reading_id
      JOIN phil_iri_assessments a ON a.id = r.assessment_id WHERE n.id = ?''', answerId, 'answer');
    await db.delete('phil_iri_answers', where: 'id = ?', whereArgs: [answerId]);
  }

  @override
  Future<List<PhilIriAnswer>> getAnswers(int readingId) async {
    final rows = await db.query('phil_iri_answers',
        where: 'reading_id = ?', whereArgs: [readingId], orderBy: 'question_id');
    return rows.map(PhilIriAnswer.fromMap).toList();
  }

  // ---- Rubric scores ----

  @override
  Future<PhilIriRubricScore> saveRubricScore(PhilIriRubricScore score) async {
    final existing = await db.query('phil_iri_rubric_scores',
        columns: ['id'], where: 'assessment_id = ? AND criterion_id = ?',
        whereArgs: [score.assessmentId, score.criterionId]);
    final int id;
    if (existing.isEmpty) {
      id = await db.insert('phil_iri_rubric_scores', score.toMap()..remove('id'));
    } else {
      id = existing.first['id'] as int;
      await db.update('phil_iri_rubric_scores', {'score': score.score}, where: 'id = ?', whereArgs: [id]);
    }
    final rows = await db.query('phil_iri_rubric_scores', where: 'id = ?', whereArgs: [id]);
    return PhilIriRubricScore.fromMap(rows.first);
  }

  @override
  Future<List<PhilIriRubricScore>> getRubricScores(int assessmentId) async {
    final rows = await db.query('phil_iri_rubric_scores',
        where: 'assessment_id = ?', whereArgs: [assessmentId], orderBy: 'criterion_id');
    return rows.map(PhilIriRubricScore.fromMap).toList();
  }

  @override
  Future<PhilIriAssessment> upsertAssessmentWithId(PhilIriAssessment assessment) async {
    if (assessment.id == null) throw ArgumentError('Cannot upsertAssessmentWithId a PhilIriAssessment with no id');
    if (assessment.attemptNo == null || assessment.attemptNo == 0) {
      throw ArgumentError('upsertAssessmentWithId requires the real attemptNo (got ${assessment.attemptNo})');
    }
    await upsertById(db, 'phil_iri_assessments', {...toSqliteRow(assessment.toMap()), 'origin': 'cloud'});
    return (await findAssessment(assessment.id!))!;
  }

  /// Deletes aren't guarded by triggers locally (pull-cloud clears tables),
  /// so the repository refuses to delete under a finalized session itself.
  Future<void> _guardNotFinalized(String statusSql, int id, String what) async {
    final rows = await db.rawQuery(statusSql, [id]);
    if (rows.isEmpty) throw StateError('No Phil-IRI $what $id');
    if (rows.first['status'] == PhilIriStatus.finalized.value) {
      throw StateError('This Phil-IRI assessment is finalized and cannot be changed');
    }
  }
}
