// AralReportViewModel.learnerRounds: each ARAL learner's BoSY/MoSY result,
// the per-learner part of the implementation report shared with the ARAL
// forms (ARAL memo Plan B Task 4). The report adds these up, so the tallies
// must equal the report's row counts.
//
// School 1, 2026-2027, values_aral actual (the default):
//   Grade 2 section 71 (CRLA, Filipino):
//     G 701  BoSY Low Emerging, MoSY Developing
//     H 702  BoSY High Emerging, no MoSY
//   Grade 7 section 72 (Phil-IRI, 10 questions, 120 words in one minute):
//     P 703  BoSY 3/10, MoSY 1 9/10
//     Q 704  nothing at all (not assessed)
//     R 705  BoSY 9/10, left ARAL (transferred out) before the as-of date
import 'dart:io';

import 'package:basa_capstone/core/models/aral_enrollment.dart';
import 'package:basa_capstone/core/models/phil_iri_assessment.dart' show PhilIriRound;
import 'package:basa_capstone/core/models/phil_iri_reading.dart' show PhilIriReadingMethod;
import 'package:basa_capstone/core/services/crla_rules.dart';
import 'package:basa_capstone/core/wiring/app_context.dart';
import 'package:basa_capstone/core/wiring/wire_admin.dart';
import 'package:basa_capstone/core/wiring/wire_shared.dart';
import 'package:basa_capstone/core/wiring/wire_tutor.dart';
import 'package:basa_capstone/viewmodels/aral_report_viewmodel.dart';
import 'package:basa_capstone/viewmodels/viewmodel_exception.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../helpers/offline_owner.dart';

const _year = '2026-2027';
const _g2 = 71, _g7 = 72;
const g = 701, h = 702, p = 703, q = 704, r = 705;
const _asOf = '2026-11-14';

