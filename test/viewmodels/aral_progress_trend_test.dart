// The ARAL progress trend (spec
// docs/superpowers/specs/2026-11-27-aral-effectiveness-design.md D5): per round,
// the share of ARAL class learners up / same / down since their start.
import 'dart:io';

import 'package:basa_capstone/core/models/aral_progress.dart';
import 'package:basa_capstone/core/models/phil_iri_assessment.dart' show PhilIriRound;
import 'package:basa_capstone/core/models/phil_iri_reading.dart' show PhilIriReadingMethod;
import 'package:basa_capstone/core/models/trend_chart.dart';
import 'package:basa_capstone/core/wiring/app_context.dart';
import 'package:basa_capstone/core/wiring/wire_shared.dart';
import 'package:basa_capstone/core/wiring/wire_tutor.dart';
import 'package:basa_capstone/viewmodels/viewmodel_exception.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../helpers/offline_owner.dart';

const _year = '2026-2027';
final _asOf = DateTime(2026, 11, 27);

void main() {
  late TutorVms t;

  Map<String, List<num?>> seriesOf(TrendChart c) => {for (final s in c.series) s.name: s.values};

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final ctx = await AppContext.open(dataDir: Directory.systemTemp.createTempSync('basa_aral_trend_').path);
    t = wireTutor(ctx, wireShared(ctx));
    final db = ctx.localDb;
    await db.insert('schools', {'id': 1, 'school_id': 'ZZAT1', 'school_name': 'ZZ Trend', 'region_id': 13});
    for (final (id, grade) in [(72, '7'), (73, '3'), (74, '7')]) {
      await db.insert('sections', {'id': id, 'school_id': 1, 'school_year': _year, 'grade_level': grade, 'section_name': 'S$id'});
    }
    for (final id in [1, 2]) {
      await db.insert('aral_classes', {'id': id, 'school_id': 1, 'school_year': _year, 'class_name': 'ARAL-R-0$id',
          'grade_level': 7, 'origin': 'cloud', 'row_version': 1});
    }
    // 1-4 Grade 7 (section 72) and 6-7 Grade 3 (section 73) in class 1 (mixed);
    // 5 Grade 7 (section 74) in class 2. No sessions at all: the trend has no
    // attendance minimum.
    final sectionOf = {1: 72, 2: 72, 3: 72, 4: 72, 5: 74, 6: 73, 7: 73};
    for (final e in sectionOf.entries) {
      final s = e.key;
      final crla = e.value == 73;
      await db.insert('students', {'id': s, 'lrn': '99960000000$s', 'last_name': 'T$s', 'first_name': 'F', 'school_id': 1});
      await db.insert('enrollments', {'student_id': s, 'section_id': e.value, 'school_year': _year, 'status': 'active'});
      await db.insert('aral_enrollments', {
        'id': s, 'student_id': s, 'school_id': 1, 'section_id': e.value, 'school_year': _year,
        'key_stage': crla ? 'ks1' : 'ks3', 'track': crla ? null : 'basic', 'class_id': s == 5 ? 2 : 1,
        'status': 'active', 'entered_on': '2026-07-01', 'basis_source': crla ? 'crla' : 'phil_iri',
        'basis_round': 'bosy', 'basis_level': 'x', 'origin': 'cloud', 'row_version': 1,
      });
    }
    // CRLA (Grade 3 English): 6 up BOSY -> MOSY; 7 BOSY only.
    var id = 100;
    for (final (s, round, day, profile) in [
      (6, 'bosy', '2026-08-03', 'Low Emerging Reader'),
      (6, 'mosy', '2026-10-05', 'Developing Reader'),
      (7, 'bosy', '2026-08-03', 'Low Emerging Reader'),
    ]) {
      await db.insert('crla_assessments', {
        'id': ++id, 'student_id': s, 'school_id': 1, 'section_id': 73, 'school_year': _year, 'subject_variant': 'eng',
        'language': 'English', 'round': round, 'attempt_no': round == 'bosy' ? 1 : 2, 'assessed_at': day,
        'origin': 'cloud', 'row_version': 1, 'reading_profile': profile,
      });
    }
    // Phil-IRI (Grade 7) through the ViewModel.
    await db.insert('phil_iri_collections', {'id': 1, 'name': 'Graded', 'is_grade_leveled': 1});
    for (final p in [301, 302]) {
      await db.insert('phil_iri_passages', {'id': p, 'collection_id': 1, 'level': 7, 'title': 'P$p',
          'body': [...List.filled(119, 'word'), 'end$p'].join(' '), 'word_count': 120, 'is_active': 1});
      for (var q = 1; q <= 10; q++) {
        await db.insert('phil_iri_questions', {'id': p * 10 + q, 'passage_id': p, 'question_no': q, 'prompt': 'Q$q',
            'choices': '["a","b"]', 'answer_key': 'a'});
      }
    }
    await seedOfflineOwner(db, userId: '00000000-0000-0000-0000-0000000000at', email: 'at@test', role: 'coordinator',
        schoolId: 1);
    expect(await ctx.authVm.signInOffline(email: 'at@test', password: 'test-pw'), isNull);
    final vm = t.philIriVm;
    Future<void> read(int student, PhilIriRound round, int passage, int correct, DateTime day) async {
      final s = await vm.startSession(
          studentId: student, sectionId: sectionOf[student]!, schoolYear: _year, round: round, assessedAt: day);
      final r = await vm.startReading(
          assessmentId: s.id!, passageId: passage, method: PhilIriReadingMethod.oneMinute, wordsRead: 120);
      for (var q = 1; q <= 10; q++) {
        await vm.answer(readingId: r.id!, questionId: passage * 10 + q, chosen: q <= correct ? 'a' : 'b');
      }
      await vm.complete(s.id!);
    }

    // BOSY -> MOSY #1: 1, 2, 5 up (4 -> 8), 3 same (4 -> 4), 4 down (8 -> 4).
    for (final (s, bosy, mosy) in [(1, 4, 8), (2, 4, 8), (3, 4, 4), (4, 8, 4), (5, 4, 8)]) {
      await read(s, PhilIriRound.bosy, 301, bosy, DateTime(2026, 8, 3));
      await read(s, PhilIriRound.mosy1, 302, mosy, DateTime(2026, 10, 5));
    }
  });

  test('school, Phil-IRI: per round shares, rounds nobody has left out', () async {
    final c = await t.trendVm.aralProgress(const SchoolScope(1), _year, instrument: AralLearnerProgress.philIri, asOf: _asOf);
    expect(c.title, 'ARAL progress since the start (Phil-IRI) — ZZ Trend — $_year');
    expect(c.xLabels, ['MOSY #1 (n = 5)']);
    expect(seriesOf(c), {'Up': [60.0], 'Same': [20.0], 'Down': [20.0]});
  });

  test('section scope counts only that section', () async {
    final c = await t.trendVm.aralProgress(const SectionScope(72), _year, instrument: AralLearnerProgress.philIri, asOf: _asOf);
    expect(c.xLabels, ['MOSY #1 (n = 4)']);
    expect(seriesOf(c), {'Up': [50.0], 'Same': [25.0], 'Down': [25.0]});
  });

  test('mixed class split by instrument', () async {
    final c = await t.trendVm.aralProgress(const SchoolScope(1), _year, instrument: AralLearnerProgress.crla, asOf: _asOf);
    expect(c.xLabels, ['MOSY (n = 1)']);
    expect(seriesOf(c), {'Up': [100.0], 'Same': [0.0], 'Down': [0.0]});
    final phil = await t.trendVm.aralProgress(const SectionScope(73), _year, instrument: AralLearnerProgress.philIri, asOf: _asOf);
    expect(phil.xLabels, isEmpty);
  });

  test('tutor scope and an unknown instrument are refused', () async {
    await expectLater(t.trendVm.aralProgress(const TutorScope(null), _year, instrument: AralLearnerProgress.crla),
        throwsA(isA<ViewModelException>()));
    await expectLater(t.trendVm.aralProgress(const SchoolScope(1), _year, instrument: 'GST'),
        throwsA(isA<ViewModelException>().having((e) => e.message, 'message', 'The instrument is CRLA or Phil-IRI.')));
  });
}
