// A reading imported from ma's workbook keeps only the number of correct
// answers (phil_iri_readings.imported_correct, spec 2026-11-09-phil-iri-import
// D6): scoring reads that count instead of the answers.
import 'dart:io';

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
}
