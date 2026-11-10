// Phil-IRI passages in any round (spec 2026-11-10-phil-iri-any-round-passages,
// ma 2026-11-09): no round refuses a passage because of its test_type; the
// type is a booklet label that only orders the passage list (D4): oral
// follow-ups, then this round's label, then the rest.
import 'dart:io';

import 'package:basa_capstone/core/models/phil_iri_assessment.dart' show PhilIriRound;
import 'package:basa_capstone/core/models/phil_iri_reading.dart' show PhilIriReadingMethod;
import 'package:basa_capstone/core/wiring/app_context.dart';
import 'package:basa_capstone/core/wiring/wire_shared.dart';
import 'package:basa_capstone/core/wiring/wire_tutor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../helpers/offline_owner.dart';

const _year = '2026-2027';
// Grade 7 passages: 501 pre, 502 mosy, 503 post, 504 unlabelled; 505 in a
// non-graded collection; 506 a Grade 6 pre passage.
const pre = 501, mosy = 502, post = 503, untyped = 504, frb = 505, grade6 = 506;

void main() {
  late AppContext ctx;
  late TutorVms t;
  var nextStudent = 800;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    ctx = await AppContext.open(dataDir: Directory.systemTemp.createTempSync('basa_pi_any_round_').path);
    t = wireTutor(ctx, wireShared(ctx));
    final db = ctx.localDb;
    await db.insert('schools', {'id': 1, 'school_id': 'ZZ44', 'school_name': 'ZZ any round'});
    await seedOfflineOwner(db,
        userId: '00000000-0000-0000-0000-00000000ab44', email: 'anyround@test', role: 'coordinator', schoolId: 1);
    await db.insert('sections', {'id': 92, 'school_id': 1, 'school_year': _year, 'grade_level': '7', 'section_name': 'S92'});
    await db.insert('phil_iri_collections', {'id': 1, 'name': 'Graded any', 'is_grade_leveled': 1, 'has_comprehension': 1});
    await db.insert('phil_iri_collections', {'id': 2, 'name': 'FRB any', 'is_grade_leveled': 0, 'has_comprehension': 1});
    for (final (id, collection, level, type) in [
      (pre, 1, 7, 'pre'), (mosy, 1, 7, 'mosy'), (post, 1, 7, 'post'), (untyped, 1, 7, null),
      (frb, 2, null, null), (grade6, 1, 6, 'pre'),
    ]) {
      await db.insert('phil_iri_passages', {
        'id': id, 'collection_id': collection, 'level': level, 'test_type': type, 'title': 'P$id',
        'body': List.filled(100, 'w$id').join(' '), 'word_count': 100, 'is_active': 1,
      });
    }
    expect(await ctx.authVm.signInOffline(email: 'anyround@test', password: 'test-pw'), isNull);
  });

  Future<int> learner() async {
    final id = nextStudent++;
    await ctx.localDb.insert('students', {'id': id, 'lrn': '88888888$id', 'last_name': 'L$id', 'first_name': 'F', 'school_id': 1});
    await ctx.localDb.insert('enrollments', {'student_id': id, 'section_id': 92, 'school_year': _year, 'status': 'active'});
    return id;
  }

  Future<int> session(int student, PhilIriRound round) async =>
      (await t.philIriVm.startSession(studentId: student, sectionId: 92, schoolYear: _year, round: round)).id!;

  Future<void> read(int sessionId, int passage, {PhilIriReadingMethod method = PhilIriReadingMethod.wholeText}) =>
      t.philIriVm.startReading(assessmentId: sessionId, passageId: passage, method: method, readingSeconds: 60);

  Future<List<int>> listed(int sessionId, {PhilIriReadingMethod method = PhilIriReadingMethod.wholeText}) async =>
      [for (final p in await t.philIriVm.availablePassages(sessionId, method: method)) p.id!];

  test('BOSY lists every label, its own (pre) first, the rest in today\'s order', () async {
    final ids = await listed(await session(await learner(), PhilIriRound.bosy));
    expect(ids.first, pre);
    expect(ids.toSet(), {pre, mosy, post, untyped, frb});
    expect(ids.last, frb); // graded before non-graded, as before
  });

  test('MOSY and EOSY put their own label first', () async {
    final student = await learner();
    expect((await listed(await session(student, PhilIriRound.mosy2))).first, mosy);
    expect((await listed(await session(student, PhilIriRound.eosy))).first, post);
  });

  test('a round accepts a passage labelled for another round', () async {
    await read(await session(await learner(), PhilIriRound.bosy), post);
    await read(await session(await learner(), PhilIriRound.mosy1), pre);
    await read(await session(await learner(), PhilIriRound.eosy), mosy);
  });

  test('an oral follow-up comes first even with another round\'s label', () async {
    final student = await learner();
    await read(await session(student, PhilIriRound.bosy), post, method: PhilIriReadingMethod.silent);
    final ids = await listed(await session(student, PhilIriRound.bosy));
    expect(ids.take(2), [post, pre]);
  });

  test('no-repeat still refuses a text read in an earlier round', () async {
    final student = await learner();
    await read(await session(student, PhilIriRound.bosy), post);
    final eosy = await session(student, PhilIriRound.eosy);
    expect(await listed(eosy), isNot(contains(post)));
    await expectLater(read(eosy, post), throwsA(predicate((e) => '$e'.contains('has already read'))));
  });

  test('own grade still refuses', () async {
    await expectLater(read(await session(await learner(), PhilIriRound.bosy), grade6),
        throwsA(predicate((e) => '$e'.contains('reads a Grade 7 passage'))));
  });
}
