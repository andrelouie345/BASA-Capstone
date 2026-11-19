// ARAL memo settings, IRIP cycle length (plan docs/superpowers/plans/2026-11-18-aral-memo-a-settings.md,
// Task 7): a cycle has the school's irip_weeks (default 8). A strand's cycle
// length is the larger of the setting and its highest saved week, so a cycle
// already past a lowered length is not stranded: it is done once its last
// saved week is rated. Signed in offline as a coordinator; the settings are
// rows of the device's aral_settings mirror.
import 'dart:convert';
import 'dart:io';

import 'package:basa_capstone/core/data/local/local_database.dart';
import 'package:basa_capstone/core/models/aral_enrollment.dart';
import 'package:basa_capstone/core/models/aral_irip.dart';
import 'package:basa_capstone/core/wiring/app_context.dart';
import 'package:basa_capstone/core/wiring/wire_shared.dart';
import 'package:basa_capstone/core/wiring/wire_tutor.dart';
import 'package:basa_capstone/viewmodels/aral_irip_viewmodel.dart';
import 'package:basa_capstone/viewmodels/aral_viewmodel.dart';
import 'package:basa_capstone/viewmodels/viewmodel_exception.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../helpers/offline_owner.dart';

const _school = 9801;
const _year = '2026-2027';
const _coord = '00000000-0000-0000-0000-0000000098c1';

void main() {
  late Database db;
  late AralViewModel aral;
  late AralIripViewModel irip;
  var nextStudent = 9801;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final ctx = await AppContext.open(dataDir: Directory.systemTemp.createTempSync('basa_irip_weeks_').path);
    db = ctx.localDb;
    final t = wireTutor(ctx, wireShared(ctx));
    aral = t.aralVm;
    irip = t.aralIripVm;
    await db.insert('schools', {'id': _school, 'school_id': 'ZZIW1', 'school_name': 'ZZ IRIP Weeks'});
    await db.insert('sections', {'id': 9801, 'school_id': _school, 'school_year': _year, 'grade_level': '7', 'section_name': 'S9801'});
    var id = 9800;
    for (final strand in ['filipino', 'english']) {
      for (var seq = 1; seq <= 3; seq++) {
        await db.insert('aral_irip_targets',
            {'id': id++, 'program': 'basic_ks23', 'strand': strand, 'seq': seq, 'focus': '$strand $seq'});
      }
    }
    await seedOfflineOwner(db, userId: _coord, email: 'coord98@zz', role: 'coordinator', schoolId: _school);
    expect(await ctx.authVm.signInOffline(email: 'coord98@zz', password: 'test-pw'), isNull);
  });

  tearDownAll(LocalDatabase.close);

  Future<void> setting(int? weeks) async {
    await db.delete('aral_settings');
    if (weeks != null) {
      await db.insert('aral_settings', {'id': 1, 'school_id': _school, 'settings': jsonEncode({'irip_weeks': weeks})});
    }
  }

  Future<int> learner() async {
    final id = nextStudent++;
    await db.insert('students', {'id': id, 'lrn': '99999998${id.toString().padLeft(4, '0')}', 'last_name': 'ZZI',
        'first_name': 'L$id', 'school_id': _school});
    await db.insert('enrollments', {'student_id': id, 'section_id': 9801, 'school_year': _year, 'status': 'active'});
    final e = await aral.enroll(sectionId: 9801, schoolYear: _year, studentId: id,
        keyStage: AralKeyStage.ks3, track: AralTrack.basic);
    return e.id!;
  }

  /// Rates the latest week of every strand (partial: the same target again).
  Future<void> rateAll(int e) async {
    for (final s in (await irip.plan(e)).strands) {
      if (s.awaitingRating) await irip.rate(s.latest!.id!, AralIripStatus.partial);
    }
  }

  /// Starts a cycle and runs it to week [upTo], every week rated.
  Future<void> runTo(int e, int upTo) async {
    await irip.startCycle(e);
    await rateAll(e);
    for (var w = 2; w <= upTo; w++) {
      await irip.nextWeek(e);
      await rateAll(e);
    }
  }

  Matcher refused(String text) =>
      throwsA(isA<ViewModelException>().having((x) => x.message, 'message', contains(text)));

  test('the school sets 6 weeks: done after week 6, no week 7', () async {
    await setting(6);
    final e = await learner();
    await runTo(e, 5);
    expect((await irip.plan(e)).cycleDone, isFalse);
    await irip.nextWeek(e);
    await rateAll(e);
    final p = await irip.plan(e);
    expect(p.cycleDone, isTrue);
    expect(p.strands.map((s) => s.cycleLength), [6, 6]);
    await expectLater(irip.nextWeek(e), refused('the cycle has 6 weeks'));
    await irip.startCycle(e); // the next cycle may start
    expect((await irip.plan(e)).currentCycle, 2);
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('no setting: 8 weeks as today', () async {
    await setting(null);
    final e = await learner();
    await runTo(e, 7);
    expect((await irip.plan(e)).cycleDone, isFalse);
    await expectLater(irip.startCycle(e), refused('rate week 8 of every strand'));
    await irip.nextWeek(e);
    await rateAll(e);
    expect((await irip.plan(e)).cycleDone, isTrue);
    await expectLater(irip.nextWeek(e), refused('the cycle has 8 weeks'));
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('a cycle already at week 8 when the school lowers it to 6 is done once week 8 is rated', () async {
    await setting(null);
    final e = await learner();
    await runTo(e, 7);
    await irip.nextWeek(e); // week 8, not rated yet
    await setting(6);
    var p = await irip.plan(e);
    expect(p.strands.map((s) => s.cycleLength), [8, 8]);
    expect(p.cycleDone, isFalse);
    await rateAll(e);
    p = await irip.plan(e);
    expect(p.cycleDone, isTrue);
    expect(p.canStartCycle, isTrue);
    expect(await db.query('aral_irip_weeks', where: 'enrollment_id = ? AND week_no = 8', whereArgs: [e]), hasLength(2));
  }, timeout: const Timeout(Duration(minutes: 3)));
}
