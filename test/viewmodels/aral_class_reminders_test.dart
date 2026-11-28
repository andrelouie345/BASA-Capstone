// MOSY and EOSY of ARAL class learners are the class tutor's (spec
// docs/superpowers/specs/2026-11-27-aral-class-tutor-design.md D1; decided by
// the reading coordinator 2026-11-27): their reminders go to the class tutor,
// grouped by class; BOSY stays with the section's tutors.
import 'dart:io';

import 'package:basa_capstone/core/wiring/app_context.dart';
import 'package:basa_capstone/core/wiring/wire_shared.dart';
import 'package:basa_capstone/core/wiring/wire_tutor.dart';
import 'package:basa_capstone/viewmodels/reminder_viewmodel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../helpers/offline_owner.dart';

const _year = '2026-2027';
const _a = '00000000-0000-0000-0000-0000000000a1'; // tutor of sections 71 and 72, and of class 2
const _b = '00000000-0000-0000-0000-0000000000b1'; // tutor of class 1
const _coord = '00000000-0000-0000-0000-0000000000c1';
final _today = DateTime(2026, 11, 27);

void main() {
  late TutorVms t;
  late Database db;

  Future<List<TutorReminder>> remindersOf(String tutor) async =>
      (await t.reminderVm.tutorReminders(tutor, _year, today: _today)).reminders;
  Set<int> idsOf(TutorReminder r) => r.learners.map((l) => l.studentId).toSet();
  TutorReminder line(List<TutorReminder> rs, {int? section, int? cls, required String round}) => rs.singleWhere((r) =>
      r.window?.round == round && (section == null || r.section?.id == section) && (cls == null || r.aralClass?.id == cls));

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final ctx = await AppContext.open(dataDir: Directory.systemTemp.createTempSync('basa_aral_class_reminders_').path);
    t = wireTutor(ctx, wireShared(ctx));
    db = ctx.localDb;
    await db.insert('schools', {'id': 1, 'school_id': 'ZZCR1', 'school_name': 'ZZ Class reminders', 'region_id': 13});
    for (final (id, grade) in [(71, '2'), (72, '7')]) {
      await db.insert('sections', {'id': id, 'school_id': 1, 'school_year': _year, 'grade_level': grade, 'section_name': 'S$id'});
    }
    for (final u in [_a, _b]) {
      await db.insert('users', {'id': u, 'email': '$u@t', 'full_name': 'Tutor ${u.substring(34)}', 'role': 'tutor',
          'school_id': 1, 'is_active': 1});
    }
    for (final s in [71, 72]) {
      await db.insert('tutor_section_assignments', {'tutor_id': _a, 'section_id': s, 'assigned_at': '2026-06-01'});
    }
    // Section 71 (Grade 2): 1 class 1, 2 class 2 (tutor A), 3 class 3 (no tutor), 4 waiting, 5 exited from class 1.
    // Section 72 (Grade 7): 6 class 1, 7 not in ARAL.
    final sectionOf = {1: 71, 2: 71, 3: 71, 4: 71, 5: 71, 6: 72, 7: 72};
    for (final e in sectionOf.entries) {
      await db.insert('students', {'id': e.key, 'lrn': '99990000010${e.key}', 'last_name': 'L${e.key}',
          'first_name': 'F', 'school_id': 1});
      await db.insert('enrollments', {'student_id': e.key, 'section_id': e.value, 'school_year': _year, 'status': 'active'});
    }
    for (final (id, tutor) in [(1, _b), (2, _a), (3, null)]) {
      await db.insert('aral_classes', {'id': id, 'school_id': 1, 'school_year': _year, 'class_name': 'ARAL-R-0$id',
          'grade_level': 2, 'tutor_id': tutor, 'origin': 'cloud', 'row_version': 1});
    }
    for (final (student, cls, exited) in [(1, 1, false), (2, 2, false), (3, 3, false), (4, null, false), (5, 1, true), (6, 1, false)]) {
      final g7 = sectionOf[student] == 72;
      await db.insert('aral_enrollments', {
        'id': student, 'student_id': student, 'school_id': 1, 'section_id': sectionOf[student], 'school_year': _year,
        'key_stage': g7 ? 'ks3' : 'ks1', 'track': g7 ? 'basic' : null, 'class_id': cls,
        'status': exited ? 'exited' : 'active', 'entered_on': '2026-07-01', 'exited_on': exited ? '2026-10-01' : null,
        'exit_reason': exited ? 'other' : null, 'basis_source': 'manual', 'origin': 'cloud', 'row_version': 1,
      });
    }
    // Rounds open today: BOSY and MOSY for both instruments (region default).
    var id = 0;
    for (final (instrument, round) in [('crla', 'bosy'), ('crla', 'mosy'), ('phil_iri', 'bosy'), ('phil_iri', 'mosy1')]) {
      await db.insert('assessment_calendar', {'id': ++id, 'school_year': _year, 'instrument': instrument, 'round': round,
          'opens_on': '2026-11-01', 'closes_on': '2026-12-15'});
    }
    await seedOfflineOwner(db, userId: _coord, email: 'cr@test', role: 'coordinator', schoolId: 1);
    expect(await ctx.authVm.signInOffline(email: 'cr@test', password: 'test-pw'), isNull);
  });

  test('at MOSY a placed learner leaves the section line and appears on the class line', () async {
    final section = line(await remindersOf(_a), section: 71, round: 'mosy');
    expect(idsOf(section), {3, 4, 5}); // 1 (class 1) and 2 (class 2: on A's class line) are handed over
    final cls = line(await remindersOf(_b), cls: 1, round: 'mosy');
    expect(idsOf(cls), {1});
    expect(cls.section, isNull);
    expect(cls.message, 'CRLA MOSY closes in 18 days: 1 of 1 learner of ARAL class ARAL-R-01 not assessed.');
  });

  test('BOSY is unchanged', () async {
    expect(idsOf(line(await remindersOf(_a), section: 71, round: 'bosy')), {1, 2, 3, 4, 5});
    expect((await remindersOf(_b)).where((r) => r.window?.round == 'bosy'), isEmpty);
  });

  test('a class without a tutor keeps its learners on the section line', () async {
    expect(idsOf(line(await remindersOf(_a), section: 71, round: 'mosy')), contains(3));
  });

  // Final review I1, accepted by the owner 2026-11-27: a tutor's phone holds
  // only that tutor's own classes, so a class with no tutor is not on it and
  // its learners look handed over: no MOSY/EOSY line for anyone until the
  // class gets a tutor (the coordinator's "class has no tutor" notice is the
  // safety net). On a coordinator's device (all classes) they stay on the
  // section line, as the test above shows.
  test('on a tutor\'s phone a tutorless class is not there: its learners leave the section line', () async {
    final row = (await db.query('aral_classes', where: 'id = 3')).single;
    await db.delete('aral_classes', where: 'id = 3');
    try {
      expect(idsOf(line(await remindersOf(_a), section: 71, round: 'mosy')), isNot(contains(3)));
    } finally {
      await db.insert('aral_classes', row);
    }
  });

  test('a learner who exited ARAL goes back to the section line', () async {
    expect(idsOf(line(await remindersOf(_a), section: 71, round: 'mosy')), contains(5));
    expect(idsOf(line(await remindersOf(_b), cls: 1, round: 'mosy')), isNot(contains(5)));
  });

  test('section tutor who also tutors the class sees the learner once', () async {
    final rs = await remindersOf(_a);
    final withTwo = rs.where((r) => r.window?.round == 'mosy' && idsOf(r).contains(2)).toList();
    expect(withTwo, hasLength(1));
    expect(withTwo.single.aralClass?.id, 2);
  });

  test('a mixed-grade class gets a CRLA line and a Phil-IRI line', () async {
    final rs = await remindersOf(_b);
    expect(idsOf(line(rs, cls: 1, round: 'mosy')), {1});
    final phil = line(rs, cls: 1, round: 'mosy1');
    expect(idsOf(phil), {6});
    expect(phil.message, startsWith('Phil-IRI MOSY #1 closes in 18 days: 1 of 1 learner of ARAL class ARAL-R-01'));
    // The Grade 7 section's own MOSY #1 line keeps only the learner not in ARAL.
    expect(idsOf(line(await remindersOf(_a), section: 72, round: 'mosy1')), {7});
  });

  // Final review I3: compare the round reminders field by field (the ARAL
  // notices are left out: placements really change them).
  Future<List<String>> coordinatorRounds() async => [
        for (final school in await t.reminderVm.coordinatorReminders(1, _year, today: _today))
          for (final r in school.reminders)
            '${r.instrument.name} ${r.window.round} ${r.kind.name} ${r.sectionCount} '
                '${[for (final b in r.below) '${b.section.id}:${b.assessed}/${b.enrolled}'].join(',')}',
      ];

  test('coordinator reminders are unchanged', () async {
    final placed = await coordinatorRounds();
    expect(placed, isNotEmpty);
    expect(placed.any((l) => l.contains('71:0/5')), isTrue, reason: '$placed'); // section 71 counts all 5 learners
    await db.update('aral_enrollments', {'class_id': null});
    try {
      expect(await coordinatorRounds(), placed);
    } finally {
      for (final (student, cls) in [(1, 1), (2, 2), (3, 3), (5, 1), (6, 1)]) {
        await db.update('aral_enrollments', {'class_id': cls}, where: 'id = ?', whereArgs: [student]);
      }
    }
  });
}
