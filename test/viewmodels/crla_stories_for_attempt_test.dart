// CrlaViewModel.storiesForAttempt (2026-11-15): the stories the Part 2 form
// lists for one attempt (the school's region, the attempt's language, the
// section's grade), story 1 first, and the same match Part 2 is scored with.
import 'dart:io';

import 'package:basa_capstone/core/wiring/app_context.dart';
import 'package:basa_capstone/core/wiring/wire_shared.dart';
import 'package:basa_capstone/core/wiring/wire_tutor.dart';
import 'package:basa_capstone/viewmodels/crla_viewmodel.dart';
import 'package:basa_capstone/viewmodels/viewmodel_exception.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../helpers/offline_owner.dart';

const _school = 9801, _noStories = 9802;
const _year = '2026-2027';

void main() {
  late CrlaViewModel vm;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final ctx = await AppContext.open(dataDir: Directory.systemTemp.createTempSync('basa_crla_stories_').path);
    vm = wireTutor(ctx, wireShared(ctx)).crlaVm;
    final db = ctx.localDb;

    await db.insert('schools', {'id': _school, 'school_id': 'ZZCS1', 'school_name': 'ZZ Stories', 'region_id': 13});
    await db.insert('schools', {'id': _noStories, 'school_id': 'ZZCS2', 'school_name': 'ZZ No stories', 'region_id': 2});
    for (final (id, school, grade) in [(9801, _school, '2'), (9802, _noStories, '2'), (9803, _school, '5')]) {
      await db.insert('sections', {'id': id, 'school_id': school, 'school_year': _year, 'grade_level': grade,
          'section_name': 'S$id'});
    }
    await db.insert('students', {'id': 9801, 'lrn': '999999998801', 'last_name': 'ZZCS', 'first_name': 'One',
        'school_id': _school});
    for (final (id, school, section) in [(9801, _school, 9801), (9802, _noStories, 9802), (9803, _school, 9803)]) {
      await db.insert('crla_assessments', {
        'id': id, 'student_id': 9801, 'school_id': school, 'section_id': section, 'school_year': _year,
        'subject_variant': 'fil', 'language': 'Tagalog', 'round': 'bosy', 'attempt_no': 1,
        'assessed_at': '2026-08-10', 'origin': 'cloud', 'row_version': 1,
      });
    }
    // Story 2 first on purpose (the list is story 1 first); the others must
    // not match: another grade, another language, another region.
    for (final (id, region, language, grade, no, title, words) in [
      (9802, 13, 'Tagalog', 2, 2, 'Ang Ikalawa', 80),
      (9801, 13, 'Tagalog', 2, 1, 'Ang Una', 96),
      (9803, 13, 'Tagalog', 3, 1, 'Grade 3 story', 120),
      (9804, 13, 'Cebuano', 2, 1, 'Cebuano story', 90),
      (9805, 1, 'Tagalog', 2, 1, 'Region 1 story', 70),
    ]) {
      await db.insert('crla_stories', {'id': id, 'region_id': region, 'language': language, 'grade': grade,
          'story_no': no, 'title': title, 'word_count': words});
    }
    await seedOfflineOwner(db, userId: '00000000-0000-0000-0000-00000000cs01', email: 'cs@test', role: 'tutor',
        schoolId: _school);
    expect(await ctx.authVm.signInOffline(email: 'cs@test', password: 'test-pw'), isNull);
  });

  test("lists the attempt's two stories, story 1 first", () async {
    final stories = await vm.storiesForAttempt(9801);
    expect([for (final s in stories) (s.storyNo, s.title, s.wordCount)], [(1, 'Ang Una', 96), (2, 'Ang Ikalawa', 80)]);
  });

  test('is empty where the region has no stories for the attempt', () async {
    expect(await vm.storiesForAttempt(9802), isEmpty);
  });

  test('Part 2 is scored with the listed story', () async {
    final story2 = (await vm.storiesForAttempt(9801)).last;
    final saved = await vm.savePart2Fluency(
        assessmentId: 9801, storyNo: 2, miscues: 5, timeMinutes: 1, timeSeconds: 0, comprehensionCorrect: 4);
    expect(saved.wordsRead, story2.wordCount - 5);
  });

  test('refuses an unknown attempt and one outside Grades 1-3', () async {
    await expectLater(vm.storiesForAttempt(1),
        throwsA(isA<ViewModelException>().having((e) => e.message, 'message', 'No assessment with id 1.')));
    await expectLater(
        vm.storiesForAttempt(9803),
        throwsA(isA<ViewModelException>()
            .having((e) => e.message, 'message', 'Assessment 9803 is not in a Grade 1-3 section.')));
  });
}
