// The ARAL roster on classes (spec docs/superpowers/specs/2026-10-23-aral-classes-design.md),
// signed in offline as a coordinator: placing into a full class, the
// proposal filling a class, referrals, learners of another grade (only with
// the coordinator's other-grade confirmation, plan 2026-10-24-aral-class-grade),
// mixed-programs classes, a section move to another grade, and the
// informational lines of aral-update.
import 'dart:io';

import 'package:basa_capstone/core/data/local/local_database.dart';
import 'package:basa_capstone/core/models/aral_class.dart';
import 'package:basa_capstone/core/models/aral_enrollment.dart';
import 'package:basa_capstone/core/wiring/app_context.dart';
import 'package:basa_capstone/core/wiring/wire_shared.dart';
import 'package:basa_capstone/core/wiring/wire_tutor.dart';
import 'package:basa_capstone/viewmodels/aral_class_viewmodel.dart';
import 'package:basa_capstone/viewmodels/aral_viewmodel.dart';
import 'package:basa_capstone/viewmodels/reminder_viewmodel.dart';
import 'package:basa_capstone/viewmodels/viewmodel_exception.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../helpers/offline_owner.dart';

const _school = 9501;
const _year = '2026-2027';
const _coord = '00000000-0000-0000-0000-0000000095c1';
const _tutor = '00000000-0000-0000-0000-0000000095a1';

Matcher _refused(String message) =>
    throwsA(isA<ViewModelException>().having((e) => e.message, 'message', message));

