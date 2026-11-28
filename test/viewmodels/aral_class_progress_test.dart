// Each ARAL class learner's change from their ARAL starting round to their
// latest assessed round (spec docs/superpowers/specs/2026-11-27-aral-class-tutor-design.md D2).
import 'dart:convert';
import 'dart:io';

import 'package:basa_capstone/core/models/aral_progress.dart';
import 'package:basa_capstone/core/models/phil_iri_assessment.dart' show PhilIriRound;
import 'package:basa_capstone/core/models/phil_iri_reading.dart' show PhilIriReadingMethod;
import 'package:basa_capstone/core/wiring/app_context.dart';
import 'package:basa_capstone/core/wiring/wire_shared.dart';
import 'package:basa_capstone/core/wiring/wire_tutor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../helpers/offline_owner.dart';

const _year = '2026-2027';
const _asOf = '2026-11-27';
const _class = 1;

void main() {
  late TutorVms t;
  late Database db;
  late Map<int, AralLearnerProgress> byStudent;

  Future<Map<int, AralLearnerProgress>> progress() async =>
      {for (final p in await t.aralClassVm.classProgress(_class, asOf: _asOf)) p.enrollment.studentId: p};

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final ctx = await AppContext.open(dataDir: Directory.systemTemp.createTempSync('basa_aral_progress_').path);
    t = wireTutor(ctx, wireShared(ctx));
    db = ctx.localDb;
    await db.insert('schools', {'id': 1, 'school_id': 'ZZAP1', 'school_name': 'ZZ Progress', 'region_id': 13});
    for (final (id, grade) in [(71, '2'), (72, '7'), (73, '1')]) {
      await db.insert('sections', {'id': id, 'school_id': 1, 'school_year': _year, 'grade_level': grade, 'section_name': 'S$id'});
    }
    // Learners: 1-3, 6, 8, 10 Grade 2; 4, 5 Grade 7; 7 Grade 1.
    final sectionOf = {1: 71, 2: 71, 3: 71, 4: 72, 5: 72, 6: 71, 7: 73, 8: 71, 9: 72, 10: 71};
    for (final e in sectionOf.entries) {
      await db.insert('students', {'id': e.key, 'lrn': '9999000000${e.key.toString().padLeft(2, '0')}',
          'last_name': 'L${e.key.toString().padLeft(2, '0')}', 'first_name': 'F', 'school_id': 1});
      await db.insert('enrollments', {'student_id': e.key, 'section_id': e.value, 'school_year': _year, 'status': 'active'});
    }
    await db.insert('aral_classes', {'id': _class, 'school_id': 1, 'school_year': _year, 'class_name': 'ARAL-R-G2-01',
        'grade_level': 2, 'origin': 'cloud', 'row_version': 1});
    Future<void> enrol(int student, {String? basisRound = 'bosy', bool exited = false}) =>
        db.insert('aral_enrollments', {
          'id': student, 'student_id': student, 'school_id': 1, 'section_id': sectionOf[student], 'school_year': _year,
          'key_stage': sectionOf[student] == 72 ? 'ks3' : 'ks1', 'track': sectionOf[student] == 72 ? 'basic' : null,
          'class_id': _class, 'status': exited ? 'exited' : 'active', 'entered_on': '2026-07-01',
          'exited_on': exited ? '2026-10-01' : null, 'exit_reason': exited ? 'other' : null,
          'basis_source': basisRound == null ? 'manual' : (sectionOf[student] == 72 ? 'phil_iri' : 'crla'),
          'basis_round': basisRound, 'basis_level': basisRound == null ? null : 'x', 'origin': 'cloud', 'row_version': 1,
        });
    for (final s in [1, 2, 3, 4, 5, 8, 9]) {
      await enrol(s);
    }
    await enrol(6, basisRound: null);
    await enrol(7, basisRound: 'mosy');
    await enrol(10, exited: true);

    // CRLA attempts (stored profiles): the grade's language (G1 MT, G2 Filipino).
    var id = 100;
    final attempts = <int, int>{};
    Future<void> crla(int student, String variant, String round, String day, String profile) {
      final language = switch (variant) { 'fil' => 'Tagalog', 'eng' => 'English', _ => 'Sinugbuanong Binisaya' };
      attempts[student] = (attempts[student] ?? 0) + 1;
      return db.insert('crla_assessments', {
        'id': ++id, 'student_id': student, 'school_id': 1, 'section_id': sectionOf[student], 'school_year': _year,
        'subject_variant': variant, 'language': language, 'round': round, 'attempt_no': attempts[student],
        'assessed_at': day, 'origin': 'cloud', 'row_version': 1, 'reading_profile': profile,
      });
    }
    await crla(1, 'fil', 'bosy', '2026-08-03', 'Low Emerging Reader');
    await crla(1, 'fil', 'mosy', '2026-10-05', 'Developing Reader');
    await crla(2, 'fil', 'bosy', '2026-08-03', 'High Emerging Reader');
    await crla(2, 'fil', 'mosy', '2026-10-05', 'High Emerging Reader');
    await crla(3, 'fil', 'bosy', '2026-08-03', 'Developing Reader');
    await crla(3, 'fil', 'mosy', '2026-10-05', 'Low Emerging Reader');
    await crla(6, 'fil', 'bosy', '2026-08-03', 'Low Emerging Reader');
    await crla(6, 'fil', 'mosy', '2026-10-05', 'High Emerging Reader');
    await crla(7, 'mt', 'mosy', '2026-10-05', 'Low Emerging Reader');
    await crla(7, 'mt', 'eosy', '2026-11-20', 'High Emerging Reader');
    await crla(8, 'eng', 'bosy', '2026-08-03', 'Low Emerging Reader'); // not the grade's language
    await crla(8, 'fil', 'mosy', '2026-10-05', 'Developing Reader');
    await crla(10, 'fil', 'bosy', '2026-08-03', 'Low Emerging Reader');
    await crla(10, 'fil', 'mosy', '2026-09-20', 'Developing Reader');

    // Phil-IRI (Grade 7): two passages, readings through the ViewModel.
    await db.insert('phil_iri_collections', {'id': 1, 'name': 'Graded', 'is_grade_leveled': 1});
    for (final p in [301, 302, 303, 304]) {
      await db.insert('phil_iri_passages', {'id': p, 'collection_id': 1, 'level': 7, 'title': 'P$p',
          'body': [...List.filled(119, 'word'), 'end$p'].join(' '), 'word_count': 120, 'is_active': 1});
      for (var q = 1; q <= 10; q++) {
        await db.insert('phil_iri_questions', {'id': p * 10 + q, 'passage_id': p, 'question_no': q, 'prompt': 'Q$q',
            'choices': '["a","b"]', 'answer_key': 'a'});
      }
    }
    await seedOfflineOwner(db, userId: '00000000-0000-0000-0000-0000000000ap', email: 'ap@test', role: 'coordinator',
        schoolId: 1);
    expect(await ctx.authVm.signInOffline(email: 'ap@test', password: 'test-pw'), isNull);
    final vm = t.philIriVm;
    Future<void> read(int student, PhilIriRound round, int passage, int correct, DateTime day,
        {bool answers = true}) async {
      final s = await vm.startSession(
          studentId: student, sectionId: 72, schoolYear: _year, round: round, assessedAt: day);
      final r = await vm.startReading(
          assessmentId: s.id!, passageId: passage, method: PhilIriReadingMethod.oneMinute, wordsRead: 120);
      for (var q = 1; answers && q <= 10; q++) {
        await vm.answer(readingId: r.id!, questionId: passage * 10 + q, chosen: q <= correct ? 'a' : 'b');
      }
      await vm.complete(s.id!);
    }

    await read(4, PhilIriRound.bosy, 301, 4, DateTime(2026, 8, 3));
    await read(4, PhilIriRound.mosy1, 302, 8, DateTime(2026, 10, 5));
    await read(5, PhilIriRound.bosy, 301, 6, DateTime(2026, 8, 3));
    // 9: BOSY 8/10, then a MOSY #1 reading saved with no answers (blank
    // comprehension: not assessed, final review I2).
    await read(9, PhilIriRound.bosy, 303, 8, DateTime(2026, 8, 3));
    await read(9, PhilIriRound.mosy1, 304, 0, DateTime(2026, 10, 5), answers: false);
    byStudent = await progress();
  });

  test('CRLA up: Low Emerging at BOSY -> Developing at MOSY', () {
    final p = byStudent[1]!;
    expect((p.instrument, p.startRound, p.startProfile, p.latestRound, p.latestProfile, p.change),
        ('CRLA', 'bosy', 'Low Emerging Reader', 'mosy', 'Developing Reader', AralProgressChange.up));
  });

  test('CRLA same', () => expect(byStudent[2]!.change, AralProgressChange.same));

  test('CRLA down', () => expect(byStudent[3]!.change, AralProgressChange.down));

  test('Phil-IRI up: numbers before and after', () {
    final p = byStudent[4]!;
    expect((p.instrument, p.startRound, p.latestRound, p.change), ('Phil-IRI', 'bosy', 'mosy1', AralProgressChange.up));
    expect((p.startNumbers!.comprehension, p.latestNumbers!.comprehension), (40, 80));
    expect(p.latestNumbers!.wpm, isNotNull);
  });

  test('not assessed yet: no reading after the starting round', () {
    final p = byStudent[5]!;
    expect((p.change, p.latestRound), (AralProgressChange.notAssessedYet, null));
    expect(p.startProfile, isNotNull);
  });

  test('no recorded starting round starts at BOSY', () {
    expect((byStudent[6]!.startRound, byStudent[6]!.change), ('bosy', AralProgressChange.up));
  });

  test('Grade 1 starts at MOSY', () {
    final p = byStudent[7]!;
    expect((p.startRound, p.latestRound, p.change), ('mosy', 'eosy', AralProgressChange.up));
  });

  test('starting attempt in another language is not used', () {
    expect((byStudent[8]!.startProfile, byStudent[8]!.change), (null, AralProgressChange.noStartingResult));
  });

  test('an exited learner stays on the list, marked exited', () {
    expect((byStudent[10]!.exited, byStudent[10]!.change), (true, AralProgressChange.up));
    expect(byStudent.keys.toList(), [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]); // by last name
  });

  test('a later reading saved with no answers is not assessed yet, not a drop (final review I2)', () {
    final p = byStudent[9]!;
    expect((p.change, p.latestRound), (AralProgressChange.notAssessedYet, null));
  });

  test('actual values without an own reading: not assessed yet, not the stand-in', () async {
    expect((await progress())[5]!.change, AralProgressChange.notAssessedYet); // default values_aral = actual
  });

  test('carried values without an own reading: not assessed yet', () async {
    await db.insert('report_settings', {'id': 1, 'school_id': 1, 'settings': jsonEncode({'values_aral': 'carried'})});
    try {
      final p = (await progress())[5]!;
      expect((p.change, p.latestRound), (AralProgressChange.notAssessedYet, null));
    } finally {
      await db.delete('report_settings');
    }
  });

  test('the row has no carried/actual wording', () {
    for (final p in byStudent.values) {
      final text = '${p.change.label} $p'.toLowerCase();
      expect(text.contains('carried') || text.contains('actual'), isFalse, reason: text);
    }
  });
}
