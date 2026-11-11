// Phil-IRI import, Task 8: the local import writer (spec
// docs/superpowers/specs/2026-11-09-phil-iri-import-design.md, import()):
// one device transaction per learner, sessions created in progress with
// import_source then completed, the GST result, the section's lock row.
import 'dart:io';

import 'package:basa_capstone/core/data/local/phil_iri_import_writer_sqlite.dart';
import 'package:basa_capstone/core/data/local/sync_upload_local_sqlite.dart';
import 'package:basa_capstone/core/models/phil_iri_answer.dart';
import 'package:basa_capstone/core/models/phil_iri_assessment.dart';
import 'package:basa_capstone/core/models/phil_iri_gst_result.dart';
import 'package:basa_capstone/core/models/phil_iri_miscue.dart';
import 'package:basa_capstone/core/models/phil_iri_reading.dart';
import 'package:basa_capstone/core/models/phil_iri_workbook_import.dart';
import 'package:basa_capstone/core/repositories/phil_iri_import_writer.dart';
import 'package:basa_capstone/core/wiring/app_context.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _year = '2026-2027';

void main() {
  late Database db;
  late PhilIriImportWriter writer;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final ctx = await AppContext.open(dataDir: Directory.systemTemp.createTempSync('basa_import_writer_').path);
    db = ctx.localDb;
    writer = PhilIriImportWriterSqlite(db);
    await db.insert('schools', {'id': 1, 'school_id': 'ZZ08', 'school_name': 'ZZ writer'});
    await db.insert('sections', {'id': 70, 'school_id': 1, 'school_year': _year, 'grade_level': '7', 'section_name': 'S70'});
    await db.insert('sections', {'id': 71, 'school_id': 1, 'school_year': _year, 'grade_level': '7', 'section_name': 'S71'});
    for (final s in [701, 702, 703, 704]) {
      await db.insert('students', {'id': s, 'lrn': '9999999$s', 'last_name': 'L$s', 'first_name': 'F', 'school_id': 1});
      await db.insert('enrollments', {'student_id': s, 'section_id': 70, 'school_year': _year, 'status': 'active'});
    }
    await db.insert('phil_iri_collections', {'id': 1, 'name': 'Graded writer', 'is_grade_leveled': 1});
    Future<void> passage(int id, int level) => db.insert('phil_iri_passages', {
          'id': id, 'collection_id': 1, 'level': level, 'title': 'P$id',
          'body': List.filled(100, 'word').join(' '), 'word_count': 100, 'is_active': 1,
        });
    await passage(207, 7);
    await passage(217, 7);
    await passage(206, 6); // lower grade: the own-grade trigger refuses it
    for (final p in [207, 217]) {
      for (var q = 1; q <= 5; q++) {
        await db.insert('phil_iri_questions',
            {'id': p * 10 + q, 'passage_id': p, 'question_no': q, 'prompt': 'Q$q', 'choices': '["a","b"]', 'answer_key': 'a'});
      }
    }
  });

  PhilIriAssessment session(int student, PhilIriRound round, {PhilIriImportSource source = PhilIriImportSource.workbook}) =>
      PhilIriAssessment(
        studentId: student, schoolId: 1, sectionId: 70, schoolYear: _year,
        round: round, assessedAt: '2026-07-01', importSource: source,
      );

  // reading_id / assessment_id below are placeholders: the writer links them.
  PhilIriImportedSession imported(
    PhilIriAssessment a,
    PhilIriReading r, {
    List<PhilIriMiscue> miscues = const [],
    List<PhilIriAnswer> answers = const [],
  }) =>
      PhilIriImportedSession(assessment: a, reading: r, miscues: miscues, answers: answers);

  PhilIriMiscue miscue(PhilIriMiscueType t, {bool self = false}) =>
      PhilIriMiscue(readingId: 0, type: t, selfCorrected: self);

  Future<List<Map<String, Object?>>> rows(String table, String where, List<Object?> args) =>
      db.query(table, where: where, whereArgs: args);

  test('writes a learner: negative ids, completed, all in the next upload package', () async {
    final ids = await writer.writeLearner(
      sessions: [
        imported(
          session(701, PhilIriRound.bosy),
          PhilIriReading(assessmentId: 0, sequenceNo: 1, passageId: 207, readingSeconds: 95, importedCorrect: 4),
          miscues: [miscue(PhilIriMiscueType.omission), miscue(PhilIriMiscueType.substitution, self: true)],
        ),
        imported(
          session(701, PhilIriRound.mosy1),
          PhilIriReading(
              assessmentId: 0, sequenceNo: 1, passageId: 217, method: PhilIriReadingMethod.oneMinute, wordsRead: 80),
        ),
      ],
      gst: PhilIriGstResult(
          studentId: 701, schoolId: 1, sectionId: 70, schoolYear: _year, maxScore: 40, totalScore: 22, takenAt: '2026-06-20'),
    );
    expect(ids, hasLength(2));
    expect(ids.every((id) => id < 0), isTrue);

    final sessions = await rows('phil_iri_assessments', 'student_id = ?', [701]);
    expect(sessions, hasLength(2));
    for (final s in sessions) {
      expect(s['id'] as int, isNegative);
      expect(s['row_version'], isNull);
      expect(s['status'], 'completed');
      expect(s['completed_at'], isNotNull);
      expect(s['import_source'], 'workbook');
      expect(s['attempt_no'], 1);
    }
    final readings = await rows('phil_iri_readings', 'assessment_id IN (${ids.join(',')})', []);
    expect(readings, hasLength(2));
    final bosy = readings.firstWhere((r) => r['passage_id'] == 207);
    expect(bosy['imported_correct'], 4);
    expect(bosy['profile'], isNull, reason: 'results are written at finalization only');
    final miscues = await rows('phil_iri_miscues', 'reading_id = ?', [bosy['id']]);
    expect(miscues, hasLength(2));
    expect(miscues.every((m) => m['word_index'] == null && (m['id'] as int) < 0), isTrue);
    expect(miscues.where((m) => m['self_corrected'] == 1), hasLength(1));
    final gst = await rows('phil_iri_gst_results', 'student_id = ?', [701]);
    expect(gst.single['id'] as int, isNegative);
    expect(gst.single['row_version'], isNull);

    final package = await SyncUploadLocalSqlite(db).buildPackage(release: 'test');
    Set<Object> keys(String table) =>
        package.records.where((r) => r.table == table && r.op == 'insert').map((r) => r.key).toSet();
    expect(keys('phil_iri_assessments'), containsAll(ids));
    expect(keys('phil_iri_readings'), containsAll(readings.map((r) => r['id'])));
    expect(keys('phil_iri_miscues'), containsAll(miscues.map((m) => m['id'])));
    expect(keys('phil_iri_gst_results'), contains(gst.single['id']));
  });

  test('scoresheet session: answers stored, is_correct from the key', () async {
    final ids = await writer.writeLearner(sessions: [
      imported(
        session(702, PhilIriRound.bosy, source: PhilIriImportSource.scoresheet),
        PhilIriReading(assessmentId: 0, sequenceNo: 1, passageId: 217, readingSeconds: 100),
        answers: [
          PhilIriAnswer(readingId: 0, questionId: 2171, chosen: 'a', isCorrect: false),
          PhilIriAnswer(readingId: 0, questionId: 2172, chosen: 'b', isCorrect: true),
          PhilIriAnswer(readingId: 0, questionId: 2173, isCorrect: false), // not answered
        ],
      ),
    ]);
    final reading = (await rows('phil_iri_readings', 'assessment_id = ?', [ids.single])).single;
    final answers = await db.query('phil_iri_answers', where: 'reading_id = ?', whereArgs: [reading['id']], orderBy: 'question_id');
    expect(answers.map((a) => a['is_correct']), [1, 0, 0]);
    expect(answers[2]['chosen'], isNull);
  });

  test('writes an Untitled and a comprehension-only reading', () async {
    final ids = await writer.writeLearner(sessions: [
      imported(
        session(703, PhilIriRound.bosy),
        PhilIriReading(
            assessmentId: 0, sequenceNo: 1, passageId: null, readingSeconds: 80,
            importedWordCount: 120, importedCorrect: 6, importedTotal: 8),
        miscues: [miscue(PhilIriMiscueType.omission)],
      ),
      imported(
        session(703, PhilIriRound.mosy1),
        PhilIriReading(assessmentId: 0, sequenceNo: 1, passageId: 207, importedCorrect: 3),
      ),
      imported(
        session(703, PhilIriRound.mosy2),
        PhilIriReading(assessmentId: 0, sequenceNo: 1, passageId: null, importedCorrect: 5, importedTotal: 8),
      ),
    ]);
    expect(ids, hasLength(3));
    Future<Map<String, Object?>> readingOf(int sessionId) async =>
        (await rows('phil_iri_readings', 'assessment_id = ?', [sessionId])).single;

    final untitled = await readingOf(ids[0]);
    expect(untitled['passage_id'], isNull);
    expect(untitled['imported_word_count'], 120);
    expect([untitled['imported_correct'], untitled['imported_total']], [6, 8]);
    expect(await rows('phil_iri_miscues', 'reading_id = ?', [untitled['id']]), hasLength(1));

    final compOnly = await readingOf(ids[1]);
    expect([compOnly['reading_seconds'], compOnly['words_read'], compOnly['imported_correct']], [null, null, 3]);

    final untitledCompOnly = await readingOf(ids[2]);
    expect(untitledCompOnly['passage_id'], isNull);
    expect([untitledCompOnly['reading_seconds'], untitledCompOnly['imported_word_count']], [null, null]);
    expect([untitledCompOnly['imported_correct'], untitledCompOnly['imported_total']], [5, 8]);

    final statuses = await rows('phil_iri_assessments', 'student_id = ?', [703]);
    expect(statuses.map((s) => s['status']).toSet(), {'completed'});
  });

  test('a failing session rolls the learner back', () async {
    await expectLater(
      writer.writeLearner(
        sessions: [
          imported(session(704, PhilIriRound.bosy),
              PhilIriReading(assessmentId: 0, sequenceNo: 1, passageId: 207, readingSeconds: 90, importedCorrect: 2),
              miscues: [miscue(PhilIriMiscueType.omission)]),
          imported(session(704, PhilIriRound.mosy1), // Grade 6 passage for a Grade 7 learner
              PhilIriReading(assessmentId: 0, sequenceNo: 1, passageId: 206, readingSeconds: 90)),
        ],
        gst: PhilIriGstResult(
            studentId: 704, schoolId: 1, sectionId: 70, schoolYear: _year, maxScore: 40, totalScore: 20, takenAt: '2026-06-20'),
        lock: PhilIriWorkbookImport(schoolId: 1, sectionId: 70, schoolYear: _year),
      ),
      throwsA(isA<DatabaseException>().having((e) => e.toString(), 'message', contains('their own grade'))),
    );
    expect(await rows('phil_iri_assessments', 'student_id = ?', [704]), isEmpty);
    expect(await rows('phil_iri_gst_results', 'student_id = ?', [704]), isEmpty);
    expect(await db.rawQuery(
        'SELECT 1 FROM phil_iri_readings r LEFT JOIN phil_iri_assessments a ON a.id = r.assessment_id WHERE a.id IS NULL'),
        isEmpty, reason: 'no orphan reading or miscue left behind');
    expect(await db.rawQuery(
        'SELECT 1 FROM phil_iri_miscues m LEFT JOIN phil_iri_readings r ON r.id = m.reading_id WHERE r.id IS NULL'),
        isEmpty);
    expect(await writer.isLocked(70, _year), isFalse, reason: 'the lock rolls back with the learner');
  });

  test('lock row written once and isLocked sees it', () async {
    expect(await writer.isLocked(71, _year), isFalse);
    await writer.writeLearner(sessions: const [], lock: PhilIriWorkbookImport(schoolId: 1, sectionId: 71, schoolYear: _year));
    expect(await writer.isLocked(71, _year), isTrue);
    expect(await writer.isLocked(71, '2027-2028'), isFalse);
    final lock = (await rows('phil_iri_workbook_imports', 'section_id = ?', [71])).single;
    expect(lock['id'] as int, isNegative);
    final package = await SyncUploadLocalSqlite(db).buildPackage(release: 'test');
    expect(package.records.where((r) => r.table == 'phil_iri_workbook_imports').map((r) => r.key), contains(lock['id']));
    await expectLater(
      writer.writeLearner(sessions: const [], lock: PhilIriWorkbookImport(schoolId: 1, sectionId: 71, schoolYear: _year)),
      throwsA(isA<DatabaseException>()),
    );
    expect(await rows('phil_iri_workbook_imports', 'section_id = ?', [71]), hasLength(1));
  });
}
