// Who counts as assessed (spec docs/superpowers/specs/2026-11-09-phil-iri-rules-update-design.md
// D11-D15): progress counts assessed / carried over / not assessed, tutor
// reminders list carried-over learners and learners without a GST, the
// dashboard shows the carried count, Form 2b counts a Non-Reader in 3-LD
// Frustration and a Struggling GST profile under Frustration.
import 'dart:io';

import 'package:basa_capstone/core/models/phil_iri_assessment.dart' show PhilIriRound;
import 'package:basa_capstone/core/models/phil_iri_miscue.dart' show PhilIriMiscueType;
import 'package:basa_capstone/core/models/phil_iri_reading.dart' show PhilIriReadingMethod;
import 'package:basa_capstone/core/models/phil_iri_types.dart' show PhilIriLevel;
import 'package:basa_capstone/core/services/nla_form2b.dart' show NlaBand;
import 'package:basa_capstone/core/wiring/app_context.dart';
import 'package:basa_capstone/core/wiring/wire_shared.dart';
import 'package:basa_capstone/core/wiring/wire_tutor.dart';
import 'package:basa_capstone/viewmodels/dashboard_viewmodel.dart';
import 'package:basa_capstone/viewmodels/reminder_viewmodel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../helpers/offline_owner.dart';

const _year = '2026-2027';
const _tutor = '00000000-0000-0000-0000-00000000ab42';
// Learners: A GST only, B GST + reading, C reading only, D nothing (section 81);
// E Non-Reader with 0/10, F GST 10/40 only (section 82); G Grade 2 (section 83).
const a = 601, b = 602, c = 603, d = 604, e = 605, f = 606, g = 607;

String _day(DateTime t) =>
    '${t.year.toString().padLeft(4, '0')}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';

