// Learner history (spec docs/superpowers/specs/2026-10-25-learner-history-design.md),
// signed in offline: one learner's years latest first with CRLA, Phil-IRI,
// ARAL and SRP; who may read it; the plan's Review Focus cases.
import 'dart:io';

import 'package:basa_capstone/core/data/local/local_database.dart';
import 'package:basa_capstone/core/models/aral_class.dart';
import 'package:basa_capstone/core/models/aral_enrollment.dart';
import 'package:basa_capstone/core/models/aral_session.dart';
import 'package:basa_capstone/core/models/crla_assessment.dart' show CrlaRound;
import 'package:basa_capstone/core/services/auth_messages.dart';
import 'package:basa_capstone/core/wiring/app_context.dart';
import 'package:basa_capstone/core/wiring/wire_admin.dart';
import 'package:basa_capstone/core/wiring/wire_shared.dart';
import 'package:basa_capstone/core/wiring/wire_tutor.dart';
import 'package:basa_capstone/viewmodels/learner_history_viewmodel.dart';
import 'package:basa_capstone/viewmodels/viewmodel_exception.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../helpers/offline_owner.dart';

const _school = 9901;
const _other = 9902;
const _coord = '00000000-0000-0000-0000-0000000099c1';
const _tutor = '00000000-0000-0000-0000-0000000099a1';
const _superadmin = '00000000-0000-0000-0000-0000000099d1';
const _lrn = '999999999901';

Matcher _refused(String message) =>
    throwsA(isA<ViewModelException>().having((e) => e.message, 'message', message));

