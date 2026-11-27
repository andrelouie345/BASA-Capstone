// ARAL class learners with no improvement (spec
// docs/superpowers/specs/2026-11-27-aral-effectiveness-design.md D2, D6):
// AralClassViewModel.noImprovement and classProgress(atRound:).
import 'dart:io';

import 'package:basa_capstone/core/models/aral_progress.dart';
import 'package:basa_capstone/core/wiring/app_context.dart';
import 'package:basa_capstone/core/wiring/wire_shared.dart';
import 'package:basa_capstone/core/wiring/wire_tutor.dart';
import 'package:basa_capstone/viewmodels/viewmodel_exception.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../helpers/offline_owner.dart';

const _year = '2026-2027';
const _asOf = '2026-11-27';
const _class = 1;
const _oldClass = 2;
const _tutor = '00000000-0000-0000-0000-0000000000t1';
const _otherTutor = '00000000-0000-0000-0000-0000000000t2';
const _round = '2026-10-05'; // the MOSY assessment date

void main() {
  late AppContext ctx;
  late TutorVms t;
  late Database db;

  Future<Map<int, AralNoImprovement>> flagged() async =>
      {for (final f in await t.aralClassVm.noImprovement(_class, asOf: _asOf)) f.progress.enrollment.studentId: f};

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    ctx = await AppContext.open(dataDir: Directory.systemTemp.createTempSync('basa_aral_no_impr_').path);
    t = wireTutor(ctx, wireShared(ctx));
    db = ctx.localDb;
    await db.insert('schools', {'id': 1, 'school_id': 'ZZNI1', 'school_name': 'ZZ No Improvement', 'region_id': 13});
    for (final (id, grade) in [(71, '2'), (72, '7')]) {
      await db.insert('sections', {'id': id, 'school_id': 1, 'school_year': _year, 'grade_level': grade, 'section_name': 'S$id'});
    }
    for (final u in [_tutor, _otherTutor]) {
      await db.insert('users', {'id': u, 'email': '$u@test', 'full_name': 'Tutor', 'role': 'tutor', 'school_id': 1, 'is_active': 1});
    }
    for (final (id, tutor) in [(_class, _tutor), (_oldClass, _otherTutor)]) {
      await db.insert('aral_classes', {'id': id, 'school_id': 1, 'school_year': _year, 'class_name': 'ARAL-R-G2-0$id',
          'grade_level': 2, 'tutor_id': tutor, 'origin': 'cloud', 'row_version': 1});
    }
    // 1-8 Grade 2 (CRLA, KS1); 9-10 Grade 7 (Phil-IRI, KS3 Basic: check-ins).
    int section(int s) => s >= 9 ? 72 : 71;
    for (var s = 1; s <= 10; s++) {
      await db.insert('students', {'id': s, 'lrn': '9998000000${s.toString().padLeft(2, '0')}',
          'last_name': 'N${s.toString().padLeft(2, '0')}', 'first_name': 'F', 'school_id': 1});
      await db.insert('enrollments', {'student_id': s, 'section_id': section(s), 'school_year': _year, 'status': 'active'});
      final exited = s == 7;
      await db.insert('aral_enrollments', {
        'id': s, 'student_id': s, 'school_id': 1, 'section_id': section(s), 'school_year': _year,
        'key_stage': s >= 9 ? 'ks3' : 'ks1', 'track': s >= 9 ? 'basic' : null, 'class_id': _class,
        'status': exited ? 'exited' : 'active', 'entered_on': '2026-07-01',
        'exited_on': exited ? '2026-11-01' : null, 'exit_reason': exited ? 'other' : null,
        'basis_source': s >= 9 ? 'phil_iri' : 'crla', 'basis_round': 'bosy', 'basis_level': 'x',
        'origin': 'cloud', 'row_version': 1,
      });
    }

    // CRLA (Filipino, the Grade 2 language): BOSY then MOSY on [_round].
    var id = 100;
    Future<void> crla(int s, String round, String day, String profile) => db.insert('crla_assessments', {
          'id': ++id, 'student_id': s, 'school_id': 1, 'section_id': 71, 'school_year': _year,
          'subject_variant': 'fil', 'language': 'Tagalog', 'round': round, 'attempt_no': round == 'bosy' ? 1 : 2,
          'assessed_at': day, 'origin': 'cloud', 'row_version': 1, 'reading_profile': profile,
        });
    for (final s in [1, 2, 3, 4, 5, 6, 7, 8]) {
      await crla(s, 'bosy', '2026-08-03', 'High Emerging Reader');
      if (s == 6) continue; // not assessed yet
      await crla(s, 'mosy', _round, s == 5 ? 'Developing Reader' : 'High Emerging Reader');
    }

    // Sessions: 20 in this class (Aug 1 - Sep 30 and two after the round), 10 in
    // the old class (learner 8 sat there first).
    var sessionId = 1000;
    final classSessions = <int, String>{};
    Future<int> session(int classId, String day) async {
      final sid = ++sessionId;
      await db.insert('aral_sessions', {'id': sid, 'tutor_id': classId == _class ? _tutor : _otherTutor, 'school_id': 1,
          'school_year': _year, 'session_no': sid - 1000, 'held_on': day, 'minutes': 60, 'setup': 'pull_out',
          'class_id': classId, 'origin': 'cloud', 'row_version': 1});
      return sid;
    }

    for (var i = 0; i < 18; i++) {
      final day = DateTime(2026, 8, 1).add(Duration(days: i * 3));
      classSessions[await session(_class, day.toIso8601String().substring(0, 10))] = 'before';
    }
    for (final day in ['2026-10-10', '2026-10-12']) {
      classSessions[await session(_class, day)] = 'after';
    }
    final oldSessions = [for (var i = 0; i < 10; i++) await session(_oldClass, '2026-07-${(10 + i).toString()}')];
    var markId = 5000;
    Future<void> mark(int session, int enrollment, String m) => db.insert('aral_attendance',
        {'id': ++markId, 'session_id': session, 'enrollment_id': enrollment, 'mark': m, 'row_version': 1});
    final before = [for (final e in classSessions.entries) if (e.value == 'before') e.key];
    final after = [for (final e in classSessions.entries) if (e.value == 'after') e.key];
    // 1, 5, 6, 7, 9, 10: 16 present before the round.
    for (final s in [1, 5, 6, 7, 9, 10]) {
      for (final sid in before.take(16)) {
        await mark(sid, s, 'present');
      }
    }
    // 2: 15 present.
    for (final sid in before.take(15)) {
      await mark(sid, 2, 'present');
    }
    // 3: 14 present before + 2 after the round.
    for (final sid in [...before.take(14), ...after]) {
      await mark(sid, 3, 'present');
    }
    // 4: 15 present + 1 excused.
    for (final (i, sid) in before.take(16).indexed) {
      await mark(sid, 4, i == 0 ? 'excused' : 'present');
    }
    // 8: 10 present in the old class + 6 in this one.
    for (final sid in [...oldSessions, ...before.take(6)]) {
      await mark(sid, 8, 'present');
    }

    // Check-ins (KS3 Basic, after session 16): two items. 9 failed complete
    // (0/2), 10 failed incomplete (one answer, wrong).
    await db.insert('aral_checkin_tools', {'id': 1, 'key_stage': 'ks3', 'track': 'basic', 'checkpoint': 16,
        'language': 'english', 'title': 'ZZ check-in 16'});
    for (final item in [1, 2]) {
      await db.insert('aral_checkin_items', {'id': item, 'tool_id': 1, 'item_no': item, 'kind': 'open', 'prompt': 'Read.'});
    }
    for (final (cid, enrollment, answers) in [(1, 9, [1, 2]), (2, 10, [1])]) {
      await db.insert('aral_checkins', {'id': cid, 'enrollment_id': enrollment, 'tool_id': 1, 'attempt_no': 1,
          'taken_on': '2026-10-01', 'origin': 'cloud', 'row_version': 1});
      for (final item in answers) {
        await db.insert('aral_checkin_answers',
            {'id': cid * 10 + item, 'checkin_id': cid, 'item_id': item, 'is_correct': 0, 'row_version': 1});
      }
    }

    await seedOfflineOwner(db, userId: '00000000-0000-0000-0000-0000000000ni', email: 'ni@test', role: 'coordinator',
        schoolId: 1);
    expect(await ctx.authVm.signInOffline(email: 'ni@test', password: 'test-pw'), isNull);
  });

  test('same after 16 attended', () async {
    final f = (await flagged())[1]!;
    expect(f.reasons.map((r) => r.message), ['Same since BOSY: High Emerging Reader -> High Emerging Reader (MOSY)']);
    expect(f.progress.latestAssessedOn, _round);
  });

  test('same after 15 attended is not flagged', () async => expect((await flagged()).containsKey(2), isFalse));

  test('attendance after the round not counted', () async => expect((await flagged()).containsKey(3), isFalse));

  test('absent and excused do not count', () async => expect((await flagged()).containsKey(4), isFalse));

  test('up, not assessed yet and exited learners are not flagged', () async {
    final f = await flagged();
    expect([5, 6, 7].where(f.containsKey), isEmpty);
  });

  test('moved learner appears once; sessions in the old class count', () async {
    final f = await t.aralClassVm.noImprovement(_class, asOf: _asOf);
    expect(f.where((x) => x.progress.enrollment.studentId == 8).length, 1);
    final rows = await t.aralClassVm.classProgress(_class, asOf: _asOf);
    expect(rows.where((p) => p.enrollment.studentId == 8).length, 1);
  });

  test('failed complete check-in flags; incomplete is ignored', () async {
    final f = await flagged();
    expect(f[9]!.reasons.map((r) => (r.kind, r.message)),
        [(AralNoImprovementKind.checkin, 'Check-in after session 16: 0%, pass mark 75%')]);
    expect(f.containsKey(10), isFalse);
  });

  test('by name', () async {
    expect((await flagged()).keys.toList(), [1, 8, 9]);
  });

  test('atRound picks that round; not after the start = not assessed yet', () async {
    final at = {
      for (final p in await t.aralClassVm.classProgress(_class, asOf: _asOf, atRound: 'mosy')) p.enrollment.studentId: p
    };
    expect((at[5]!.latestRound, at[5]!.change), ('mosy', AralProgressChange.up));
    expect(at[6]!.change, AralProgressChange.notAssessedYet);
    final atBosy = await t.aralClassVm.classProgress(_class, asOf: _asOf, atRound: 'bosy');
    expect(atBosy.map((p) => p.change).toSet(), {AralProgressChange.notAssessedYet, AralProgressChange.noStartingResult});
    // A Phil-IRI round name on a CRLA row: not assessed yet.
    final atMosy1 = await t.aralClassVm.classProgress(_class, asOf: _asOf, atRound: 'mosy1');
    expect(atMosy1.firstWhere((p) => p.enrollment.studentId == 5).change, AralProgressChange.notAssessedYet);
  });

  test('without atRound the latest round is used (unchanged)', () async {
    final rows = await t.aralClassVm.classProgress(_class, asOf: _asOf);
    expect(rows.firstWhere((p) => p.enrollment.studentId == 5).latestRound, 'mosy');
  });

  test('tutor of another class refused', () async {
    await ctx.authVm.signOut();
    await seedOfflineOwner(db, userId: _otherTutor, email: '$_otherTutor@test', role: 'tutor', schoolId: 1);
    expect(await ctx.authVm.signInOffline(email: '$_otherTutor@test', password: 'test-pw'), isNull);
    await expectLater(t.aralClassVm.noImprovement(_class, asOf: _asOf),
        throwsA(isA<ViewModelException>().having((e) => e.message, 'message', 'This ARAL class is not one of your classes.')));
  });
}
