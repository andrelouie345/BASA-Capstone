// ARAL memo settings, basis round (plan docs/superpowers/plans/2026-11-18-aral-memo-a-settings.md,
// Task 6): with the school's basis_round 'mosy', a new proposal for Grades
// 2-10 uses the latest assessed round up to MoSY (CRLA mosy; Phil-IRI the
// latest of MOSY #3, #2, #1 that counts), else BoSY; 'bosy' (default) is
// today's rule. Grade 1 already uses CRLA MoSY. The round's values follow
// the school's values_aral (carried = best so far, the default; actual).
//
// Grade 7 section 81 (school 1), 10 questions per passage, one-minute
// readings of 120 words with no miscues (word reading 100%):
//   A 701  BOSY 9/10 (grade-level ready), MOSY 1 2/10
//   C 703  BOSY 3/10 only
//   F 706  BOSY 3/10, MOSY 1 9/10, MOSY 2 2/10
// Grade 2 section 82, CRLA Filipino rows (the grade's language):
//   G 721  BOSY Low Emerging, MOSY Transitioning
//   H 722  BOSY Low Emerging only
import 'dart:convert';
import 'dart:io';

import 'package:basa_capstone/core/models/phil_iri_assessment.dart' show PhilIriRound;
import 'package:basa_capstone/core/models/phil_iri_reading.dart' show PhilIriReadingMethod;
import 'package:basa_capstone/core/services/crla_rules.dart';
import 'package:basa_capstone/core/wiring/app_context.dart';
import 'package:basa_capstone/core/wiring/wire_shared.dart';
import 'package:basa_capstone/core/wiring/wire_tutor.dart';
import 'package:basa_capstone/viewmodels/aral_viewmodel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../helpers/offline_owner.dart';

const _year = '2026-2027';
const _g7 = 81, _g2 = 82;
const a = 701, c = 703, f = 706, g = 721, h = 722;

