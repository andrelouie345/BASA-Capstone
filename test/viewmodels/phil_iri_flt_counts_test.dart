// The FLT toggle (report_settings key no_comprehension_counts_FLT, default
// off; owner 2026-11-10): a reading from a collection without comprehension
// questions (e.g. the Foundational Literacy Test) counts as assessed only
// when the school's setting (school -> region -> off) is on.
import 'dart:convert';
import 'dart:io';

import 'package:basa_capstone/core/models/phil_iri_assessment.dart' show PhilIriRound;
import 'package:basa_capstone/core/models/phil_iri_reading.dart' show PhilIriReadingMethod;
import 'package:basa_capstone/core/models/phil_iri_types.dart' show PhilIriRoundStatus;
import 'package:basa_capstone/core/models/report_setting.dart';
import 'package:basa_capstone/core/wiring/app_context.dart';
import 'package:basa_capstone/core/wiring/wire_shared.dart';
import 'package:basa_capstone/core/wiring/wire_tutor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../helpers/offline_owner.dart';

const _year = '2026-2027';
// 701 read the FLT (no comprehension); 702 read a graded passage and left
// every answer blank; 703 read it and recorded one answer, "x" (does not
// know): a recorded 0 still counts (spec 2026-11-09 D4).
const flt = 701, blank = 702, zero = 703;

void main() {
  late AppContext ctx;
  late TutorVms t;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    ctx = await AppContext.open(dataDir: Directory.systemTemp.createTempSync('basa_pi_flt_').path);
    t = wireTutor(ctx, wireShared(ctx));
    final db = ctx.localDb;
    await db.insert('schools', {'id': 1, 'school_id': 'ZZ43', 'school_name': 'ZZ flt'});
    await seedOfflineOwner(db,
        userId: '00000000-0000-0000-0000-00000000ab43', email: 'flt@test', role: 'coordinator', schoolId: 1);
    await db.insert('sections', {'id': 91, 'school_id': 1, 'school_year': _year, 'grade_level': '7', 'section_name': 'S91'});
    for (final id in [flt, blank, zero]) {
      await db.insert('students', {'id': id, 'lrn': '99999999$id', 'last_name': 'L$id', 'first_name': 'F', 'school_id': 1});
      await db.insert('enrollments', {'student_id': id, 'section_id': 91, 'school_year': _year, 'status': 'active'});
    }
    await db.insert('phil_iri_collections',
        {'id': 1, 'name': 'Graded flt', 'is_grade_leveled': 1, 'has_comprehension': 1});
    await db.insert('phil_iri_collections',
        {'id': 2, 'school_id': 1, 'name': 'Foundational Literacy Test', 'is_grade_leveled': 1, 'has_comprehension': 0});
    for (final (id, collection) in [(401, 1), (402, 2)]) {
      await db.insert('phil_iri_passages', {
        'id': id, 'collection_id': collection, 'level': 7, 'title': 'P$id',
        'body': List.filled(120, 'word').join(' '), 'word_count': 120, 'is_active': 1,
      });
    }
    await db.insert('phil_iri_questions',
        {'id': 4001, 'passage_id': 401, 'question_no': 1, 'prompt': 'Q1', 'choices': '["a","b"]', 'answer_key': 'a'});
    expect(await ctx.authVm.signInOffline(email: 'flt@test', password: 'test-pw'), isNull);

    final vm = t.philIriVm;
    for (final (student, passage) in [(flt, 402), (blank, 401), (zero, 401)]) {
      final s = await vm.startSession(studentId: student, sectionId: 91, schoolYear: _year, round: PhilIriRound.bosy);
      final r = await vm.startReading(
          assessmentId: s.id!, passageId: passage, method: PhilIriReadingMethod.oneMinute, wordsRead: 120);
      if (student == zero) await vm.answer(readingId: r.id!, questionId: 4001, chosen: null);
      await vm.complete(s.id!);
    }
  });

  Future<void> setRows({bool? region, bool? school}) async {
    final db = ctx.localDb;
    await db.delete('report_settings');
    if (region != null) {
      await db.insert('report_settings',
          {'id': 1, 'school_id': null, 'settings': jsonEncode({ReportSettings.noComprehensionCountsFltKey: region})});
    }
    if (school != null) {
      await db.insert('report_settings',
          {'id': 2, 'school_id': 1, 'settings': jsonEncode({ReportSettings.noComprehensionCountsFltKey: school})});
    }
  }

  Future<Set<int>> assessed() async {
    final out = <int>{};
    for (final id in [flt, blank]) {
      final res = await t.philIriVm.reportResults(studentId: id, sectionId: 91, schoolYear: _year);
      if (res.status(PhilIriRound.bosy) == PhilIriRoundStatus.assessed) out.add(id);
    }
    return out;
  }

  test('no answers recorded is a blank comprehension; one recorded "x" is an entry of 0', () async {
    await setRows();
    final blankRes = await t.philIriVm.reportResults(studentId: blank, sectionId: 91, schoolYear: _year);
    expect(blankRes.round(PhilIriRound.bosy).comprehensionAssessed, isFalse);
    expect(blankRes.round(PhilIriRound.bosy).actual!.comprehensionBlank, isTrue);
    expect(blankRes.status(PhilIriRound.bosy), PhilIriRoundStatus.carriedOver);
    final zeroRes = await t.philIriVm.reportResults(studentId: zero, sectionId: 91, schoolYear: _year);
    expect(zeroRes.round(PhilIriRound.bosy).comprehensionAssessed, isTrue);
    expect(zeroRes.round(PhilIriRound.bosy).comprehensionPercent, 0);
    expect(zeroRes.status(PhilIriRound.bosy), PhilIriRoundStatus.assessed);
  });

  test('the key is off by default', () {
    expect(const ReportSettings().noComprehensionCountsFlt, isFalse);
    expect(ReportSettings.fromMap({ReportSettings.noComprehensionCountsFltKey: true}).noComprehensionCountsFlt, isTrue);
    expect(ReportSettings.noComprehensionCountsFltKey, 'no_comprehension_counts_FLT');
  });

  test('off: an FLT reading is not assessed', () async {
    await setRows();
    expect(await assessed(), isEmpty);
  });

  test('on for the region: the FLT reading counts, a blank graded passage does not', () async {
    await setRows(region: true);
    expect(await assessed(), {flt});
  });

  test('the school row beats the region row', () async {
    await setRows(region: true, school: false);
    expect(await assessed(), isEmpty);
    await setRows(region: false, school: true);
    expect(await assessed(), {flt});
  });
}
