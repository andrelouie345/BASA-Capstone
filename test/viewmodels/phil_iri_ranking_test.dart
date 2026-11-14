// The Phil-IRI ranking list (spec docs/superpowers/specs/2026-11-14-phil-iri-value-sources-design.md,
// D9, D10, D12): the lowest N learners by one measure in one round, values
// from values_ranking (default actual); learners without a value for the
// measure go in a second block with a reason.
//
// School 1, 2026-2027. MOSY 1 readings (one minute, 120 words), comprehension /10:
//   section 71 (G7): r1 3 (6 miscues), r2 4 (2 miscues), r6 silent 7 (120 words in 60 s),
//                    r8 BOSY 2 only (no MOSY 1 reading)
//   section 72 (G7): r3 4 (0 miscues), r4 5 (3 miscues), r7 imported comprehension only 6/10
//   section 81 (G8): r5 6 (1 miscue)
import 'dart:convert';
import 'dart:io';

import 'package:basa_capstone/core/models/phil_iri_assessment.dart' show PhilIriRound;
import 'package:basa_capstone/core/models/phil_iri_miscue.dart' show PhilIriMiscueType;
import 'package:basa_capstone/core/models/phil_iri_reading.dart' show PhilIriReadingMethod;
import 'package:basa_capstone/core/models/report_setting.dart';
import 'package:basa_capstone/core/services/auth_messages.dart';
import 'package:basa_capstone/core/wiring/app_context.dart';
import 'package:basa_capstone/core/wiring/wire_admin.dart';
import 'package:basa_capstone/core/wiring/wire_shared.dart';
import 'package:basa_capstone/core/wiring/wire_tutor.dart';
import 'package:basa_capstone/viewmodels/phil_iri_ranking_viewmodel.dart';
import 'package:basa_capstone/viewmodels/viewmodel_exception.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../helpers/offline_owner.dart';

const _year = '2026-2027';
const r1 = 901, r2 = 902, r3 = 903, r4 = 904, r5 = 905, r6 = 906, r7 = 907, r8 = 908;
const mosy1 = PhilIriRound.mosy1;
const _comp = PhilIriRankMeasure.comprehension, _acc = PhilIriRankMeasure.accuracy, _wpm = PhilIriRankMeasure.wpm;

Matcher _refused(String message) =>
    throwsA(isA<ViewModelException>().having((e) => e.message, 'message', message));

