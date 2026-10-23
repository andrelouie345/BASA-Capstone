// ARAL sessions per class (spec decision 6 and 8), signed in offline: a tutor
// logs for their own classes, the default sheet is the class's active
// learners, numbering and check-in timing count per class, the class summary,
// and a moved learner's earlier marks.
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
import 'package:basa_capstone/viewmodels/viewmodel_exception.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../helpers/offline_owner.dart';

const _school = 9701;
const _year = '2026-2027';
const _coord = '00000000-0000-0000-0000-0000000097c1';
const _t1 = '00000000-0000-0000-0000-0000000097a1';
const _t2 = '00000000-0000-0000-0000-0000000097a2';

Matcher _refused(String message) =>
    throwsA(isA<ViewModelException>().having((e) => e.message, 'message', message));

void main() {
  late AppContext ctx;
  late AralViewModel aral;
  late AralClassViewModel classes;
  late AralSessionViewModel sessions;
  late AralClass a, b, c;
  final roster = <int, AralEnrollment>{}; // by student id

  Future<void> signInAs(String id, String email, String role) async {
    await seedOfflineOwner(ctx.localDb, userId: id, email: email, role: role, schoolId: _school);
    expect(await ctx.authVm.signInOffline(email: email, password: 'test-pw'), isNull);
  }

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    ctx = await AppContext.open(dataDir: Directory.systemTemp.createTempSync('basa_class_sessions_').path);
    final t = wireTutor(ctx, wireShared(ctx));
    aral = t.aralVm;
    classes = t.aralClassVm;
    sessions = t.aralSessionVm;
    final db = ctx.localDb;

    await db.insert('schools', {'id': _school, 'school_id': 'ZZS1', 'school_name': 'ZZ Class Sessions'});
    for (final (id, email) in [(_t1, 'one@zz'), (_t2, 'two@zz')]) {
      await db.insert('users', {'id': id, 'email': email, 'full_name': 'Tutor $email', 'role': 'tutor', 'school_id': _school});
    }
    await db.insert('sections', {'id': 9701, 'school_id': _school, 'school_year': _year, 'grade_level': '7', 'section_name': 'S7'});
    for (var i = 1; i <= 6; i++) {
      await db.insert('students', {'id': 9700 + i, 'lrn': '99999997000$i', 'last_name': 'ZZS', 'first_name': 'L$i',
          'school_id': _school});
      await db.insert('enrollments', {'student_id': 9700 + i, 'section_id': 9701, 'school_year': _year, 'status': 'active'});
    }

    await signInAs(_coord, 'coord@zz', 'coordinator');
    classFor(String name, String? tutor) => classes.createClass(schoolId: _school, schoolYear: _year, className: name,
        program: AralClassProgram.ks3Basic, gradeBand: AralGradeBand.g7to10, tutorId: tutor);
    a = await classFor('7-A', _t1);
    b = await classFor('7-B', _t1);
    c = await classFor('7-C', _t2);
    for (var i = 1; i <= 6; i++) {
      roster[9700 + i] = await aral.enroll(sectionId: 9701, schoolYear: _year, studentId: 9700 + i,
          keyStage: AralKeyStage.ks3, track: AralTrack.basic, enteredOn: DateTime(2026, 8, 1));
    }
    for (final s in [9701, 9702, 9703, 9704]) {
      await classes.place(roster[s]!.id!, a.id!);
    }
    await classes.place(roster[9705]!.id!, b.id!);
    // 9704 left before the sessions; 9706 waits for a class.
    await aral.exit(roster[9704]!.id!, AralExitReason.other, on: DateTime(2026, 8, 1));
  });

  tearDownAll(LocalDatabase.close);

  test('a tutor logs sessions for their own classes only', () async {
    await signInAs(_t1, 'one@zz', 'tutor');
    final s = await sessions.logSession(classId: a.id!, heldOn: DateTime(2026, 8, 3), minutes: 45, setup: AralSetup.pullOut);
    expect(s.classId, a.id);
    expect(s.tutorId, _t1);
    expect(s.sessionNo, 1);
    await expectLater(
        sessions.logSession(classId: c.id!, heldOn: DateTime(2026, 8, 3), minutes: 45, setup: AralSetup.pullOut),
        _refused('Forbidden: you can only log sessions for your own classes.'));
    await expectLater(
        sessions.logSession(classId: a.id!, heldOn: DateTime(2026, 8, 3), minutes: 45, setup: AralSetup.pullOut),
        _refused('Class "7-A" already has session 1 (#${s.id}) on 2026-08-03.'));
  });

  test('the default sheet is the class\'s learners active on the date', () async {
    final first = (await sessions.classSessions(a.id!)).single;
    final sheet = await sessions.sheet(first.id!);
    expect(sheet.map((l) => l.enrollment.studentId).toSet(), {9701, 9702, 9703});
    expect(sheet.every((l) => l.expected), isTrue);
    await sessions.mark(first.id!, roster[9701]!.id!, AralMark.present);
    await sessions.mark(first.id!, roster[9702]!.id!, AralMark.absent);
    await sessions.mark(first.id!, roster[9703]!.id!, AralMark.excused);
    // A tutor doesn't mark a learner of another class.
    await expectLater(sessions.mark(first.id!, roster[9705]!.id!, AralMark.present),
        _refused('Only an admin or coordinator can mark a learner of another class.'));
    final summary = await sessions.classSummary(a.id!);
    expect(summary.sessions, 1);
    expect(summary.activeLearners, 3);
    expect(summary.attendance.rate, 0.5, reason: 'present 1 / (present 1 + absent 1); excused does not count');
  });

  test('numbering and the check-in timing count per class', () async {
    for (var d = 3; d <= 5; d++) {
      await sessions.logSession(classId: b.id!, heldOn: DateTime(2026, 8, d), minutes: 45, setup: AralSetup.pullOut);
    }
    AralSession? last;
    for (var d = 4; d <= 18; d++) {
      last = await sessions.logSession(classId: a.id!, heldOn: DateTime(2026, 8, d), minutes: 45, setup: AralSetup.pullOut);
    }
    expect(last!.sessionNo, 16);
    expect(sessions.lastWarning, contains('Class "7-A": session 16 done: the check-in assessment is due.'));
    final sumB = await sessions.classSummary(b.id!);
    expect(sumB.lastSessionNo, 3);
    expect(sumB.nextCheckInAfter, 16);
    expect((await sessions.classSummary(a.id!)).nextCheckInAfter, 32);
  });

  test('after a move, the new class tutor still sees the learner\'s marks from the old class', () async {
    await signInAs(_coord, 'coord@zz', 'coordinator');
    await classes.place(roster[9701]!.id!, c.id!);
    await signInAs(_t2, 'two@zz', 'tutor');
    final (summary, rows) = await sessions.learnerAttendance(roster[9701]!.id!);
    expect(rows, hasLength(1));
    expect(rows.single.$1.classId, a.id);
    expect(summary.present, 1);
  });
}