void main() {
  late AppContext ctx;
  late LearnerHistoryViewModel vm;
  late AralClass cls;

  Future<void> signInAs(String id, String email, String role, int? schoolId) async {
    await seedOfflineOwner(ctx.localDb, userId: id, email: email, role: role, schoolId: schoolId);
    expect(await ctx.authVm.signInOffline(email: email, password: 'test-pw'), isNull);
  }

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    ctx = await AppContext.open(dataDir: Directory.systemTemp.createTempSync('basa_learner_history_vm_').path);
    final s = wireShared(ctx);
    final t = wireTutor(ctx, s);
    vm = (await wireAdmin(ctx, s, t)).learnerHistoryVm;
    final db = ctx.localDb;

    await db.insert('schools', {'id': _school, 'school_id': 'ZZLH1', 'school_name': 'ZZ History', 'region_id': 13});
    await db.insert('schools', {'id': _other, 'school_id': 'ZZLH2', 'school_name': 'ZZ Other', 'region_id': 13});
    await db.insert('users', {'id': _tutor, 'email': 'tutor@lh', 'full_name': 'Tutor One', 'role': 'tutor',
        'school_id': _school, 'is_active': 1});
    for (final (id, year, grade, name) in [
      (9900, '2024-2025', '2', 'S2'),
      (9901, '2025-2026', '3', 'S3'),
      (9902, '2026-2027', '4', 'S4-A'),
      (9903, '2026-2027', '4', 'S4-B'),
    ]) {
      await db.insert('sections', {'id': id, 'school_id': _school, 'school_year': year, 'grade_level': grade,
          'section_name': name});
    }
    await db.insert('sections', {'id': 9904, 'school_id': _other, 'school_year': '2026-2027', 'grade_level': '4',
        'section_name': 'O4'});
    for (final (id, school) in [(9901, _school), (9902, _other), (9903, _school), (9904, null)]) {
      await db.insert('students', {'id': id, 'lrn': '99999999$id', 'last_name': 'ZZLH',
          'first_name': 'L$id', 'school_id': school});
    }
    for (final (student, section, year) in [
      (9901, 9900, '2024-2025'),
      (9901, 9901, '2025-2026'),
      (9901, 9903, '2026-2027'), // moved to 9902 below
      (9902, 9904, '2026-2027'),
    ]) {
      await db.insert('enrollments', {'student_id': student, 'section_id': section, 'school_year': year, 'status': 'active'});
    }
    // Grade 3 CRLA, BOSY: Filipino with a profile, English without one (no story match).
    for (final (id, variant, language, profile) in [
      (9901, 'fil', 'Filipino', 'High Emerging Reader'),
      (9902, 'eng', 'English', null),
    ]) {
      await db.insert('crla_assessments', {
        'id': id, 'student_id': 9901, 'school_id': _school, 'section_id': 9901, 'school_year': '2025-2026',
        'subject_variant': variant, 'language': language, 'round': 'bosy', 'attempt_no': 1,
        'assessed_at': '2025-08-10', 'origin': 'cloud', 'row_version': 1, 'reading_profile': profile,
      });
    }
    // 9903: an ARAL entry waiting for a class, no enrollments row (Review Focus 3).
    await db.insert('aral_enrollments', {
      'id': 9903, 'student_id': 9903, 'school_id': _school, 'section_id': 9902, 'school_year': '2026-2027',
      'key_stage': 'ks2', 'track': 'basic', 'entered_on': '2026-08-01', 'basis_source': 'manual',
      'origin': 'cloud', 'row_version': 1,
    });
    await db.insert('srp_classes', {'id': 9901, 'school_id': _school, 'school_year': '2026-2027', 'assessed_grade': 4,
        'class_name': 'Summer Readers', 'room': 'R1', 'tutor_id': _tutor});
    await db.insert('srp_class_members', {'class_id': 9901, 'student_id': 9901, 'school_year': '2026-2027'});
    // A one-item check-in tool for KS2 Basic after session 16 (tools come from the cloud).
    await db.insert('aral_checkin_tools', {'id': 9901, 'key_stage': 'ks2', 'track': 'basic', 'checkpoint': 16,
        'language': 'english', 'title': 'ZZ check-in 16'});
    await db.insert('aral_checkin_items', {'id': 9901, 'tool_id': 9901, 'item_no': 1, 'kind': 'open', 'prompt': 'Read.'});

    await signInAs(_coord, 'coord@lh', 'coordinator', _school);
    // Grade 4: GST in two sections (moved learner, Review Focus 2 and 5), ARAL in a class.
    await t.philIriVm.recordGst(studentId: 9901, sectionId: 9903, schoolYear: '2026-2027', totalScore: 6);
    await db.update('enrollments', {'section_id': 9902},
        where: 'student_id = ? AND school_year = ?', whereArgs: [9901, '2026-2027']);
    await t.philIriVm.recordGst(studentId: 9901, sectionId: 9902, schoolYear: '2026-2027', totalScore: 4);
    cls = await t.aralClassVm.createClass(schoolId: _school, schoolYear: '2026-2027', className: '4-Readers',
        gradeLevel: 4, program: AralClassProgram.ks2Basic, tutorId: _tutor);
    final e = await t.aralVm.enroll(sectionId: 9902, schoolYear: '2026-2027', studentId: 9901,
        keyStage: AralKeyStage.ks2, track: AralTrack.basic, enteredOn: DateTime(2026, 8, 1));
    await t.aralClassVm.place(e.id!, cls.id!);
    for (final (day, mark) in [(3, AralMark.present), (4, AralMark.absent)]) {
      final s = await t.aralSessionVm.logSession(classId: cls.id!, heldOn: DateTime(2026, 8, day), minutes: 45,
          setup: AralSetup.pullOut);
      await t.aralSessionVm.mark(s.id!, e.id!, mark);
    }
    // Check-in 16: attempt 1 passed, attempt 2 failed -> the latest counts.
    final c1 = await t.aralCheckinVm.startCheckin(e.id!, 16, on: DateTime(2026, 9, 1));
    await t.aralCheckinVm.markOpen(c1.id!, 1, true);
    final c2 = await t.aralCheckinVm.startCheckin(e.id!, 16, on: DateTime(2026, 9, 8));
    await t.aralCheckinVm.markOpen(c2.id!, 1, false);
  });

  tearDownAll(LocalDatabase.close);

  test('years come latest first with every part filled', () async {
    await signInAs(_coord, 'coord@lh', 'coordinator', _school);
    final h = await vm.history(9901);
    expect(h.student.id, 9901);
    expect(h.years.map((y) => y.schoolYear), ['2026-2027', '2025-2026', '2024-2025']);

    final g3 = h.years[1];
    expect(g3.crla[CrlaRound.bosy], {'Filipino': 'High Emerging Reader', 'English': null}); // Review Focus 4
    expect(g3.enrollments.single.gradeLevel, '3');

    final g4 = h.years[0];
    expect(g4.enrollments.single.gradeLevel, '4');
    expect(g4.enrollments.single.sectionName, 'S4-A');
    expect(g4.enrollments.single.schoolName, 'ZZ History');
    final aral = g4.aral.single;
    expect(aral.className, '4-Readers');
    expect(aral.tutorName, 'Tutor One');
    expect(aral.attendance.present, 1);
    expect(aral.attendance.absent, 1);
    expect(aral.checkin16, LearnerHistoryCheckin.failed);
    expect(aral.checkin32, LearnerHistoryCheckin.notTaken);
    expect(g4.srp!.className, 'Summer Readers');
    expect(g4.srp!.tutorName, 'Tutor One');
    expect(g4.srp!.room, 'R1');
    expect(g4.isEmpty, isFalse);
  });

  test('a GST-only year gives one Phil-IRI result per section', () async {
    await signInAs(_coord, 'coord@lh', 'coordinator', _school);
    final g4 = (await vm.history(9901)).years.first;
    expect(g4.philIri, hasLength(2)); // Review Focus 2 and 5
    expect(g4.philIri.map((p) => p.sectionId), [9902, 9903]);
    expect(g4.philIri.map((p) => p.sectionName), ['S4-A', 'S4-B']);
    // The GST counts for the whole year (Phil-IRI's rule): the year's latest under each section.
    expect(g4.philIri.map((p) => p.results.gst?.totalScore).toSet(), hasLength(1));
  });

  test('an enrollment-only year is empty', () async {
    await signInAs(_coord, 'coord@lh', 'coordinator', _school);
    final g2 = (await vm.history(9901)).years.last;
    expect(g2.schoolYear, '2024-2025');
    expect(g2.isEmpty, isTrue);
  });

  test('historyByLrn finds the same learner', () async {
    await signInAs(_coord, 'coord@lh', 'coordinator', _school);
    expect((await vm.historyByLrn(_lrn)).student.id, 9901);
  });

  test('a coordinator gets the scope note, a superadmin none', () async {
    await signInAs(_coord, 'coord@lh', 'coordinator', _school);
    expect((await vm.history(9901)).scopeNote, learnerHistoryScopeNote);
    await signInAs(_superadmin, 'super@lh', 'admin', null);
    expect((await vm.history(9901)).scopeNote, isNull);
    expect((await vm.history(9902)).years.single.schoolYear, '2026-2027');
  });

  test('a tutor is refused', () async {
    await signInAs(_tutor, 'tutor@lh', 'tutor', _school);
    await expectLater(vm.history(9901), _refused('Forbidden: only an admin or coordinator can view learner history.'));
  });

  test("another school's learner is refused", () async {
    await signInAs(_coord, 'coord@lh', 'coordinator', _school);
    await expectLater(vm.history(9902), _refused('Forbidden: that learner is not in your school.'));
    await expectLater(vm.history(9904), _refused('Forbidden: that learner is not in your school.')); // Review Focus 1
  });

  test('unknown id and LRN give the pull-cloud messages', () async {
    await signInAs(_coord, 'coord@lh', 'coordinator', _school);
    await expectLater(
        vm.history(1), _refused('Learner not found on this device. Download the latest data first (pull-cloud).'));
    await expectLater(vm.historyByLrn('000000000000'),
        _refused('No learner with LRN 000000000000 on this device. Download the latest data first (pull-cloud).'));
  });

  test('a year with only a waiting ARAL entry is listed', () async {
    await signInAs(_coord, 'coord@lh', 'coordinator', _school);
    final h = await vm.history(9903);
    final y = h.years.single;
    expect(y.schoolYear, '2026-2027');
    expect(y.enrollments, isEmpty);
    final aral = y.aral.single; // Review Focus 3
    expect(aral.className, isNull);
    expect(aral.tutorName, isNull);
    expect(aral.attendance.marked, 0);
    expect(aral.checkin16, LearnerHistoryCheckin.notTaken);
    expect(aral.checkin32, LearnerHistoryCheckin.notTaken);
  });

  test('not signed in is refused', () async {
    ctx.authVm.currentUser = null;
    await expectLater(vm.history(9901), _refused(notSignedInMessage));
  });
}
