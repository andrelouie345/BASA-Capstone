// ARAL memo settings, class size (plan docs/superpowers/plans/2026-11-18-aral-memo-a-settings.md,
// Task 4): a class holds at most the school's class_max_learners (default 15)
// active learners; a class over a lowered maximum and a class under the
// school's class_min_learners are coordinator notices; taking a learner out
// of a class keeps their attendance. Signed in offline as a coordinator; the
// settings are rows of the device's aral_settings mirror.
import 'dart:convert';
import 'dart:io';

import 'package:basa_capstone/core/data/local/local_database.dart';
import 'package:basa_capstone/core/models/aral_class.dart';
import 'package:basa_capstone/core/models/aral_enrollment.dart';
import 'package:basa_capstone/core/models/aral_session.dart';
import 'package:basa_capstone/core/wiring/app_context.dart';
import 'package:basa_capstone/core/wiring/wire_shared.dart';
import 'package:basa_capstone/core/wiring/wire_tutor.dart';
import 'package:basa_capstone/viewmodels/aral_class_viewmodel.dart';
import 'package:basa_capstone/viewmodels/aral_session_viewmodel.dart';
import 'package:basa_capstone/viewmodels/aral_viewmodel.dart';
import 'package:basa_capstone/viewmodels/reminder_viewmodel.dart';
import 'package:basa_capstone/viewmodels/viewmodel_exception.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../helpers/offline_owner.dart';

const _school = 9601;
const _year = '2026-2027';
const _coord = '00000000-0000-0000-0000-0000000096c1';
const _tutor = '00000000-0000-0000-0000-0000000096a1';

void main() {
  late Database db;
  late AralViewModel aral;
  late AralClassViewModel classes;
  late AralSessionViewModel sessions;
  late ReminderViewModel reminders;
  var nextStudent = 9601;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final ctx = await AppContext.open(dataDir: Directory.systemTemp.createTempSync('basa_class_size_').path);
    db = ctx.localDb;
    final t = wireTutor(ctx, wireShared(ctx));
    aral = t.aralVm;
    classes = t.aralClassVm;
    sessions = t.aralSessionVm;
    reminders = t.reminderVm;

    await db.insert('schools', {'id': _school, 'school_id': 'ZZCS1', 'school_name': 'ZZ Class Size'});
    await db.insert('users', {'id': _tutor, 'email': 'tutor96@zz', 'full_name': 'Tutor 96', 'role': 'tutor',
        'school_id': _school, 'is_active': 1});
    await db.insert('sections', {'id': 9601, 'school_id': _school, 'school_year': _year, 'grade_level': '7', 'section_name': 'S9601'});
    await seedOfflineOwner(db, userId: _coord, email: 'coord96@zz', role: 'coordinator', schoolId: _school);
    expect(await ctx.authVm.signInOffline(email: 'coord96@zz', password: 'test-pw'), isNull);
  });

  tearDownAll(LocalDatabase.close);

  Future<void> setting(Map<String, Object?>? school) async {
    await db.delete('aral_settings');
    if (school != null) await db.insert('aral_settings', {'id': 1, 'school_id': _school, 'settings': jsonEncode(school)});
  }

  Future<AralClass> newClass(String name) => classes.createClass(
      schoolId: _school, schoolYear: _year, className: name, gradeLevel: 7,
      program: AralClassProgram.ks3Basic, tutorId: _tutor);

  Future<AralEnrollment> learner() async {
    final id = nextStudent++;
    await db.insert('students', {'id': id, 'lrn': '99999996${id.toString().padLeft(4, '0')}', 'last_name': 'ZZS',
        'first_name': 'L$id', 'school_id': _school});
    await db.insert('enrollments', {'student_id': id, 'section_id': 9601, 'school_year': _year, 'status': 'active'});
    return aral.enroll(sectionId: 9601, schoolYear: _year, studentId: id, keyStage: AralKeyStage.ks3, track: AralTrack.basic);
  }

  Future<List<AralEnrollment>> fill(AralClass c, int n) async =>
      [for (var i = 0; i < n; i++) await classes.place((await learner()).id!, c.id!)];

  Future<List<AralClassNotice>> notices(AralClassNoticeKind kind) async =>
      (await reminders.coordinatorReminders(_school, _year)).single.aral.where((n) => n.kind == kind).toList();

  test("the school's maximum: the 11th placement is refused", () async {
    await setting({'class_max_learners': 10});
    expect(await classes.classMax(_school), 10);
    final c = await newClass('7-Ten');
    await fill(c, 10);
    final eleventh = await learner();
    await expectLater(
        classes.place(eleventh.id!, c.id!),
        throwsA(isA<ViewModelException>()
            .having((e) => e.message, 'message', 'Class "7-Ten" already has 10 active ARAL learners.')));
    await setting(null);
    expect(await classes.classMax(_school), 15);
    expect((await classes.place(eleventh.id!, c.id!)).classId, c.id);
  }, timeout: const Timeout(Duration(minutes: 3))); // many learners, one insert each

  test('a class over a lowered maximum is a notice; taking a learner out keeps their attendance', () async {
    await setting(null);
    final c = await newClass('7-Twelve');
    final placed = await fill(c, 12);
    expect(await notices(AralClassNoticeKind.overMax), isEmpty);
    await setting({'class_max_learners': 10});
    final over = (await notices(AralClassNoticeKind.overMax)).where((n) => n.aralClass?.id == c.id).toList();
    expect(over.map((n) => n.message), [
      'Class "7-Twelve" has 12 active learners, more than the maximum 10: '
          'move learners to another class. Their records stay.'
    ]);
    expect(over.single.aralClass?.id, c.id);

    final s = await sessions.logSession(classId: c.id!, heldOn: DateTime.now(), minutes: 45, setup: AralSetup.pullOut);
    await sessions.mark(s.id!, placed.first.id!, AralMark.present);
    final before = (await db.query('aral_attendance', where: 'enrollment_id = ?', whereArgs: [placed.first.id])).length;
    expect(before, 1);
    await classes.unplace(placed.first.id!);
    expect((await db.query('aral_attendance', where: 'enrollment_id = ?', whereArgs: [placed.first.id])).length, before);
  }, timeout: const Timeout(Duration(minutes: 3))); // many learners, one insert each

  test("a class under the school's minimum is a notice; minimum 0 = none", () async {
    await setting(null);
    final c = await newClass('7-Three');
    await fill(c, 3);
    await setting({'class_min_learners': 5});
    expect(await classes.classMin(_school), 5);
    final under = (await notices(AralClassNoticeKind.underMin)).where((n) => n.aralClass?.id == c.id).toList();
    expect(under.map((n) => n.message), [
      'Class "7-Three" has 3 active learners, fewer than 5: '
          'combine it with the nearest level of the same grade if there is one.'
    ]);
    await setting({'class_min_learners': 0});
    expect(await notices(AralClassNoticeKind.underMin), isEmpty);
    await setting(null);
    expect(await classes.classMin(_school), 0);
    expect(await notices(AralClassNoticeKind.underMin), isEmpty);
  }, timeout: const Timeout(Duration(minutes: 3))); // many learners, one insert each
}
