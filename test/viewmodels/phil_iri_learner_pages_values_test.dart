// Phil-IRI value sources on the ViewModel (spec 2026-11-14 D5, D11): the
// round views of reportResults / learnerResults, and values_learner_pages.
// One Grade 7 learner: BOSY (2026-08-05, comprehension 2/2) and MOSY 1
// (2026-10-05, 1/2) finished, nothing later.
import 'dart:convert';
import 'dart:io';

import 'package:basa_capstone/core/models/phil_iri_assessment.dart' show PhilIriRound;
import 'package:basa_capstone/core/models/phil_iri_reading.dart' show PhilIriReadingMethod;
import 'package:basa_capstone/core/models/report_setting.dart';
import 'package:basa_capstone/core/wiring/app_context.dart';
import 'package:basa_capstone/core/wiring/wire_shared.dart';
import 'package:basa_capstone/core/wiring/wire_tutor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../helpers/offline_owner.dart';

const _year = '2026-2027';
const _learner = 711, _section = 92;
const bosy = PhilIriRound.bosy, mosy1 = PhilIriRound.mosy1, mosy2 = PhilIriRound.mosy2;
const carried = PhilIriValues.carried, actual = PhilIriValues.actual;

void main() {
  late AppContext ctx;
  late TutorVms t;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    ctx = await AppContext.open(dataDir: Directory.systemTemp.createTempSync('basa_pi_values_').path);
    t = wireTutor(ctx, wireShared(ctx));
    final db = ctx.localDb;
    await db.insert('schools', {'id': 1, 'school_id': 'ZZ44', 'school_name': 'ZZ values'});
    await seedOfflineOwner(db,
        userId: '00000000-0000-0000-0000-00000000ab44', email: 'values@test', role: 'coordinator', schoolId: 1);
    await db.insert('sections',
        {'id': _section, 'school_id': 1, 'school_year': _year, 'grade_level': '7', 'section_name': 'S92'});
    await db.insert('students', {'id': _learner, 'lrn': '999999990711', 'last_name': 'Val', 'first_name': 'F', 'school_id': 1});
    await db.insert('enrollments', {'student_id': _learner, 'section_id': _section, 'school_year': _year, 'status': 'active'});
    await db.insert('phil_iri_collections',
        {'id': 1, 'name': 'Graded values', 'is_grade_leveled': 1, 'has_comprehension': 1});
    for (final id in [401, 402]) {
      await db.insert('phil_iri_passages', {
        'id': id, 'collection_id': 1, 'level': 7, 'title': 'P$id',
        'body': List.filled(120, 'w$id').join(' '), 'word_count': 120, 'is_active': 1,
      });
      for (final q in [1, 2]) {
        await db.insert('phil_iri_questions', {
          'id': id * 10 + q, 'passage_id': id, 'question_no': q, 'prompt': 'Q$q', 'choices': '["a","b"]',
          'answer_key': 'a',
        });
      }
    }
    expect(await ctx.authVm.signInOffline(email: 'values@test', password: 'test-pw'), isNull);

    final vm = t.philIriVm;
    for (final (round, passage, date, second) in [
      (bosy, 401, DateTime(2026, 8, 5), 'a'),
      (mosy1, 402, DateTime(2026, 10, 5), 'b'),
    ]) {
      final s = await vm.startSession(
          studentId: _learner, sectionId: _section, schoolYear: _year, round: round, assessedAt: date);
      final r = await vm.startReading(
          assessmentId: s.id!, passageId: passage, method: PhilIriReadingMethod.oneMinute, wordsRead: 120);
      await vm.answer(readingId: r.id!, questionId: passage * 10 + 1, chosen: 'a');
      await vm.answer(readingId: r.id!, questionId: passage * 10 + 2, chosen: second);
      await vm.complete(s.id!);
    }
  });

  Future<void> schoolRow(Map<String, Object?>? settings) async {
    await ctx.localDb.delete('report_settings');
    if (settings != null) {
      await ctx.localDb.insert('report_settings', {'id': 1, 'school_id': 1, 'settings': jsonEncode(settings)});
    }
  }

  test('reportResults.view: a round without an own reading is not assessed under actual', () async {
    final r = await t.philIriVm.reportResults(studentId: _learner, sectionId: _section, schoolYear: _year);
    final a = r.view(mosy2, actual);
    expect(a.notAssessedThisRound, isTrue);
    expect((a.adjustedLevel, a.levelsDown), (4, 3));
    final c = r.view(mosy2, carried);
    expect(c.notAssessedThisRound, isFalse);
    expect((c.profile, c.comprehensionScore), (r.round(mosy1).profile, r.round(mosy1).comprehensionScore));
    // MOSY 1's own reading (50%) under actual; carried keeps BOSY's 100%.
    expect(r.view(mosy1, actual).comprehensionScore, 0.5);
    expect(r.view(mosy1, carried).comprehensionScore, 1.0);
  });

  test('asOf before MOSY 1: MOSY 1 is not assessed under actual', () async {
    final r = await t.philIriVm.reportResults(
        studentId: _learner, sectionId: _section, schoolYear: _year, asOf: '2026-09-30');
    expect(r.view(mosy1, actual).notAssessedThisRound, isTrue);
    expect(r.view(bosy, actual).notAssessedThisRound, isFalse);
    expect(r.latestView(PhilIriRound.values, actual)!.round, bosy);
  });

  test('latestView: actual = the last round read; carried = latest as before', () async {
    final r = await t.philIriVm.reportResults(studentId: _learner, sectionId: _section, schoolYear: _year);
    final a = r.latestView(PhilIriRound.values, actual)!;
    expect((a.round, a.comprehensionScore), (mosy1, 0.5));
    final c = r.latestView(PhilIriRound.values, carried)!;
    expect((c.round, c.profile), (r.latest(PhilIriRound.values)!.round, r.latest(PhilIriRound.values)!.profile));
    expect(r.latestView({mosy2}, actual), isNull);
    expect(r.latestView({mosy2}, carried), isNull);
  });

  test('learnerResults.values follows values_learner_pages (default carried)', () async {
    final vm = t.philIriVm;
    Future<PhilIriValues> values() async =>
        (await vm.learnerResults(studentId: _learner, sectionId: _section, schoolYear: _year)).values;
    await schoolRow(null);
    expect(await values(), carried);
    expect(await vm.valueSource(1, PhilIriValueList.learnerPages), carried);
    expect(await vm.valueSource(1, PhilIriValueList.ranking), actual);
    await schoolRow({'values_learner_pages': 'actual'});
    expect(await values(), actual);
    expect(await vm.valueSource(1, PhilIriValueList.learnerPages), actual);

    final res = await vm.learnerResults(studentId: _learner, sectionId: _section, schoolYear: _year);
    expect(res.view(mosy2).notAssessedThisRound, isTrue);
    expect(res.view(mosy1).comprehensionScore, 0.5);
    expect(res.endView()!.round, mosy1);
    await schoolRow(null);
    final carriedRes = await vm.learnerResults(studentId: _learner, sectionId: _section, schoolYear: _year);
    expect(carriedRes.view(mosy2).comprehensionScore, 1.0);
    expect(carriedRes.endView()!.round, carriedRes.end!.round);
  });
}