void main() {
  late AppContext ctx;
  late TutorVms t;
  late AdminVms adm;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    ctx = await AppContext.open(dataDir: Directory.systemTemp.createTempSync('basa_learner_rounds_').path);
    final s = wireShared(ctx);
    t = wireTutor(ctx, s);
    adm = await wireAdmin(ctx, s, t);
    final db = ctx.localDb;
    await db.insert('schools', {'id': 1, 'school_id': 'ZZ46', 'school_name': 'ZZ learner rounds', 'region_id': 13});
    await seedOfflineOwner(db,
        userId: '00000000-0000-0000-0000-00000000ab46', email: 'lr@test', role: 'coordinator', schoolId: 1);
    await db.insert('sections', {'id': _g2, 'school_id': 1, 'school_year': _year, 'grade_level': '2', 'section_name': 'Two'});
    await db.insert('sections', {'id': _g7, 'school_id': 1, 'school_year': _year, 'grade_level': '7', 'section_name': 'Seven'});
    for (final id in [g, h, p, q, r]) {
      await db.insert('students',
          {'id': id, 'lrn': '99999999$id', 'last_name': 'L$id', 'first_name': 'F', 'school_id': 1, 'sex': id.isEven ? 'F' : 'M'});
      await db.insert('enrollments',
          {'student_id': id, 'section_id': id <= h ? _g2 : _g7, 'school_year': _year, 'status': 'active'});
    }
    // CRLA: profiles stored on the attempt, as CrlaViewModel / the pull leave them.
    var attempt = 0;
    Future<void> crla(int student, String round, String profile, String at) {
      attempt++;
      return db.insert('crla_assessments', {
          'id': -100 - attempt, 'student_id': student, 'school_id': 1, 'section_id': _g2, 'school_year': _year,
          'subject_variant': 'fil', 'language': 'Filipino', 'round': round, 'attempt_no': attempt,
          'assessed_at': at, 'reading_profile': profile,
      });
    }
    await crla(g, 'bosy', crlaLowEmerging, '2026-08-05');
    await crla(g, 'mosy', crlaDeveloping, '2026-10-05');
    await crla(h, 'bosy', crlaHighEmerging, '2026-08-05');

    await db.insert('phil_iri_collections', {'id': 1, 'name': 'Graded rounds', 'is_grade_leveled': 1});
    for (var n = 1; n <= 2; n++) {
      final id = 500 + n;
      await db.insert('phil_iri_passages', {
        'id': id, 'collection_id': 1, 'level': 7, 'title': 'P$id',
        'body': List.filled(120, 'w$id').join(' '), 'word_count': 120, 'is_active': 1,
      });
      for (var k = 1; k <= 10; k++) {
        await db.insert('phil_iri_questions',
            {'id': id * 100 + k, 'passage_id': id, 'question_no': k, 'prompt': 'Q$k', 'choices': '["a","b"]', 'answer_key': 'a'});
      }
    }
    expect(await ctx.authVm.signInOffline(email: 'lr@test', password: 'test-pw'), isNull);

    final vm = t.philIriVm;
    Future<void> read(int student, PhilIriRound round, DateTime at, int passageNo, int correct) async {
      final sess = await vm.startSession(studentId: student, sectionId: _g7, schoolYear: _year, round: round, assessedAt: at);
      final passage = 500 + passageNo;
      final rd = await vm.startReading(
          assessmentId: sess.id!, passageId: passage, method: PhilIriReadingMethod.oneMinute, wordsRead: 120);
      for (var k = 1; k <= 10; k++) {
        await vm.answer(readingId: rd.id!, questionId: passage * 100 + k, chosen: k <= correct ? 'a' : 'b');
      }
      await vm.complete(sess.id!);
    }

    await read(p, PhilIriRound.bosy, DateTime(2026, 8, 5), 1, 3);
    await read(p, PhilIriRound.mosy1, DateTime(2026, 10, 5), 2, 9);
    await read(r, PhilIriRound.bosy, DateTime(2026, 8, 5), 1, 9);

    // The roster, written as the pull leaves it (the proposal rules are not under test).
    Future<int> roster(int student, int section, String ks) => db.insert('aral_enrollments', {
          'id': -student, 'student_id': student, 'school_id': 1, 'section_id': section, 'school_year': _year,
          'key_stage': ks, 'track': ks == 'ks1' ? null : 'basic', 'status': 'active', 'entered_on': '2026-08-10',
          'basis_source': 'manual',
        });
    await roster(g, _g2, 'ks1');
    await roster(h, _g2, 'ks1');
    await roster(p, _g7, 'ks3');
    await roster(q, _g7, 'ks3');
    await roster(r, _g7, 'ks3');
    await t.aralVm.exit(-r, AralExitReason.transferredOut, on: DateTime(2026, 9, 1));
  });

  Future<Map<int, AralLearnerRounds>> rounds() async => {
        for (final x in await adm.aralReportVm.learnerRounds(schoolId: 1, schoolYear: _year, asOf: _asOf))
          x.enrollment.studentId: x,
      };

  test('CRLA: profile names, profile order as rank, no MoSY = no result', () async {
    final by = await rounds();
    final lg = by[g]!;
    expect((lg.grade, lg.instrument, lg.inAral, lg.notAssessed), (2, 'CRLA', true, false));
    expect((lg.bosyResult, lg.bosyRank), (crlaLowEmerging, 0));
    expect((lg.mosyResult, lg.mosyRank, lg.mosyOwn), (crlaDeveloping, 2, true));
    final lh = by[h]!;
    expect((lh.bosyResult, lh.bosyRank), (crlaHighEmerging, 1));
    expect((lh.mosyResult, lh.mosyRank, lh.mosyOwn), (aralReportNoResult, null, false));
  });

  test('Phil-IRI: report groups, adjusted level as rank, not assessed, left ARAL', () async {
    final by = await rounds();
    final lp = by[p]!;
    expect((lp.grade, lp.instrument, lp.inAral, lp.notAssessed), (7, 'Phil-IRI', true, false));
    expect(lp.mosyResult, 'GLR');
    expect((lp.mosyRank, lp.mosyOwn), (8, true)); // Independent: adjusted level above the grade, still GLR
    expect(lp.bosyRank, lessThan(7));
    expect(lp.bosyResult, isNot('GLR'));
    final lq = by[q]!;
    expect((lq.notAssessed, lq.bosyResult, lq.mosyResult), (true, aralReportNotAssessed, aralReportNotAssessed));
    expect((lq.bosyRank, lq.mosyRank, lq.mosyOwn), (null, null, false));
    final lr = by[r]!;
    expect((lr.inAral, lr.bosyResult, lr.bosyRank), (false, 'GLR', 8));
    expect((lr.mosyResult, lr.mosyRank, lr.mosyOwn), (null, null, false));
    expect(lr.enrollment.exitReason, AralExitReason.transferredOut);
  });

  test("the implementation report's counts are these learners added up", () async {
    final list = await adm.aralReportVm.learnerRounds(schoolId: 1, schoolYear: _year, asOf: _asOf);
    final rep = await adm.aralReportVm.implementationReport(schoolId: 1, schoolYear: _year, asOf: DateTime(2026, 11, 14));
    for (final row in rep.rows) {
      final mine = list.where((x) => x.enrollment.sectionId == row.section.id);
      final bosy = <String, int>{};
      final mosy = <String, int>{};
      for (final x in mine) {
        bosy[x.bosyResult!] = (bosy[x.bosyResult!] ?? 0) + 1;
        if (x.inAral) mosy[x.mosyResult!] = (mosy[x.mosyResult!] ?? 0) + 1;
      }
      expect(bosy, row.bosy, reason: row.section.sectionName);
      expect(mosy, row.mosy, reason: row.section.sectionName);
    }
    expect(list.map((x) => x.enrollment.studentId), [g, h, p, q, r]); // by grade, section, then roster order
  });

  test('an as-of date that is not a date is refused', () async {
    expect(() => adm.aralReportVm.learnerRounds(schoolId: 1, schoolYear: _year, asOf: '14/11/2026'),
        throwsA(isA<ViewModelException>()));
  });
}
