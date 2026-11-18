// ARAL memo settings, sessions (plan docs/superpowers/plans/2026-11-18-aral-memo-a-settings.md,
// Task 5): the school's weekdays-only rule and longest session, the sessions
// after which the two check-ins are due, and the sessions-a-week reminder
// (tutor and coordinator). Without a setting every rule is today's. Signed in
// offline as a coordinator; the settings are rows of the device's
// aral_settings mirror.
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

const _school = 9701;
const _year = '2026-2027';
const _coord = '00000000-0000-0000-0000-0000000097c1';
const _tutor = '00000000-0000-0000-0000-0000000097a1';

Matcher _refused(String text) =>
    throwsA(isA<ViewModelException>().having((e) => e.message, 'message', contains(text)));

void main() {
  late Database db;
  late AralViewModel aral;
  late AralClassViewModel classes;
  late AralSessionViewModel sessions;
  late ReminderViewModel reminders;
  var nextStudent = 9701;
  var nextClass = 1;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final ctx = await AppContext.open(dataDir: Directory.systemTemp.createTempSync('basa_session_rules_').path);
    db = ctx.localDb;
    final t = wireTutor(ctx, wireShared(ctx));
    aral = t.aralVm;
    classes = t.aralClassVm;
    sessions = t.aralSessionVm;
    reminders = t.reminderVm;

    await db.insert('schools', {'id': _school, 'school_id': 'ZZSR1', 'school_name': 'ZZ Session Rules'});
    await db.insert('users', {'id': _tutor, 'email': 'tutor97@zz', 'full_name': 'Tutor 97', 'role': 'tutor',
        'school_id': _school, 'is_active': 1});
    await db.insert('sections', {'id': 9701, 'school_id': _school, 'school_year': _year, 'grade_level': '7', 'section_name': 'S9701'});
    await seedOfflineOwner(db, userId: _coord, email: 'coord97@zz', role: 'coordinator', schoolId: _school);
    expect(await ctx.authVm.signInOffline(email: 'coord97@zz', password: 'test-pw'), isNull);
  });

  tearDownAll(LocalDatabase.close);

  Future<void> setting(Map<String, Object?>? school) async {
    await db.delete('aral_settings');
    if (school != null) await db.insert('aral_settings', {'id': 1, 'school_id': _school, 'settings': jsonEncode(school)});
  }

  /// A class with one active learner who entered ARAL on 1 September.
  Future<AralClass> newClass() async {
    final c = await classes.createClass(schoolId: _school, schoolYear: _year, className: 'C${nextClass++}',
        gradeLevel: 7, program: AralClassProgram.ks3Basic, tutorId: _tutor);
    final id = nextStudent++;
    await db.insert('students', {'id': id, 'lrn': '99999997${id.toString().padLeft(4, '0')}', 'last_name': 'ZZT',
        'first_name': 'L$id', 'school_id': _school});
    await db.insert('enrollments', {'student_id': id, 'section_id': 9701, 'school_year': _year, 'status': 'active'});
    final e = await aral.enroll(sectionId: 9701, schoolYear: _year, studentId: id,
        keyStage: AralKeyStage.ks3, track: AralTrack.basic);
    await db.update('aral_enrollments', {'entered_on': '2026-09-01'}, where: 'id = ?', whereArgs: [e.id]);
    await classes.place(e.id!, c.id!);
    return c;
  }

  Future<AralSession> log(AralClass c, DateTime on, {int minutes = 45, AralSetup setup = AralSetup.pullOut}) =>
      sessions.logSession(classId: c.id!, heldOn: on, minutes: minutes, setup: setup);

  test("absent settings keep today's rule", () async {
    await setting(null);
    final c = await newClass();
    await log(c, DateTime(2026, 11, 16), minutes: 61); // Monday
    expect(sessions.lastWarning, contains('60'));
    await log(c, DateTime(2026, 11, 14), minutes: 120, setup: AralSetup.weekend); // Saturday
    await expectLater(log(c, DateTime(2026, 11, 15), minutes: 121), _refused('1 to 120'));
  });

  test('weekdays only', () async {
    await setting({'sessions_weekdays_only': true});
    final c = await newClass();
    await expectLater(log(c, DateTime(2026, 11, 14)), _refused('Monday to Friday')); // Saturday
    await expectLater(log(c, DateTime(2026, 11, 16), setup: AralSetup.weekend), _refused('Monday to Friday'));
    final s = await log(c, DateTime(2026, 11, 16));
    // An edit follows the same rules.
    await expectLater(sessions.editSession(s.id!, heldOn: DateTime(2026, 11, 15)), _refused('Monday to Friday'));
    await expectLater(sessions.editSession(s.id!, setup: AralSetup.weekend), _refused('Monday to Friday'));
    await sessions.editSession(s.id!, heldOn: DateTime(2026, 11, 17));
  });

  test('maximum length', () async {
    await setting({'session_max_minutes': 60});
    final c = await newClass();
    await expectLater(log(c, DateTime(2026, 11, 16), minutes: 61), _refused('at most 60 minutes'));
    await expectLater(log(c, DateTime(2026, 11, 14), minutes: 90, setup: AralSetup.weekend), _refused('at most 60 minutes'));
    final s = await log(c, DateTime(2026, 11, 16), minutes: 60);
    expect(sessions.lastWarning, isNull);
    await expectLater(sessions.editSession(s.id!, minutes: 61), _refused('at most 60 minutes'));
  });

  test('check-ins follow the setting', () async {
    await setting({'checkin_after_sessions': [3, 5]});
    final c = await newClass();
    for (var d = 2; d <= 3; d++) {
      await log(c, DateTime(2026, 11, d));
      expect(sessions.lastWarning, isNull);
    }
    expect((await sessions.classSummary(c.id!)).nextCheckInAfter, 3);
    await log(c, DateTime(2026, 11, 4));
    expect(sessions.lastWarning, contains('session 3 done: the check-in assessment is due'));
    expect((await sessions.classSummary(c.id!)).nextCheckInAfter, 5);
    await log(c, DateTime(2026, 11, 5));
    expect(sessions.lastWarning, isNull);
    await log(c, DateTime(2026, 11, 6));
    expect(sessions.lastWarning, contains('session 5 done'));
    expect((await sessions.classSummary(c.id!)).nextCheckInAfter, isNull);
    // Without the setting, 16 and 32 as today.
    await setting(null);
    expect((await sessions.classSummary(c.id!)).nextCheckInAfter, 16);
  });

  test('fewer sessions this week: tutor and coordinator reminders from Wednesday', () async {
    await setting({'class_min_sessions_per_week': 3});
    final c = await newClass();
    await log(c, DateTime(2026, 11, 9)); // Monday
    Future<List<String>> tutorLines(DateTime today) async => [
          for (final r in (await reminders.tutorReminders(_tutor, _year, today: today)).reminders)
            if (r.kind == TutorReminderKind.fewSessionsThisWeek && r.aralClass?.id == c.id) r.message
        ];
    Future<List<String>> coordLines(DateTime today) async => [
          for (final n in (await reminders.coordinatorReminders(_school, _year, today: today)).single.aral)
            if (n.kind == AralClassNoticeKind.fewSessionsThisWeek && n.aralClass?.id == c.id) n.message
        ];
    const line = 'Class "C5" has 1 session this week; the school asks for at least 3.';
    expect(c.className, 'C5');
    expect(await tutorLines(DateTime(2026, 11, 11)), [line]); // Wednesday
    expect(await coordLines(DateTime(2026, 11, 11)), [line]);
    expect(await tutorLines(DateTime(2026, 11, 10)), isEmpty); // Tuesday: too early to say
    expect(await coordLines(DateTime(2026, 11, 10)), isEmpty);
    await log(c, DateTime(2026, 11, 10));
    await log(c, DateTime(2026, 11, 11));
    expect(await tutorLines(DateTime(2026, 11, 11)), isEmpty); // 3 held
    await setting({'class_min_sessions_per_week': 0});
    expect(await tutorLines(DateTime(2026, 11, 13)), isEmpty);
    await setting(null);
    expect(await coordLines(DateTime(2026, 11, 13)), isEmpty);
  });
}