void main() {
  late AppContext ctx;
  late TutorVms t;
  final now = DateTime.now();

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    ctx = await AppContext.open(dataDir: Directory.systemTemp.createTempSync('basa_pi_assessed_').path);
    t = wireTutor(ctx, wireShared(ctx));
    final db = ctx.localDb;
    await db.insert('schools', {'id': 1, 'school_id': 'ZZ42', 'school_name': 'ZZ assessed'});
    await seedOfflineOwner(db,
        userId: '00000000-0000-0000-0000-00000000ab41', email: 'cnt@test', role: 'coordinator', schoolId: 1);
    await db.insert('users',
        {'id': _tutor, 'email': 'tut@test', 'full_name': 'Tutor T', 'role': 'tutor', 'school_id': 1, 'is_active': 1});
    for (final (id, grade) in [(81, '7'), (82, '7'), (83, '2')]) {
      await db.insert('sections', {'id': id, 'school_id': 1, 'school_year': _year, 'grade_level': grade, 'section_name': 'S$id'});
    }
    await db.insert('tutor_section_assignments',
        {'id': 1, 'tutor_id': _tutor, 'section_id': 81, 'assigned_at': '2026-06-01'});
    for (final (id, section) in [(a, 81), (b, 81), (c, 81), (d, 81), (e, 82), (f, 82), (g, 83)]) {
      await db.insert('students', {'id': id, 'lrn': '99999999$id', 'last_name': 'L$id', 'first_name': 'F', 'school_id': 1,
          'sex': id.isEven ? 'F' : 'M'});
      await db.insert('enrollments', {'student_id': id, 'section_id': section, 'school_year': _year, 'status': 'active'});
    }
    final opens = _day(now.subtract(const Duration(days: 10))), closes = _day(now.add(const Duration(days: 10)));
    await db.insert('assessment_calendar',
        {'id': 1, 'school_year': _year, 'instrument': 'phil_iri', 'round': 'bosy', 'opens_on': opens, 'closes_on': closes});
    await db.insert('assessment_calendar',
        {'id': 2, 'school_year': _year, 'instrument': 'crla', 'round': 'bosy', 'opens_on': opens, 'closes_on': closes});
    await db.insert('phil_iri_collections', {'id': 1, 'name': 'Graded assessed', 'is_grade_leveled': 1});
    await db.insert('phil_iri_passages', {
      'id': 301, 'collection_id': 1, 'level': 7, 'title': 'P301',
      'body': List.filled(120, 'word').join(' '), 'word_count': 120, 'is_active': 1,
    });
    for (var q = 1; q <= 10; q++) {
      await db.insert('phil_iri_questions',
          {'id': 3000 + q, 'passage_id': 301, 'question_no': q, 'prompt': 'Q$q', 'choices': '["a","b"]', 'answer_key': 'a'});
    }
    expect(await ctx.authVm.signInOffline(email: 'cnt@test', password: 'test-pw'), isNull);

    final vm = t.philIriVm;
    Future<void> read(int student, int section, int miscues, int correct) async {
      final s = await vm.startSession(studentId: student, sectionId: section, schoolYear: _year, round: PhilIriRound.bosy);
      final r = await vm.startReading(
          assessmentId: s.id!, passageId: 301, method: PhilIriReadingMethod.oneMinute, wordsRead: 120);
      for (var i = 0; i < miscues; i++) {
        await vm.markMiscue(readingId: r.id!, wordIndex: i, type: PhilIriMiscueType.omission);
      }
      for (var q = 1; q <= 10; q++) {
        await vm.answer(readingId: r.id!, questionId: 3000 + q, chosen: q <= correct ? 'a' : 'b');
      }
      await vm.complete(s.id!);
    }

    await vm.recordGst(studentId: a, sectionId: 81, schoolYear: _year, totalScore: 36);
    await vm.recordGst(studentId: b, sectionId: 81, schoolYear: _year, totalScore: 36);
    await read(b, 81, 0, 8);
    await read(c, 81, 0, 8);
    await read(e, 82, 100, 0);
    await vm.recordGst(studentId: f, sectionId: 82, schoolYear: _year, totalScore: 10);
  });

  test('progress counts assessed, carried and not assessed', () async {
    final p = await t.nlaReportVm.progress(schoolId: 1, schoolYear: _year, sectionIds: {81});
    final row = p.sections.single;
    expect(row.assessed[PhilIriRound.bosy]!.total, 2); // B, C
    expect(row.carriedOver[PhilIriRound.bosy]!.total, 1); // A (GST only)
    expect(row.notAssessed[PhilIriRound.bosy]!.total, 1); // D
    expect(row.share(PhilIriRound.bosy), 0.5);
  });

  test('school total sums carried and not assessed', () async {
    final p = await t.nlaReportVm.progress(schoolId: 1, schoolYear: _year, sectionIds: {81});
    expect(p.total.carriedOver[PhilIriRound.bosy]!.total, 1);
    expect(p.total.notAssessed[PhilIriRound.bosy]!.total, 1);
  });

  test('asOf before the reading', () async {
    final p = await t.nlaReportVm.progress(
        schoolId: 1, schoolYear: _year, sectionIds: {81}, asOf: now.subtract(const Duration(days: 1)));
    expect(p.total.assessed[PhilIriRound.bosy]!.total, 0);
  });

  test('Form 2b counts a Non-Reader once in 3-LD Frustration', () async {
    final r = await t.nlaReportVm.report(schoolId: 1, schoolYear: _year, sectionIds: {82});
    final ld3 = r.total.band(PhilIriRound.bosy, NlaBand.ld3Frustration);
    expect(ld3.male, 1); // E (605): Non-Reader with 0%, not counted before
    expect(ld3.female, 1); // F (606): GST 25% carried into BOSY
  });

  test('GST profile counts Struggling under Frustration', () async {
    final r = await t.nlaReportVm.report(schoolId: 1, schoolYear: _year, sectionIds: {82});
    expect(r.total.gstProfile[PhilIriLevel.frustration]!.total, 1); // F, 25%
  });

  test('tutor reminders list carried-over learners and learners without a GST', () async {
    final r = await t.reminderVm.tutorReminders(_tutor, _year, today: now);
    final open = r.reminders.singleWhere(
        (x) => x.kind == TutorReminderKind.openAssessment && x.section?.id == 81);
    expect(open.learners.map((l) => l.studentId).toSet(), {a, d});
    final noGst = r.reminders.singleWhere((x) => x.kind == TutorReminderKind.noGst);
    expect(noGst.learners.map((l) => l.studentId).toSet(), {c, d});
  });

  test('Phil-IRI tile carries the count; CRLA tile has none', () async {
    final s = (await t.dashboardVm.summary(_year, today: now)) as SchoolDashboard;
    final phil = s.school.current.singleWhere((r) => r.roundName == 'Phil-IRI BOSY');
    expect(phil.carriedOver, 2); // A (section 81) and F (section 82)
    final crla = s.school.current.singleWhere((r) => r.roundName.startsWith('CRLA'));
    expect(crla.carriedOver, isNull);
  });
}
