// Learner history (spec docs/superpowers/specs/2026-10-25-learner-history-design.md),
// signed in offline: one learner's years latest first with CRLA, Phil-IRI,
// ARAL and SRP; who may read it; the plan's Review Focus cases.
import 'dart:io';

import 'package:basa_capstone/core/data/local/local_database.dart';
import 'package:basa_capstone/core/models/aral_class.dart';
import 'package:basa_capstone/core/models/aral_enrollment.dart';
import 'package:basa_capstone/core/models/aral_session.dart';
import 'package:basa_capstone/core/models/crla_assessment.dart' show CrlaRound;
import 'package:basa_capstone/core/models/phil_iri_assessment.dart' show PhilIriRound;
import 'package:basa_capstone/core/services/auth_messages.dart';
import 'package:basa_capstone/core/wiring/app_context.dart';
import 'package:basa_capstone/core/wiring/wire_admin.dart';
import 'package:basa_capstone/core/wiring/wire_shared.dart';
import 'package:basa_capstone/core/wiring/wire_tutor.dart';
import 'package:basa_capstone/viewmodels/aral_checkin_viewmodel.dart';
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
  late AralCheckinViewModel checkinVm;

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
    checkinVm = t.aralCheckinVm;
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
    // Grade 3 CRLA, BOSY, languages as saves store them (fil = "Tagalog"):
    // MT Tagalog, Filipino twice (attempt 2 counts), English without a profile
    // (no story match). MT and Filipino share the language but are two tests.
    for (final (id, variant, language, attempt, day, profile) in [
      (9901, 'fil', 'Tagalog', 1, '2025-08-10', 'High Emerging Reader'),
      (9902, 'eng', 'English', 1, '2025-08-10', null),
      (9903, 'mt', 'Tagalog', 1, '2025-08-11', 'Developing Reader'),
      (9904, 'fil', 'Tagalog', 2, '2025-08-20', 'Transitioning Reader'),
    ]) {
      await db.insert('crla_assessments', {
        'id': id, 'student_id': 9901, 'school_id': _school, 'section_id': 9901, 'school_year': '2025-2026',
        'subject_variant': variant, 'language': language, 'round': 'bosy', 'attempt_no': attempt,
        'assessed_at': day, 'origin': 'cloud', 'row_version': 1, 'reading_profile': profile,
      });
    }
    // A prescribed Grade 4 pretest passage with one question (content comes from the cloud).
    await db.insert('phil_iri_collections', {'id': 9901, 'name': 'ZZ LH passages', 'is_prescribed': 1});
    await db.insert('phil_iri_passages', {'id': 9901, 'collection_id': 9901, 'test_type': 'pre', 'level': 4,
        'selection_no': 1, 'title': 'ZZ Passage', 'body': 'One two three four five six seven eight nine ten.',
        'word_count': 10});
    await db.insert('phil_iri_questions', {'id': 9901, 'passage_id': 9901, 'question_no': 1, 'question_type': 'L',
        'prompt': 'How many?', 'choices': '["ten","two"]', 'answer_key': 'a'});
    // 9905: a GST in a section not on this device, a check-in on a tool not on
    // this device, an enrollment in a section whose school is not on this device.
    await db.insert('sections', {'id': 9906, 'school_id': 9999, 'school_year': '2025-2026', 'grade_level': '5',
        'section_name': 'Lost5'});
    await db.insert('enrollments', {'student_id': 9905, 'section_id': 9906, 'school_year': '2025-2026', 'status': 'active'});
    await db.insert('students', {'id': 9905, 'lrn': '999999999905', 'last_name': 'ZZLH', 'first_name': 'L9905',
        'school_id': _school});
    await db.insert('phil_iri_gst_results', {'id': 9905, 'student_id': 9905, 'school_id': _school, 'section_id': 9999,
        'school_year': '2026-2027', 'attempt_no': 1, 'max_score': 20, 'total_score': 5, 'taken_at': '2026-08-02', 'row_version': 1,
        'origin': 'cloud'});
    await db.insert('aral_enrollments', {
      'id': 9905, 'student_id': 9905, 'school_id': _school, 'section_id': 9902, 'school_year': '2026-2027',
      'key_stage': 'ks2', 'track': 'basic', 'entered_on': '2026-08-01', 'basis_source': 'manual',
      'origin': 'cloud', 'row_version': 1,
    });
    await db.insert('aral_checkins', {'id': 9905, 'enrollment_id': 9905, 'tool_id': 9999, 'attempt_no': 1,
        'taken_on': '2026-09-01', 'origin': 'cloud', 'row_version': 1});
    // 9906: our learner with another school's enrollment on this device, and an
    // exited referral ARAL entry whose check-in 16 was retaken on another tool
    // after a program change (newer date, lower attempt number).
    await db.insert('students', {'id': 9906, 'lrn': '999999999906', 'last_name': 'ZZLH', 'first_name': 'L9906',
        'school_id': _school});
    await db.insert('sections', {'id': 9905, 'school_id': _school, 'school_year': '2025-2026', 'grade_level': '5',
        'section_name': 'S5'});
    await db.insert('enrollments', {'student_id': 9906, 'section_id': 9905, 'school_year': '2025-2026', 'status': 'active'});
    await db.insert('enrollments', {'student_id': 9906, 'section_id': 9904, 'school_year': '2026-2027', 'status': 'active'});
    await db.insert('aral_enrollments', {
      'id': 9906, 'student_id': 9906, 'school_id': _school, 'section_id': 9905, 'school_year': '2025-2026',
      'key_stage': 'ks2', 'track': 'basic', 'entered_on': '2025-08-01', 'status': 'exited',
      'exited_on': '2025-12-01', 'exit_reason': 'grade_level_ready', 'basis_source': 'referral',
      'referred_by': 'Teacher A', 'referral_reason': 'Slow reader', 'origin': 'cloud', 'row_version': 1,
    });
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
    for (final (id, track, checkpoint) in [(9902, 'plus', 16), (9903, 'basic', 32)]) {
      await db.insert('aral_checkin_tools', {'id': id, 'key_stage': 'ks2', 'track': track, 'checkpoint': checkpoint,
          'language': 'english', 'title': 'ZZ check-in $id'});
      await db.insert('aral_checkin_items', {'id': id, 'tool_id': id, 'item_no': 1, 'kind': 'open', 'prompt': 'Read.'});
    }
    for (final (id, tool, attempt, day, correct) in [
      (9906, 9901, 2, '2025-09-01', null), // older, failed (no answer)
      (9907, 9902, 1, '2025-09-10', 1), // newer, passed
      (9908, 9903, 1, '2025-11-01', 1),
    ]) {
      await db.insert('aral_checkins', {'id': id, 'enrollment_id': 9906, 'tool_id': tool, 'attempt_no': attempt,
          'taken_on': day, 'origin': 'cloud', 'row_version': 1});
      if (correct != null) {
        await db.insert('aral_checkin_answers', {'id': id, 'checkin_id': id, 'item_id': tool, 'is_correct': correct, 'row_version': 1});
      }
    }

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
    // A scored Phil-IRI BOSY reading in the current section.
    final session = await t.philIriVm.startSession(studentId: 9901, sectionId: 9902, schoolYear: '2026-2027',
        round: PhilIriRound.bosy, assessedAt: DateTime(2026, 8, 5));
    final reading = await t.philIriVm.startReading(assessmentId: session.id!, passageId: 9901, readingSeconds: 10);
    await t.philIriVm.answer(readingId: reading.id!, questionId: 9901, chosen: 'a');
  });

  tearDownAll(LocalDatabase.close);

  test('years come latest first with every part filled', () async {
    await signInAs(_coord, 'coord@lh', 'coordinator', _school);
    final h = await vm.history(9901);
    expect(h.student.id, 9901);
    expect(h.years.map((y) => y.schoolYear), ['2026-2027', '2025-2026', '2024-2025']);

    final g3 = h.years[1];
    // One entry per test (MT and Filipino both store "Tagalog"), latest attempt, MT/Filipino/English order.
    final bosy = g3.crla[CrlaRound.bosy]!;
    expect(bosy.keys, ['MT (Tagalog)', 'Filipino', 'English']);
    expect(bosy, {'MT (Tagalog)': 'Developing Reader', 'Filipino': 'Transitioning Reader', 'English': null});
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

  test('a moved learner gets one Phil-IRI result per section', () async {
    await signInAs(_coord, 'coord@lh', 'coordinator', _school);
    final g4 = (await vm.history(9901)).years.first;
    expect(g4.philIri, hasLength(2)); // Review Focus 2 and 5
    expect(g4.philIri.map((p) => p.sectionId), [9902, 9903]);
    expect(g4.philIri.map((p) => p.sectionName), ['S4-A', 'S4-B']);
    // The GST counts for the whole year (Phil-IRI's rule): the year's latest under each section.
    expect(g4.philIri.map((p) => p.results?.gst?.totalScore).toSet(), hasLength(1));
    expect(g4.philIri.every((p) => p.unavailable == null), isTrue);
  });

  test('a scored Phil-IRI round shows under its section', () async {
    await signInAs(_coord, 'coord@lh', 'coordinator', _school);
    final g4 = (await vm.history(9901)).years.first;
    final current = g4.philIri.firstWhere((p) => p.sectionId == 9902).results!;
    final bosy = current.rounds.firstWhere((r) => r.round == PhilIriRound.bosy);
    expect(bosy.given, isTrue);
    expect(bosy.profile, isNotNull);
    final old = g4.philIri.firstWhere((p) => p.sectionId == 9903).results!;
    expect(old.rounds.where((r) => r.given), isEmpty); // the reading was in the other section
  });

  test('a part not on this device gets a note and the rest still shows', () async {
    await signInAs(_coord, 'coord@lh', 'coordinator', _school);
    final h = await vm.history(9905);
    expect(h.years.map((y) => y.schoolYear), ['2026-2027', '2025-2026']);
    final y = h.years.first;
    final p = y.philIri.single;
    expect(p.sectionId, 9999);
    expect(p.sectionName, isNull);
    expect(p.results, isNull);
    expect(p.unavailable, '${learnerHistoryUnavailable}No section with id 9999.');
    final aral = y.aral.single;
    expect(aral.unavailable, startsWith(learnerHistoryUnavailable));
    expect(aral.checkin16, LearnerHistoryCheckin.unavailable);
    expect(aral.checkin32, LearnerHistoryCheckin.unavailable);
    expect(aral.attendance.marked, 0);
    final e = h.years.last.enrollments.single; // its school is not on this device
    expect(e.sectionName, 'Lost5');
    expect(e.schoolName, isNull);
  });

  test('check-in: the newer attempt counts after a program change, like the check-in report', () async {
    await signInAs(_coord, 'coord@lh', 'coordinator', _school);
    final h = await vm.history(9906);
    expect(h.scopeNote, learnerHistoryScopeNote);
    expect(h.years.map((y) => y.schoolYear), ['2026-2027', '2025-2026']);
    // Another school's enrollment on this device is shown as it is (RLS decides what reaches the device).
    expect(h.years.first.enrollments.single.schoolName, 'ZZ Other');
    final aral = h.years.last.aral.single;
    expect(aral.enrollment.exitedOn, '2025-12-01');
    expect(aral.enrollment.exitReason, AralExitReason.gradeLevelReady);
    expect(aral.enrollment.basisSource, AralBasisSource.referral);
    expect(aral.enrollment.referredBy, 'Teacher A');
    expect(aral.checkin16, LearnerHistoryCheckin.passed); // attempt 1 on 09-10 beats attempt 2 on 09-01
    expect(aral.checkin32, LearnerHistoryCheckin.passed);
    expect(aral.unavailable, isNull);
    final report = await checkinVm.checkinReport(schoolId: _school, schoolYear: '2025-2026');
    final row = report.sections.expand((s) => s.learners).singleWhere((l) => l.enrollment.id == 9906);
    expect(row.after16!.passed, isTrue);
    expect(row.after16!.checkin.id, 9907);
  });

  test('a blank LRN is refused', () async {
    await signInAs(_coord, 'coord@lh', 'coordinator', _school);
    await expectLater(vm.historyByLrn('  '), _refused('Enter an LRN.'));
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