void main() {
  late AppContext ctx;
  late PhilIriRankingViewModel vm;

  Future<void> rankingValues(PhilIriValues? v) async {
    await ctx.localDb.delete('report_settings');
    if (v == null) return;
    await ctx.localDb.insert('report_settings',
        {'id': 1, 'school_id': 1, 'settings': jsonEncode({PhilIriValueList.ranking.key: v.name})});
  }

  Future<PhilIriRanking> rank(PhilIriRankMeasure m,
          {int n = 10, int? sectionId, int? grade, PhilIriRound round = mosy1}) =>
      vm.rank(schoolId: 1, schoolYear: _year, round: round, measure: m, n: n, sectionId: sectionId, grade: grade);

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    ctx = await AppContext.open(dataDir: Directory.systemTemp.createTempSync('basa_pi_ranking_').path);
    final s = wireShared(ctx);
    final t = wireTutor(ctx, s);
    vm = (await wireAdmin(ctx, s, t)).philIriRankingVm;
    final db = ctx.localDb;
    await db.insert('schools', {'id': 1, 'school_id': 'ZZ46', 'school_name': 'ZZ ranking'});
    await seedOfflineOwner(db,
        userId: '00000000-0000-0000-0000-00000000ab46', email: 'rank@test', role: 'coordinator', schoolId: 1);
    for (final (id, grade) in [(71, '7'), (72, '7'), (81, '8')]) {
      await db.insert('sections', {'id': id, 'school_id': 1, 'school_year': _year, 'grade_level': grade, 'section_name': 'S$id'});
    }
    // Names: r1 Abad, r2 Cruz, r3 Bautista (ties with r2 at 40%: Bautista first), ...
    const names = {r1: 'Abad', r2: 'Cruz', r3: 'Bautista', r4: 'Diaz', r5: 'Estrada', r6: 'Flores', r7: 'Garcia', r8: 'Hernandez'};
    const sectionOf = {r1: 71, r2: 71, r6: 71, r8: 71, r3: 72, r4: 72, r7: 72, r5: 81};
    for (final e in sectionOf.entries) {
      await db.insert('students', {'id': e.key, 'lrn': '99999999${e.key}', 'last_name': names[e.key], 'first_name': 'Ana',
          'school_id': 1, 'sex': 'F'});
      await db.insert('enrollments', {'student_id': e.key, 'section_id': e.value, 'school_year': _year, 'status': 'active'});
    }
    await db.insert('phil_iri_collections', {'id': 1, 'name': 'Graded ranking', 'is_grade_leveled': 1});
    for (final (id, level) in [(601, 7), (602, 7), (603, 8)]) {
      await db.insert('phil_iri_passages', {
        'id': id, 'collection_id': 1, 'level': level, 'title': 'P$id',
        'body': List.filled(120, 'w$id').join(' '), 'word_count': 120, 'is_active': 1,
      });
      for (var q = 1; q <= 10; q++) {
        await db.insert('phil_iri_questions',
            {'id': id * 100 + q, 'passage_id': id, 'question_no': q, 'prompt': 'Q$q', 'choices': '["a","b"]', 'answer_key': 'a'});
      }
    }
    expect(await ctx.authVm.signInOffline(email: 'rank@test', password: 'test-pw'), isNull);

    final pi = t.philIriVm;
    Future<void> read(int student, int section, PhilIriRound round, int passage, int correct,
        {int miscues = 0, bool silent = false}) async {
      final s = await pi.startSession(studentId: student, sectionId: section, schoolYear: _year, round: round,
          assessedAt: round == PhilIriRound.bosy ? DateTime(2026, 8, 5) : DateTime(2026, 9, 5));
      final r = silent
          ? await pi.startReading(
              assessmentId: s.id!, passageId: passage, method: PhilIriReadingMethod.silent, readingSeconds: 60)
          : await pi.startReading(
              assessmentId: s.id!, passageId: passage, method: PhilIriReadingMethod.oneMinute, wordsRead: 120);
      for (var i = 0; i < miscues; i++) {
        await pi.markMiscue(readingId: r.id!, wordIndex: i, type: PhilIriMiscueType.omission);
      }
      for (var q = 1; q <= 10; q++) {
        await pi.answer(readingId: r.id!, questionId: passage * 100 + q, chosen: q <= correct ? 'a' : 'b');
      }
      await pi.complete(s.id!);
    }

    await read(r1, 71, mosy1, 601, 3, miscues: 6);
    await read(r2, 71, mosy1, 601, 4, miscues: 2);
    await read(r3, 72, mosy1, 601, 4);
    await read(r4, 72, mosy1, 601, 5, miscues: 3);
    await read(r5, 81, mosy1, 603, 6, miscues: 1);
    await read(r6, 71, mosy1, 601, 7, silent: true);
    await read(r8, 71, PhilIriRound.bosy, 602, 2);
    // r7: a workbook import with comprehension only (no word reading).
    Future<int> localId() async => -(await db.rawInsert("INSERT INTO local_ids (made_at) VALUES (datetime('now'))"));
    final session = await localId();
    await db.insert('phil_iri_assessments', {
      'id': session, 'student_id': r7, 'school_id': 1, 'section_id': 72, 'school_year': _year,
      'round': 'mosy1', 'assessed_at': '2026-09-05', 'import_source': 'workbook',
    });
    await db.insert('phil_iri_readings', {
      'id': await localId(), 'assessment_id': session, 'sequence_no': 1, 'passage_id': null,
      'method': 'whole_text', 'imported_correct': 6, 'imported_total': 10,
    });
    await db.update('phil_iri_assessments', {'status': 'completed'}, where: 'id = ?', whereArgs: [session]);
  });

  setUp(() => rankingValues(null));

  test('no settings row: actual values (Review Focus 3)', () async {
    final r = await rank(_comp, grade: 7);
    expect(r.values, PhilIriValues.actual);
  });

  test('comprehension, n=2, Grade 7: ties share a rank and are all kept', () async {
    final r = await rank(_comp, n: 2, grade: 7);
    expect([for (final x in r.ranked) (x.student.id, x.rank)], [(r1, 1), (r3, 2), (r2, 2)]);
    expect(r.ranked.first.value, 0.3);
    expect(r.ranked.first.section.id, 71);
    expect(r.ranked.first.grade, 7);
    expect(r.ranked.first.profile, isNotNull);
    expect(r.tiedPastN, isTrue);
    expect([for (final x in r.unranked) (x.student.id, x.reason)], [(r8, PhilIriRankReason.notAssessedThisRound)]);
    expect((r.round, r.measure, r.n, r.grade, r.sectionId, r.schoolId, r.schoolYear), (mosy1, _comp, 2, 7, null, 1, _year));
  });

  test('accuracy and wpm: silent-only and comprehension-only learners are not ranked', () async {
    for (final values in [null, PhilIriValues.carried]) {
      await rankingValues(values);
      final acc = await rank(_acc, grade: 7);
      final reasons = {for (final x in acc.unranked) x.student.id: x.reason};
      expect(reasons[r6], PhilIriRankReason.silentNoAccuracy, reason: '$values');
      expect(reasons[r7], PhilIriRankReason.comprehensionOnly, reason: '$values');
    }
    await rankingValues(null);
    final acc = await rank(_acc, grade: 7);
    expect([for (final x in acc.ranked) x.student.id], [r1, r4, r2, r3]); // 95%, 97.5%, 98.3%, 100%
    final wpm = await rank(_wpm, grade: 7);
    expect({for (final x in wpm.unranked) x.student.id: x.reason},
        {r7: PhilIriRankReason.comprehensionOnly, r8: PhilIriRankReason.notAssessedThisRound});
    expect(wpm.ranked.map((x) => x.student.id), containsAll([r1, r2, r3, r4, r6])); // silent wpm is measured
  });

  test('MOSY 1: actual = not assessed this round; carried ranks the carried value', () async {
    final actual = await rank(_comp, grade: 7);
    expect(actual.unranked.single.reason, PhilIriRankReason.notAssessedThisRound);
    await rankingValues(PhilIriValues.carried);
    final carried = await rank(_comp, n: 1, grade: 7);
    expect(carried.values, PhilIriValues.carried);
    expect([for (final x in carried.ranked) (x.student.id, x.rank, x.value)], [(r8, 1, 0.2)]);
    expect(carried.unranked, isEmpty);
  });

  test('scope: whole school includes Grade 8; a section only its own learners', () async {
    final school = await rank(_comp);
    expect(school.ranked.map((x) => x.student.id), contains(r5));
    expect(school.ranked.firstWhere((x) => x.student.id == r5).grade, 8);
    final section = await rank(_comp, sectionId: 72);
    expect([for (final x in section.ranked) x.student.id], [r3, r4, r7]);
    expect(section.unranked, isEmpty);
  });

  test('n larger than the valued learners: everyone ranked, not tied past n (Review Focus 5)', () async {
    final r = await rank(_comp, n: 50);
    expect(r.ranked.length, 7);
    expect(r.tiedPastN, isFalse);
  });

  test('CSV: header, a ranked row, a not-ranked row', () async {
    final lines = philIriRankingCsv(await rank(_comp, n: 2, grade: 7)).replaceFirst('﻿', '').trim().split(RegExp(r'\r?\n'));
    expect(lines.first, 'Rank,LRN,Learner,Sex,Grade,Section,Comprehension %,Profile,Reason,Values');
    expect(lines[1], startsWith('1,99999999901,"Abad, Ana",F,7,S71,30.0,'));
    expect(lines[1], endsWith(',,actual'));
    expect(lines.last, ',99999999908,"Hernandez, Ana",F,7,S71,,,not assessed this round,actual');
    expect(lines.length, 5); // header, 3 ranked, 1 not ranked
  });

  test('refusals', () async {
    await expectLater(rank(_comp, n: 0), _refused('Learners to list is at least 1 (got 0).'));
    await expectLater(rank(_comp, sectionId: 71, grade: 7), _refused('Give a section or a grade, not both.'));
    await expectLater(rank(_comp, grade: 3), _refused('School 1 has no Grade 3 section for $_year.'));
    await expectLater(rank(_comp, grade: 9), _refused('School 1 has no Grade 9 section for $_year.'));
  });

  test('a tutor is refused; signed out is refused', () async {
    await seedOfflineOwner(ctx.localDb,
        userId: '00000000-0000-0000-0000-00000000ab47', email: 'tut@test', role: 'tutor', schoolId: 1);
    expect(await ctx.authVm.signInOffline(email: 'tut@test', password: 'test-pw'), isNull);
    await expectLater(rank(_comp), _refused('Forbidden: only an admin or coordinator can generate the Phil-IRI ranking.'));
    await ctx.authVm.signOut();
    await expectLater(rank(_comp), _refused(notSignedInMessage));
  });
}