void main() {
  late AppContext ctx;
  late TutorVms t;

  Future<void> basis(String? round) async {
    await ctx.localDb.delete('aral_settings');
    if (round != null) {
      await ctx.localDb.insert('aral_settings', {'id': 1, 'school_id': 1, 'settings': jsonEncode({'basis_round': round})});
    }
  }

  Future<void> valuesAral(String? v) async {
    await ctx.localDb.delete('report_settings');
    if (v != null) {
      await ctx.localDb.insert('report_settings', {'id': 1, 'school_id': 1, 'settings': jsonEncode({'values_aral': v})});
    }
  }

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    ctx = await AppContext.open(dataDir: Directory.systemTemp.createTempSync('basa_basis_round_').path);
    t = wireTutor(ctx, wireShared(ctx));
    final db = ctx.localDb;
    await db.insert('schools', {'id': 1, 'school_id': 'ZZBR', 'school_name': 'ZZ basis round', 'region_id': 13});
    await seedOfflineOwner(db,
        userId: '00000000-0000-0000-0000-00000000ab46', email: 'br@test', role: 'coordinator', schoolId: 1);
    await db.insert('sections', {'id': _g7, 'school_id': 1, 'school_year': _year, 'grade_level': '7', 'section_name': 'S7'});
    await db.insert('sections', {'id': _g2, 'school_id': 1, 'school_year': _year, 'grade_level': '2', 'section_name': 'S2'});
    for (final (id, sec) in [(a, _g7), (c, _g7), (f, _g7), (g, _g2), (h, _g2)]) {
      await db.insert('students', {'id': id, 'lrn': '99999998$id', 'last_name': 'L$id', 'first_name': 'F', 'school_id': 1});
      await db.insert('enrollments', {'student_id': id, 'section_id': sec, 'school_year': _year, 'status': 'active'});
    }
    await db.insert('phil_iri_collections', {'id': 1, 'name': 'Graded basis', 'is_grade_leveled': 1});
    for (var p = 1; p <= 3; p++) {
      final id = 600 + p;
      await db.insert('phil_iri_passages', {
        'id': id, 'collection_id': 1, 'level': 7, 'title': 'P$id',
        'body': List.filled(120, 'w$id').join(' '), 'word_count': 120, 'is_active': 1,
      });
      for (var q = 1; q <= 10; q++) {
        await db.insert('phil_iri_questions',
            {'id': id * 100 + q, 'passage_id': id, 'question_no': q, 'prompt': 'Q$q', 'choices': '["a","b"]', 'answer_key': 'a'});
      }
    }
    var crlaId = 9700;
    Future<void> crla(int student, String round, String profile) => db.insert('crla_assessments', {
          'id': crlaId++, 'student_id': student, 'school_id': 1, 'section_id': _g2, 'school_year': _year,
          'subject_variant': 'fil', 'language': 'Filipino', 'attempt_no': round == 'bosy' ? 1 : 2,
          'assessed_at': round == 'bosy' ? '2026-08-05' : '2026-10-20',
          'round': round, 'reading_profile': profile, 'origin': 'cloud', 'row_version': 1,
        });
    await crla(g, 'bosy', crlaLowEmerging);
    await crla(g, 'mosy', crlaTransitioning);
    await crla(h, 'bosy', crlaLowEmerging);
    expect(await ctx.authVm.signInOffline(email: 'br@test', password: 'test-pw'), isNull);

    final vm = t.philIriVm;
    final dates = {
      PhilIriRound.bosy: DateTime(2026, 8, 5),
      PhilIriRound.mosy1: DateTime(2026, 9, 5),
      PhilIriRound.mosy2: DateTime(2026, 10, 5),
    };
    Future<void> read(int student, PhilIriRound round, int passageNo, int correct) async {
      final s = await vm.startSession(
          studentId: student, sectionId: _g7, schoolYear: _year, round: round, assessedAt: dates[round]);
      final passage = 600 + passageNo;
      final r = await vm.startReading(
          assessmentId: s.id!, passageId: passage, method: PhilIriReadingMethod.oneMinute, wordsRead: 120);
      for (var q = 1; q <= 10; q++) {
        await vm.answer(readingId: r.id!, questionId: passage * 100 + q, chosen: q <= correct ? 'a' : 'b');
      }
      await vm.complete(s.id!);
    }

    await read(a, PhilIriRound.bosy, 1, 9);
    await read(a, PhilIriRound.mosy1, 2, 2);
    await read(c, PhilIriRound.bosy, 1, 3);
    await read(f, PhilIriRound.bosy, 1, 3);
    await read(f, PhilIriRound.mosy1, 2, 9);
    await read(f, PhilIriRound.mosy2, 3, 2);
  });

  Future<AralCandidate> candidate(int section, int student) async =>
      (await t.aralVm.propose(sectionId: section, schoolYear: _year)).singleWhere((x) => x.student.id == student);

  test("basis round bosy (default): today's rule", () async {
    await basis(null);
    final ca = await candidate(_g7, a);
    expect(ca.status, AralCandidateStatus.notQualified, reason: ca.reason);
    final cf = await candidate(_g7, f);
    expect((cf.status, cf.basisRound), (AralCandidateStatus.proposed, 'bosy'), reason: cf.reason);
    final cg = await candidate(_g2, g);
    expect((cg.status, cg.basisRound), (AralCandidateStatus.proposed, 'bosy'), reason: cg.reason);
  });

  test('basis round mosy, carried values (default): the latest MoSY that counts, best so far', () async {
    await basis('mosy');
    await valuesAral(null);
    // A: MOSY #1 carries BoSY's 90%: still not ARAL.
    final ca = await candidate(_g7, a);
    expect((ca.status, ca.basisRound), (AralCandidateStatus.notQualified, 'mosy1'), reason: ca.reason);
    expect(ca.reason, startsWith('Phil-IRI MOSY #1'));
    // F: MOSY #2 carries MOSY #1's 90%: improved, not proposed.
    final cf = await candidate(_g7, f);
    expect((cf.status, cf.basisRound), (AralCandidateStatus.notQualified, 'mosy2'), reason: cf.reason);
    // C: no MoSY: BoSY.
    final cc = await candidate(_g7, c);
    expect((cc.status, cc.basisRound), (AralCandidateStatus.proposed, 'bosy'), reason: cc.reason);
    expect(cc.basisAssessmentId, isNotNull);
  });

  test('basis round mosy, actual values: the latest MoSY reading itself', () async {
    await basis('mosy');
    await valuesAral('actual');
    final ca = await candidate(_g7, a);
    expect((ca.status, ca.basisRound), (AralCandidateStatus.proposed, 'mosy1'), reason: ca.reason);
    final cf = await candidate(_g7, f);
    expect((cf.status, cf.basisRound), (AralCandidateStatus.proposed, 'mosy2'), reason: cf.reason);
    expect(cf.basisAssessmentId, isNotNull);
    await valuesAral(null);
  });

  test('basis round mosy: CRLA MoSY for Grade 2, else BoSY', () async {
    await basis('mosy');
    // MoSY Transitioning: not ARAL while ks1_extended is off.
    final cg = await candidate(_g2, g);
    expect((cg.status, cg.basisRound), (AralCandidateStatus.notQualified, 'mosy'), reason: cg.reason);
    final ch = await candidate(_g2, h);
    expect((ch.status, ch.basisRound), (AralCandidateStatus.proposed, 'bosy'), reason: ch.reason);
  });
}
