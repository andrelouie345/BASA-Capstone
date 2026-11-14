// Form 2b under actual values (spec 2026-11-14 D8, owner 2026-11-14 option A):
// a learner who read in a round but has 0% or a blank comprehension counts in
// 3-LD Frustration too, so the bands add up to the enrolment. Under carried
// they stay out of every band (ma's rule: no comprehension yet, or 0).
// Section 95 (Grade 7): Z 971 MOSY 1 one answer "x" (0%), K 972 MOSY 1 no
// answer (blank), R 973 MOSY 1 9/10.
import 'dart:convert';
import 'dart:io';

import 'package:basa_capstone/core/models/phil_iri_assessment.dart' show PhilIriRound;
import 'package:basa_capstone/core/models/phil_iri_reading.dart' show PhilIriReadingMethod;
import 'package:basa_capstone/core/models/report_setting.dart';
import 'package:basa_capstone/core/services/nla_form2b.dart' show NlaBand;
import 'package:basa_capstone/core/wiring/app_context.dart';
import 'package:basa_capstone/core/wiring/wire_shared.dart';
import 'package:basa_capstone/core/wiring/wire_tutor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../helpers/offline_owner.dart';

const _year = '2026-2027';
const _sec = 95, z = 971, k = 972, r = 973;
const mosy1 = PhilIriRound.mosy1;

void main() {
  late AppContext ctx;
  late TutorVms t;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    ctx = await AppContext.open(dataDir: Directory.systemTemp.createTempSync('basa_f2b_zero_').path);
    t = wireTutor(ctx, wireShared(ctx));
    final db = ctx.localDb;
    await db.insert('schools', {'id': 1, 'school_id': 'ZZ47', 'school_name': 'ZZ zero'});
    await seedOfflineOwner(db,
        userId: '00000000-0000-0000-0000-00000000ab48', email: 'zero@test', role: 'coordinator', schoolId: 1);
    await db.insert('sections', {'id': _sec, 'school_id': 1, 'school_year': _year, 'grade_level': '7', 'section_name': 'S95'});
    for (final id in [z, k, r]) {
      await db.insert('students', {'id': id, 'lrn': '99999999$id', 'last_name': 'L$id', 'first_name': 'F', 'school_id': 1, 'sex': 'F'});
      await db.insert('enrollments', {'student_id': id, 'section_id': _sec, 'school_year': _year, 'status': 'active'});
    }
    await db.insert('phil_iri_collections', {'id': 1, 'name': 'Graded zero', 'is_grade_leveled': 1});
    await db.insert('phil_iri_passages', {
      'id': 701, 'collection_id': 1, 'level': 7, 'title': 'P701',
      'body': List.filled(120, 'w701').join(' '), 'word_count': 120, 'is_active': 1,
    });
    for (var q = 1; q <= 10; q++) {
      await db.insert('phil_iri_questions',
          {'id': 70100 + q, 'passage_id': 701, 'question_no': q, 'prompt': 'Q$q', 'choices': '["a","b"]', 'answer_key': 'a'});
    }
    expect(await ctx.authVm.signInOffline(email: 'zero@test', password: 'test-pw'), isNull);
    final vm = t.philIriVm;
    for (final (student, answers) in [(z, {1: null}), (k, <int, String?>{}), (r, {for (var q = 1; q <= 10; q++) q: q <= 9 ? 'a' : 'b'})]) {
      final s = await vm.startSession(
          studentId: student, sectionId: _sec, schoolYear: _year, round: mosy1, assessedAt: DateTime(2026, 9, 5));
      final rd = await vm.startReading(
          assessmentId: s.id!, passageId: 701, method: PhilIriReadingMethod.oneMinute, wordsRead: 120);
      for (final e in answers.entries) {
        await vm.answer(readingId: rd.id!, questionId: 70100 + e.key, chosen: e.value);
      }
      await vm.complete(s.id!);
    }
  });

  Future<void> values(PhilIriValues? v) async {
    await ctx.localDb.delete('report_settings');
    if (v != null) {
      await ctx.localDb.insert('report_settings',
          {'id': 1, 'school_id': 1, 'settings': jsonEncode({PhilIriValueList.form2b.key: v.name})});
    }
  }

  test('actual: 0% and blank comprehension count in 3-LD Frustration; bands add up to the enrolment', () async {
    await values(PhilIriValues.actual);
    final row = (await t.nlaReportVm.report(schoolId: 1, schoolYear: _year, sectionIds: {_sec})).sections.single;
    expect(row.band(mosy1, NlaBand.ld3Frustration).total, 2); // Z (0%), K (blank)
    expect(row.band(mosy1, NlaBand.glr).total, 1); // R (90%)
    expect(row.assessed(mosy1).total, 3);
  });

  test('carried: 0% and blank stay out of every band (unchanged)', () async {
    await values(null);
    final row = (await t.nlaReportVm.report(schoolId: 1, schoolYear: _year, sectionIds: {_sec})).sections.single;
    expect(row.band(mosy1, NlaBand.ld3Frustration).total, 0);
    expect(row.assessed(mosy1).total, 1); // R only
  });
}
