// A reading imported from ma's workbook keeps only the number of correct
// answers (phil_iri_readings.imported_correct, spec 2026-11-09-phil-iri-import
// D6): scoring reads that count instead of the answers.
import 'dart:io';

import 'package:basa_capstone/core/models/phil_iri_assessment.dart';
import 'package:basa_capstone/core/models/phil_iri_miscue.dart';
import 'package:basa_capstone/core/models/phil_iri_reading.dart';
import 'package:basa_capstone/core/services/phil_iri_results.dart';
import 'package:basa_capstone/viewmodels/viewmodel_exception.dart';
import 'package:basa_capstone/core/console/commands/phil_iri_commands.dart';
import 'package:basa_capstone/core/console/console_registry.dart';
import 'package:basa_capstone/core/wiring/app_context.dart';
import 'package:basa_capstone/core/wiring/wire_shared.dart';
import 'package:basa_capstone/core/wiring/wire_tutor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../helpers/offline_owner.dart';

const _year = '2026-2027';

void main() {
  late AppContext ctx;
  late TutorVms t;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    ctx = await AppContext.open(dataDir: Directory.systemTemp.createTempSync('basa_pi_imported_').path);
    t = wireTutor(ctx, wireShared(ctx));
    await seedOfflineOwner(ctx.localDb,
        userId: '00000000-0000-0000-0000-00000000ab31', email: 'imp@test', role: 'coordinator', schoolId: 1);
    expect(await ctx.authVm.signInOffline(email: 'imp@test', password: 'test-pw'), isNull);
  });

  test('importedCorrect scores like five right answers', () async {
    final db = ctx.localDb;
    await db.insert('schools', {'id': 1, 'school_id': 'ZZ31', 'school_name': 'ZZ imported'});
    await db.insert('sections', {'id': 71, 'school_id': 1, 'school_year': _year, 'grade_level': '7', 'section_name': 'S71'});
    await db.insert('students', {'id': 510, 'lrn': '999999994010', 'last_name': 'L', 'first_name': 'F', 'school_id': 1});
    await db.insert('enrollments', {'student_id': 510, 'section_id': 71, 'school_year': _year, 'status': 'active'});
    await db.insert('phil_iri_collections', {'id': 1, 'name': 'Graded imported', 'is_grade_leveled': 1});
    await db.insert('phil_iri_passages', {
      'id': 201, 'collection_id': 1, 'test_type': 'mosy', 'level': 7, 'title': 'P201',
      'body': List.filled(150, 'word').join(' '), 'word_count': 150, 'is_active': 1,
    });
    for (var q = 1; q <= 8; q++) {
      await db.insert('phil_iri_questions',
          {'passage_id': 201, 'question_no': q, 'prompt': 'Q$q', 'choices': '["a","b"]', 'answer_key': 'a'});
    }
    Future<int> localId() async => -(await db.rawInsert("INSERT INTO local_ids (made_at) VALUES (datetime('now'))"));
    final session = await localId();
    await db.insert('phil_iri_assessments', {
      'id': session, 'student_id': 510, 'school_id': 1, 'section_id': 71, 'school_year': _year,
      'round': 'bosy', 'assessed_at': '2026-07-01', 'import_source': 'workbook',
    });
    final reading = await localId();
    await db.insert('phil_iri_readings', {
      'id': reading, 'assessment_id': session, 'sequence_no': 1, 'passage_id': 201,
      'method': 'one_minute', 'words_read': 120, 'imported_correct': 5,
    });
    for (var i = 0; i < 3; i++) {
      await db.insert('phil_iri_miscues',
          {'id': await localId(), 'reading_id': reading, 'word_index': null, 'miscue_type': 'omission'});
    }

    final result = await t.philIriVm.scoreReading(reading);

    expect(result.comprehensionScore, 5 / 8);
    expect(result.wordReadingScore, 117 / 120);
  });

  // R2 (spec 2026-11-10-phil-iri-untitled-readings): readings imported from
  // the workbook without a passage ("Untitled") or without a word reading.
  group('untitled and comprehension-only', () {
    const untitledMsg = 'This reading was imported without a passage (Untitled) and cannot be edited here.';
    late Future<int> Function() localId;

    setUpAll(() async {
      final db = ctx.localDb;
      localId = () async => -(await db.rawInsert("INSERT INTO local_ids (made_at) VALUES (datetime('now'))"));
      await db.insert('sections', {'id': 72, 'school_id': 1, 'school_year': _year, 'grade_level': '7', 'section_name': 'S72'});
      for (var i = 0; i < 6; i++) {
        await db.insert('students', {'id': 520 + i, 'lrn': '99999999402$i', 'last_name': 'L$i', 'first_name': 'F', 'school_id': 1});
        await db.insert('enrollments', {'student_id': 520 + i, 'section_id': 72, 'school_year': _year, 'status': 'active'});
      }
      for (final id in [202, 203]) {
        await db.insert('phil_iri_passages', {
          'id': id, 'collection_id': 1, 'test_type': null, 'level': 7, 'title': 'P$id',
          'body': List.filled(150, 'w$id').join(' '), 'word_count': 150, 'is_active': 1,
        });
        for (var q = 1; q <= 8; q++) {
          await db.insert('phil_iri_questions',
              {'passage_id': id, 'question_no': q, 'prompt': 'Q$q', 'choices': '["a","b"]', 'answer_key': 'a'});
        }
      }
    });

    Future<int> importedSession(int student, String round) async {
      final id = await localId();
      await ctx.localDb.insert('phil_iri_assessments', {
        'id': id, 'student_id': student, 'school_id': 1, 'section_id': 72, 'school_year': _year,
        'round': round, 'assessed_at': '2026-07-01', 'import_source': 'workbook',
      });
      return id;
    }

    Future<int> importedReading(int session, Map<String, Object?> fields) async {
      final id = await localId();
      await ctx.localDb.insert('phil_iri_readings', {'id': id, 'assessment_id': session, 'sequence_no': 1, ...fields});
      return id;
    }

    Future<PhilIriRoundResult> round(int student, PhilIriRound r) async {
      final res = await t.philIriVm.learnerResults(studentId: student, sectionId: 72, schoolYear: _year);
      return res.rounds.firstWhere((x) => x.round == r);
    }

    Future<void> complete(int session) =>
        ctx.localDb.update('phil_iri_assessments', {'status': 'completed'}, where: 'id = ?', whereArgs: [session]);

    test('untitled workbook reading scores with the imported total', () async {
      final s = await importedSession(520, 'bosy');
      await importedReading(s, {
        'passage_id': null, 'method': 'whole_text', 'reading_seconds': 60,
        'imported_word_count': 120, 'imported_correct': 6, 'imported_total': 8,
      });
      await complete(s);
      final bosy = await round(520, PhilIriRound.bosy);
      expect(bosy.comprehensionScore, 0.75);
      expect(bosy.wordReadingScore, 1.0);
      expect(bosy.wordsPerMinute, 120);
      expect(bosy.status, PhilIriRoundStatus.assessed);
    });

    test('comprehension-only imported reading is scored, not skipped', () async {
      final s = await importedSession(521, 'bosy');
      await importedReading(s, {'passage_id': 202, 'method': 'whole_text', 'imported_correct': 4});
      await complete(s);
      final bosy = await round(521, PhilIriRound.bosy);
      expect(bosy.given, isTrue);
      expect(bosy.comprehensionScore, 0.5);
      expect(bosy.wordReadingAssumed, isTrue);
      expect(bosy.status, PhilIriRoundStatus.carriedOver);
    });

    test('untitled comprehension-only reading scores from its total', () async {
      final s = await importedSession(522, 'mosy1');
      await importedReading(s, {'passage_id': null, 'method': 'whole_text', 'imported_correct': 6, 'imported_total': 8});
      await complete(s);
      final mosy1 = await round(522, PhilIriRound.mosy1);
      expect(mosy1.comprehensionScore, 0.75);
      expect(mosy1.wordReadingAssumed, isTrue);
      expect(mosy1.status, PhilIriRoundStatus.carriedOver);
    });

    test('complete() accepts an untimed imported session', () async {
      final s = await importedSession(522, 'bosy');
      await importedReading(s, {'passage_id': 202, 'method': 'whole_text', 'imported_correct': 4});
      final done = await t.philIriVm.complete(s);
      expect(done.status, PhilIriStatus.completed);
    });

    test('complete() still refuses an untimed live session', () async {
      final s = await t.philIriVm.startSession(studentId: 523, sectionId: 72, schoolYear: _year, round: PhilIriRound.bosy);
      await t.philIriVm.startReading(assessmentId: s.id!, passageId: 203);
      expect(
          () => t.philIriVm.complete(s.id!),
          throwsA(isA<ViewModelException>()
              .having((e) => e.message, 'message', 'Record the reading time before completing the session.')));
    });

    test('finalize stores null word reading columns for a comprehension-only reading', () async {
      final s = await importedSession(524, 'bosy');
      final r = await importedReading(s, {'passage_id': 202, 'method': 'whole_text', 'imported_correct': 4});
      await complete(s);
      await t.philIriVm.finalize(s);
      final row = (await ctx.localDb.query('phil_iri_readings', where: 'id = ?', whereArgs: [r])).single;
      expect(row['word_reading_level'], isNull);
      expect(row['accuracy_level'], isNull);
      expect(row['comprehension_score'], 0.5);
      expect(row['profile'], isNotNull);
    });

    test('live calls on an untitled reading are refused; delete still works', () async {
      final s = await importedSession(525, 'bosy');
      final r = await importedReading(s, {'passage_id': null, 'method': 'one_minute', 'words_read': 70});
      Matcher refused() =>
          throwsA(isA<ViewModelException>().having((e) => e.message, 'message', untitledMsg));
      await expectLater(t.philIriVm.saveTiming(r, wordsRead: 80), refused());
      await expectLater(t.philIriVm.saveObservation(r, const PhilIriObservation(wordByWord: true)), refused());
      await expectLater(
          t.philIriVm.markMiscue(readingId: r, wordIndex: 1, type: PhilIriMiscueType.omission), refused());
      await expectLater(t.philIriVm.answer(readingId: r, questionId: 1, chosen: 'a'), refused());
      expect(await t.philIriVm.silentReadingFollowedUp(r), isNull);
      await t.philIriVm.deleteReading(r);
      expect(await ctx.localDb.query('phil_iri_readings', where: 'id = ?', whereArgs: [r]), isEmpty);
    });

    test('the console shows an untitled reading as Untitled', () async {
      final s = await importedSession(521, 'mosy1');
      final r = await importedReading(s, {
        'passage_id': null, 'method': 'whole_text', 'reading_seconds': 60,
        'imported_word_count': 120, 'imported_correct': 6, 'imported_total': 8,
      });
      final registry = ConsoleRegistry();
      registerPhilIriCommands(registry, t.philIriVm);
      final out = await registry.execute('phil-iri-session $s');
      expect(out, contains('Reading $r: Untitled (120 words, typed) · comprehension 6/8 · whole text, 60 s'));
    });

    test('a live reading after an untitled one is not blocked', () async {
      final s = await importedSession(520, 'mosy1');
      await importedReading(s, {'passage_id': null, 'method': 'one_minute', 'words_read': 70});
      final live = await t.philIriVm.startSession(studentId: 520, sectionId: 72, schoolYear: _year, round: PhilIriRound.mosy2);
      final reading = await t.philIriVm.startReading(assessmentId: live.id!, passageId: 203, readingSeconds: 60);
      expect(reading.passageId, 203);
    });
  });
}
