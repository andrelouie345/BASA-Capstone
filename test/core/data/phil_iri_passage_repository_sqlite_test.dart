// Dropping the local copy of a passage or question (command pass finding F11):
// "sync them" only while unsent rows (negative ids) use it; rows that are
// already on the server get UsedOnServerError (the cloud refuses too).
import 'dart:io';

import 'package:basa_capstone/core/data/local/local_database.dart';
import 'package:basa_capstone/core/data/local/phil_iri_passage_repository_sqlite.dart';
import 'package:basa_capstone/core/models/phil_iri_passage.dart';
import 'package:basa_capstone/core/models/phil_iri_question.dart';
import 'package:basa_capstone/core/repositories/phil_iri_passage_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Database db;
  late PhilIriPassageRepositorySqlite repo;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    db = await LocalDatabase.instance(Directory.systemTemp.createTempSync('basa_passages_').path);
    repo = PhilIriPassageRepositorySqlite(db);
    // A pulled (server) session; local foreign keys are off.
    await db.insert('phil_iri_assessments', {
      'id': 70, 'student_id': 1, 'school_id': 1, 'section_id': 1, 'school_year': '2026-2027',
      'attempt_no': 1, 'round': 'bosy', 'status': 'completed', 'assessed_at': '2026-10-23', 'origin': 'cloud',
      'row_version': 0, // pulled
    });
  });

  tearDownAll(LocalDatabase.close);

  Future<void> passage(int id, int questionId) async {
    await repo.upsertWithId(PhilIriPassage(
        id: id, collectionId: 1, level: 7, title: 'P$id', body: 'One two three.', wordCount: 3));
    await repo.upsertQuestionWithId(PhilIriQuestion(
        id: questionId, passageId: id, questionNo: 1, prompt: 'Q?', choices: const ['a', 'b'], answerKey: 'a'));
  }

  Future<void> reading(int id, int passageId, {int? answerId, int? questionId}) async {
    // Positive id = pulled (row_version 0), negative = new on this device.
    int? version(int rowId) => rowId > 0 ? 0 : null;
    await db.insert('phil_iri_readings',
        {'id': id, 'assessment_id': 70, 'sequence_no': id.abs(), 'passage_id': passageId, 'row_version': version(id)});
    if (answerId != null) {
      await db.insert('phil_iri_answers', {
        'id': answerId, 'reading_id': id, 'question_id': questionId, 'chosen': 'a', 'row_version': version(answerId),
      });
    }
  }

  test('a passage only server readings use: UsedOnServerError, nothing removed', () async {
    await passage(501, 901);
    await reading(601, 501, answerId: 701, questionId: 901);
    await expectLater(repo.removeMirrored(501), throwsA(isA<UsedOnServerError>()));
    await expectLater(repo.removeMirroredQuestion(901), throwsA(isA<UsedOnServerError>()));
    expect(await repo.findById(501), isNotNull);
    expect(await repo.getQuestions(501), hasLength(1));
  });

  test('a passage an unsent reading uses: plain StateError (sync first)', () async {
    await passage(502, 902);
    await reading(602, 502);
    await reading(-3, 502, answerId: -4, questionId: 902);
    await expectLater(repo.removeMirrored(502),
        throwsA(isA<StateError>().having((e) => e, 'type', isNot(isA<UsedOnServerError>()))));
    await expectLater(repo.removeMirroredQuestion(902),
        throwsA(isA<StateError>().having((e) => e, 'type', isNot(isA<UsedOnServerError>()))));
  });

  test('an unused passage is removed with its questions', () async {
    await passage(503, 903);
    await repo.removeMirroredQuestion(903);
    expect(await repo.getQuestions(503), isEmpty);
    await repo.removeMirrored(503);
    expect(await repo.findById(503), isNull);
  });
}