void main() {
  late Database db;
  late AralViewModel aral;
  late AralClassViewModel classes;
  late ReminderViewModel reminders;
  late AralClass rose, lily, sun, mixed;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final ctx = await AppContext.open(dataDir: Directory.systemTemp.createTempSync('basa_roster_classes_').path);
    db = ctx.localDb;
    final t = wireTutor(ctx, wireShared(ctx));
    aral = t.aralVm;
    classes = t.aralClassVm;
    reminders = t.reminderVm;

    await db.insert('schools', {'id': _school, 'school_id': 'ZZR1', 'school_name': 'ZZ Roster Classes'});
    await db.insert('users', {'id': _tutor, 'email': 'tutor@zz', 'full_name': 'Tutor One', 'role': 'tutor', 'school_id': _school});
    // A: G7 (16 learners), B: G7 (17), C: G5 (none yet), D: G2 (1), E: G9 (3), F: G7 (3).
    for (final (id, grade) in [(9501, '7'), (9502, '7'), (9503, '5'), (9504, '2'), (9505, '9'), (9506, '7')]) {
      await db.insert('sections', {'id': id, 'school_id': _school, 'school_year': _year, 'grade_level': grade, 'section_name': 'S$id'});
    }
    Future<void> learner(int id, int section) async {
      await db.insert('students', {'id': id, 'lrn': '99999995${id.toString().padLeft(4, '0')}', 'last_name': 'ZZR',
          'first_name': 'L$id', 'school_id': _school});
      await db.insert('enrollments', {'student_id': id, 'section_id': section, 'school_year': _year, 'status': 'active'});
    }
    for (var i = 1; i <= 16; i++) {
      await learner(9500 + i, 9501);
    }
    for (var i = 21; i <= 37; i++) {
      await learner(9500 + i, 9502);
    }
    await learner(9541, 9504);
    for (var i = 51; i <= 53; i++) {
      await learner(9500 + i, 9505);
    }
    for (var i = 61; i <= 63; i++) {
      await learner(9500 + i, 9506);
    }

    await seedOfflineOwner(db, userId: _coord, email: 'coord@zz', role: 'coordinator', schoolId: _school);
    expect(await ctx.authVm.signInOffline(email: 'coord@zz', password: 'test-pw'), isNull);

    rose = await classes.createClass(schoolId: _school, schoolYear: _year, className: '7-Rose',
        gradeLevel: 7, program: AralClassProgram.ks3Basic, tutorId: _tutor);
    lily = await classes.createClass(schoolId: _school, schoolYear: _year, className: '7-Lily',
        gradeLevel: 7, program: AralClassProgram.ks2Basic);
    sun = await classes.createClass(schoolId: _school, schoolYear: _year, className: '2-Sun',
        gradeLevel: 2, program: AralClassProgram.ks1, tutorId: _tutor);
    mixed = await classes.createClass(schoolId: _school, schoolYear: _year, className: '7-Mixed', gradeLevel: 7);
  });

  tearDownAll(LocalDatabase.close);

  test('place refuses the 16th learner of a class', () async {
    final enrolled = [
      for (var i = 1; i <= 16; i++)
        await aral.enroll(sectionId: 9501, schoolYear: _year, studentId: 9500 + i,
            keyStage: AralKeyStage.ks3, track: AralTrack.basic),
    ];
    for (final e in enrolled.take(15)) {
      expect((await classes.place(e.id!, rose.id!)).classId, rose.id);
    }
    await expectLater(classes.place(enrolled.last.id!, rose.id!), _refused('Class "7-Rose" already has 15 active ARAL learners.'));
    expect((await classes.classRoster(rose.id!)).length, 15);
    // Wrong program: refused with the learner's name.
    await expectLater(classes.place(enrolled.last.id!, lily.id!),
        _refused('ZZR, L9516 is in KS3 Basic; class "7-Lily" is KS2 Basic.'));
    await expectLater(classes.place(enrolled.last.id!, sun.id!),
        _refused('ZZR, L9516 is in KS3 Basic; class "2-Sun" is KS1.'));
  });

  test('enrollProposed fills the class to 15, weakest first; the rest wait for a class', () async {
    final created = await aral.enrollProposed(sectionId: 9502, schoolYear: _year, classId: lily.id);
    expect(created, hasLength(17));
    expect(created.where((e) => e.classId == lily.id), hasLength(15));
    final waiting = created.where((e) => e.classId == null).toList();
    expect(waiting, hasLength(2));
    for (final e in waiting) {
      expect(aral.lastWarning, contains('ZZR, L${e.studentId} (${e.studentId})'));
    }
  });

  test('a referral needs who and why', () async {
    await expectLater(
        aral.refer(sectionId: 9504, schoolYear: _year, studentId: 9541, keyStage: AralKeyStage.ks1,
            referredBy: 'Ms. Cruz', reason: ' '),
        _refused('A referral needs who referred the learner and why.'));
  });

  test('a referred KS1 learner whose latest CRLA is Developing stays in ARAL', () async {
    final e = await aral.refer(sectionId: 9504, schoolYear: _year, studentId: 9541, keyStage: AralKeyStage.ks1,
        referredBy: 'Ms. Cruz', reason: 'struggles with decoding', classId: sun.id);
    expect(e.basisSource, AralBasisSource.referral);
    expect(e.classId, sun.id);
    await db.insert('crla_assessments', {
      'id': 9591, 'student_id': 9541, 'school_id': _school, 'section_id': 9504, 'school_year': _year,
      'subject_variant': 'fil', 'language': 'Filipino', 'attempt_no': 1, 'assessed_at': '2026-10-20',
      'round': 'bosy', 'reading_profile': 'Developing Reader', 'origin': 'cloud', 'row_version': 1,
    });
    final updates = await aral.applyResults(sectionId: 9504, schoolYear: _year);
    expect((await aral.getEnrollment(e.id!))!.isActive, isTrue,
        reason: updates.map((u) => '${u.kind.name}: ${u.reason}').join('; '));
  });

  test('a class grade outside 1-10 is refused; a grade or program change needs an empty class', () async {
    await expectLater(classes.createClass(schoolId: _school, schoolYear: _year, className: 'K', gradeLevel: 11),
        _refused('ARAL-Reading classes are for Grades 1-10.'));
    await expectLater(classes.createClass(schoolId: _school, schoolYear: _year, className: 'K', gradeLevel: 0),
        _refused('ARAL-Reading classes are for Grades 1-10.'));
    for (final change in [rose.copyWith(gradeLevel: 8), rose.copyWith(program: () => null),
        rose.copyWith(program: () => AralClassProgram.ks3Plus)]) {
      await expectLater(classes.editClass(change), _refused('Class "7-Rose" has learners; its grade and program can\'t change.'));
    }
    final empty = await classes.createClass(schoolId: _school, schoolYear: _year, className: '8-Empty', gradeLevel: 8);
    final edited = await classes.editClass(empty.copyWith(gradeLevel: 9, program: () => AralClassProgram.ks2Plus));
    expect((edited.gradeLevel, edited.program), (9, AralClassProgram.ks2Plus));
    await classes.deleteClass(empty.id!);
  });

  test('a mixed-programs class takes any program of its grade', () async {
    final placed = [
      for (final (id, ks, track) in [
        (9561, AralKeyStage.ks1, null),
        (9562, AralKeyStage.ks2, AralTrack.basic),
        (9563, AralKeyStage.ks3, AralTrack.plus),
      ])
        await aral.enroll(sectionId: 9506, schoolYear: _year, studentId: id, keyStage: ks, track: track, classId: mixed.id),
    ];
    expect(placed.map((e) => e.classId), everyElement(mixed.id));
    expect(aral.lastWarning, isNull);
  });

  test('another grade joins only with other-grade', () async {
    final g9 = await aral.enroll(sectionId: 9505, schoolYear: _year, studentId: 9551,
        keyStage: AralKeyStage.ks1, classId: mixed.id);
    expect(g9.classId, isNull, reason: 'enrol with a class never places another grade');
    expect(aral.lastWarning, 'ZZR, L9551 is in Grade 9; class "7-Mixed" is for Grade 7. '
        'ZZR, L9551 is on the roster without a class.');
    await expectLater(classes.place(g9.id!, mixed.id!),
        _refused('ZZR, L9551 is in Grade 9; class "7-Mixed" is for Grade 7. '
            'Place them in it anyway with other-grade if you decide so.'));
    expect((await classes.place(g9.id!, mixed.id!, otherGrade: true)).classId, mixed.id);
    // The confirmation doesn't lift the program rule.
    final other = await aral.enroll(sectionId: 9505, schoolYear: _year, studentId: 9552,
        keyStage: AralKeyStage.ks1);
    await expectLater(classes.place(other.id!, rose.id!, otherGrade: true),
        _refused('ZZR, L9552 is in KS1; class "7-Rose" is KS3 Basic.'));
  });

  test('enrollProposed from another grade enrols everybody and places nobody', () async {
    final created = await aral.enrollProposed(sectionId: 9505, schoolYear: _year, classId: mixed.id);
    expect(created, hasLength(1)); // 9551 and 9552 are already on the roster
    expect(created.single.classId, isNull);
    expect(aral.lastWarning, contains('ZZR, L9553 (9553): ZZR, L9553 is in Grade 9; class "7-Mixed" is for Grade 7.'));
  });

  test('a section move to another grade keeps the class and warns', () async {
    final e = (await aral.roster(sectionId: 9501, schoolYear: _year)).firstWhere((e) => e.studentId == 9501);
    expect(e.classId, rose.id);
    await db.update('enrollments', {'section_id': 9503}, where: 'student_id = 9501');
    final moved = await aral.moveToSection(e.id!);
    expect(moved.sectionId, 9503);
    expect(moved.classId, rose.id);
    expect(aral.lastWarning, 'Grade 5 is now in class "7-Rose" (Grade 7); move them if needed (aral-class-place).');
  });

  test('aral-update lists learners in a class of another grade', () async {
    final updates = await aral.applyResults(sectionId: 9503, schoolYear: _year);
    expect(updates.where((u) => u.kind == AralUpdateKind.otherGrade).map((u) => u.reason),
        ['Grade 5 in class "7-Rose" (Grade 7)']);
    final g9 = await aral.applyResults(sectionId: 9505, schoolYear: _year);
    expect(g9.where((u) => u.kind == AralUpdateKind.otherGrade).map((u) => u.reason),
        ['Grade 9 in class "7-Mixed" (Grade 7)']);
    // A mixed class never flags a program mismatch.
    final f = await aral.applyResults(sectionId: 9506, schoolYear: _year);
    expect(f.where((u) => u.kind == AralUpdateKind.programMismatch || u.kind == AralUpdateKind.otherGrade), isEmpty);
  });

  test('aral-update lists learners waiting for a class', () async {
    final unplaced = (await aral.roster(sectionId: 9501, schoolYear: _year)).firstWhere((e) => e.studentId == 9516);
    final updates = await aral.applyResults(sectionId: 9501, schoolYear: _year);
    expect(
        updates.where((u) => u.before.id == unplaced.id && u.kind == AralUpdateKind.unplaced && u.reason == 'waiting for a class'),
        hasLength(1));
  });

  test('coordinator reminders name the learners of each ARAL notice (F16)', () async {
    final school = (await reminders.coordinatorReminders(_school, _year)).single;
    final other = school.aral.singleWhere((n) => n.kind == AralClassNoticeKind.otherGrade);
    expect(other.message, '2 ARAL learners in a class of another grade.');
    expect(other.learners.map((l) => '${l.lrn} ${l.name}'), ['999999959501 ZZR, L9501', '999999959551 ZZR, L9551']);
    expect(other.enrollmentIds, [for (final l in other.learners) l.enrollmentId]);
    final waiting = school.aral.singleWhere((n) => n.kind == AralClassNoticeKind.waiting);
    expect(waiting.learners.map((l) => l.name), contains('ZZR, L9516'));
    expect(waiting.learners.every((l) => l.lrn.isNotEmpty && l.enrollmentId != null), isTrue);
  });
}
