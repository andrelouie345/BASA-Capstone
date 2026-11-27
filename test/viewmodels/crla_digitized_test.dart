// Digitized CRLA in CrlaViewModel (spec docs/superpowers/specs/2026-11-27-crla-digitized-design.md,
// plan Task 5): Part 1 items marked one by one, the story marked word by word
// with a timer that stops at the grade's limit, answers per question, and the
// Part 1 / Part 2 rows written from those marks.
import 'dart:io';

import 'package:basa_capstone/core/models/crla_assessment.dart' show CrlaRound;
import 'package:basa_capstone/core/models/crla_marks.dart';
import 'package:basa_capstone/core/wiring/app_context.dart';
import 'package:basa_capstone/core/wiring/wire_shared.dart';
import 'package:basa_capstone/core/wiring/wire_tutor.dart';
import 'package:basa_capstone/viewmodels/crla_viewmodel.dart';
import 'package:basa_capstone/viewmodels/viewmodel_exception.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../helpers/offline_owner.dart';

const _school = 9901, _noForm = 9902;
const _g3 = 9901, _g2 = 9902, _g2NoForm = 9903;
const _year = '2026-2027';
const _student = 9901;

Matcher _refusal(String text) => throwsA(isA<ViewModelException>().having((e) => e.message, 'message', text));

const _typedRefusal = 'This attempt is marked in BASA; change its marks instead of typing totals.';

void main() {
  late CrlaViewModel vm;
  late SharedVms shared;
  late Database db;
  var nextId = 9900, nextAttempt = 0;
  final t0 = DateTime(2026, 11, 27, 9);
  DateTime at(int seconds) => t0.add(Duration(seconds: seconds));

  /// A pulled attempt of the learner (each test gets its own).
  Future<int> attempt(String variant, {int section = _g3, int school = _school}) async {
    final id = ++nextId;
    await db.insert('crla_assessments', {
      'id': id, 'student_id': _student, 'school_id': school, 'section_id': section, 'school_year': _year,
      'subject_variant': variant, 'language': variant == 'eng' ? 'English' : 'Tagalog', 'round': 'mosy',
      'attempt_no': ++nextAttempt, 'assessed_at': '2026-11-27', 'origin': 'cloud', 'row_version': 1,
    });
    return id;
  }

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final ctx = await AppContext.open(dataDir: Directory.systemTemp.createTempSync('basa_crla_digitized_').path);
    shared = wireShared(ctx);
    vm = wireTutor(ctx, shared).crlaVm;
    db = ctx.localDb;

    await db.insert('schools', {'id': _school, 'school_id': 'ZZCD1', 'school_name': 'ZZ Digitized', 'region_id': 10});
    await db.insert('schools', {'id': _noForm, 'school_id': 'ZZCD2', 'school_name': 'ZZ No form', 'region_id': 2});
    for (final (id, school, grade) in [(_g3, _school, '3'), (_g2, _school, '2'), (_g2NoForm, _noForm, '2')]) {
      await db.insert('sections', {'id': id, 'school_id': school, 'school_year': _year, 'grade_level': grade,
          'section_name': 'S$id'});
    }
    await db.insert('students', {'id': _student, 'lrn': '999999999901', 'last_name': 'ZZCD', 'first_name': 'One',
        'school_id': _school});
    await db.insert('enrollments', {'student_id': _student, 'section_id': _g3, 'school_year': _year});

    // Region 10 forms: English Grade 3 (Task 1 + Task 2) and Tagalog Grade 2
    // (Task 1 + low + high); 10 items each.
    var item = 0;
    for (final (language, grade, tasks) in [
      ('English', 3, ['task1', 'task2']),
      ('Tagalog', 2, ['task1', 'task2_low', 'task2_high']),
    ]) {
      for (final task in tasks) {
        for (var n = 1; n <= 10; n++) {
          await db.insert('crla_part1_items', {'id': ++item, 'region_id': 10, 'language': language, 'grade': grade,
              'task': task, 'item_no': n, 'text': '$task-$n'});
        }
      }
    }
    // English Grade 3 story 1: 100 words in 10 sentences; Tagalog Grade 2
    // story 1: 20 words.
    final eng = [for (var s = 0; s < 10; s++) [for (var w = 0; w < 10; w++) 'w${s * 10 + w}'].join(' ')].join('\n');
    await db.insert('crla_stories', {'id': 9901, 'region_id': 10, 'language': 'English', 'grade': 3, 'story_no': 1,
        'title': 'The Hundred', 'word_count': 100, 'body': eng});
    await db.insert('crla_stories', {'id': 9902, 'region_id': 10, 'language': 'Tagalog', 'grade': 2, 'story_no': 1,
        'title': 'Ang Dalawampu', 'word_count': 20,
        'body': '${[for (var w = 0; w < 10; w++) 't$w'].join(' ')}\n${[for (var w = 10; w < 20; w++) 't$w'].join(' ')}'});
    var q = 0;
    for (final story in [9901, 9902]) {
      for (var n = 1; n <= 6; n++) {
        await db.insert('crla_story_questions', {'id': ++q, 'story_id': story, 'question_no': n,
            'after_sentence': n, 'question': 'Question $n?', 'accepted_answers': 'Answer $n'});
      }
    }
    await seedOfflineOwner(db, userId: '00000000-0000-0000-0000-00000000cd01', email: 'cd@test', role: 'tutor',
        schoolId: _school);
    expect(await ctx.authVm.signInOffline(email: 'cd@test', password: 'test-pw'), isNull);
  });

  /// The attempt's Part 1 / Part 2 row (task scores and time are not in crla_results).
  Future<Map<String, Object?>?> row(String table, int a) async =>
      (await db.query(table, where: 'assessment_id = ?', whereArgs: [a])).firstOrNull;

  /// Marks items [from]..[to] of [task] right (or wrong).
  Future<void> mark(int a, CrlaTask task, int from, int to, {bool correct = true}) async {
    for (var n = from; n <= to; n++) {
      await vm.markItem(a, task, n, correct: correct);
    }
  }

  // Final review I2 (first in the file: no timer has been started yet).
  test('an attempt whose story timing is not finished is named before sending', () async {
    expect(shared.syncVm.uploadChecks, contains(vm.unfinishedTimingMessage));
    expect(await vm.unfinishedTimingMessage(), isNull);
    final a = await attempt('eng');
    await vm.startStoryTimer(a, 1, at: DateTime.now().subtract(const Duration(seconds: 10)));
    const unfinished = 'Finish the CRLA story timing of ZZCD, One first (stop the timer, or tap the last word '
        'reached), then send.';
    expect(await vm.unfinishedTimingMessage(), unfinished);
    await vm.storyTimer(a, now: DateTime.now().add(const Duration(minutes: 5))); // stopped at the limit
    expect(await vm.unfinishedTimingMessage(), unfinished, reason: 'the last word is still needed');
    await vm.setLastWordReached(a, 59);
    expect(await vm.unfinishedTimingMessage(), isNull);
  });

  // Final review C1.
  test('unmarking the last Part 1 mark of an attempt not sent yet removes its Part 1 and profile', () async {
    final a = (await vm.startAssessment(
            studentId: _student, sectionId: _g3, schoolYear: _year, subjectVariant: 'eng', round: CrlaRound.bosy))
        .id!;
    await vm.closeTask(a, CrlaTask.task1); // all wrong: Full Refresher
    expect(await row('crla_part1_english', a), isNotNull);
    for (var n = 1; n <= 10; n++) {
      await vm.unmarkItem(a, CrlaTask.task1, n);
    }
    expect(await row('crla_part1_english', a), isNull);
    expect((await vm.getAssessment(a))!.readingProfile, isNull);
    expect((await vm.digitized(a)).isDigitized, isFalse);
    await vm.markItem(a, CrlaTask.task1, 1, correct: true); // can be marked again
    expect((await row('crla_part1_english', a))!['task1_score'], 1);
    await vm.removeAttempt(a);
  });

  test('the last Part 1 mark of an attempt on the server is changed, not removed', () async {
    final a = await attempt('eng');
    await vm.markItem(a, CrlaTask.task1, 1, correct: true);
    await vm.markItem(a, CrlaTask.task1, 2, correct: false);
    await vm.unmarkItem(a, CrlaTask.task1, 2); // not the last one
    await expectLater(vm.unmarkItem(a, CrlaTask.task1, 1),
        _refusal('This attempt is already on the server: change its last Part 1 mark instead of removing it.'));
    expect((await row('crla_part1_english', a))!['task1_score'], 1);
  });

  // Final review I1.
  test('a form that reaches the device after a first look is found', () async {
    final a = await attempt('eng', section: _g2); // English Grade 2: no form yet
    await expectLater(vm.form(a),
        _refusal("No digitized CRLA form for this school's region, language and grade: enter the totals instead."));
    for (final (task, base) in [('task1', 3000), ('task2', 3100)]) {
      for (var n = 1; n <= 10; n++) {
        await db.insert('crla_part1_items', {'id': base + n, 'region_id': 10, 'language': 'English', 'grade': 2,
            'task': task, 'item_no': n, 'text': '$task-$n'});
      }
    }
    await db.insert('crla_stories', {'id': 9905, 'region_id': 10, 'language': 'English', 'grade': 2, 'story_no': 1,
        'title': 'Late', 'word_count': 3, 'body': 'It came late.'});
    expect((await vm.form(a)).stories.single.title, 'Late');
  });

  // Final review M2 (spec D5): an early stop means the whole story was read.
  test('after a stop before the limit the whole story counts: no last word', () async {
    final a = await attempt('eng');
    await vm.startStoryTimer(a, 1, at: at(0));
    await vm.stopStoryTimer(a, at: at(45));
    await expectLater(vm.setLastWordReached(a, 30),
        _refusal('The learner finished before the time limit: the whole story counts.'));
    expect((await row('crla_part2_fluency', a))!['words_read'], 100);
  });

  test('the form: items per task, the story in sentences and words, questions with accepted answers', () async {
    final a = await attempt('eng');
    final form = await vm.form(a);
    expect(form.items[CrlaTask.task1]!.length, 10);
    expect(form.items[CrlaTask.task2]!.first.text, 'task2-1');
    final story = form.stories.single;
    expect((story.storyNo, story.title, story.wordCount, story.words.length, story.sentences.length),
        (1, 'The Hundred', 100, 100, 10));
    expect(story.questions.first.acceptedAnswers, 'Answer 1');
    expect(form.timeLimitSeconds, 120);
  });

  test('no form for the region -> refusal', () async {
    final a = await attempt('fil', section: _g2NoForm, school: _noForm);
    const text = "No digitized CRLA form for this school's region, language and grade: enter the totals instead.";
    await expectLater(vm.form(a), _refusal(text));
    await expectLater(vm.markItem(a, CrlaTask.task1, 1, correct: true), _refusal(text));
  });

  test('digitized part 1 standard: task1 8 right -> task2High allowed, totals and level follow', () async {
    final a = await attempt('fil', section: _g2);
    await mark(a, CrlaTask.task1, 1, 8);
    await expectLater(vm.markItem(a, CrlaTask.task2High, 1, correct: true), _refusal('Finish Task 1 first.'));
    await mark(a, CrlaTask.task1, 9, 10, correct: false);
    await expectLater(
        vm.markItem(a, CrlaTask.task2Low, 1, correct: true), _refusal('This Task 2 is not the one Task 1 leads to.'));
    await mark(a, CrlaTask.task2High, 1, 5);
    await vm.closeTask(a, CrlaTask.task2High);
    final s = await vm.digitized(a);
    expect((s.task1Score, s.task2, s.task2Score, s.isDigitized, s.label), (8, CrlaTask.task2High, 5, true, 'Marked in BASA'));
    expect(s.evidence.part1.where((m) => m.task == CrlaTask.task2High).length, 10);
    final p1 = (await row('crla_part1_standard', a))!;
    expect((p1['task1_score'], p1['task2_high_score'], p1['task2_low_score']), (8, 5, null));
    final r = (await vm.getResult(a))!;
    expect((r.part1TotalScore, r.part1ReadingLevel), (23, 'Light Refresher'));
  });

  test('english task1 all wrong then closeTask -> test ends, Full Refresher', () async {
    final a = await attempt('eng');
    await vm.closeTask(a, CrlaTask.task1);
    await expectLater(vm.markItem(a, CrlaTask.task2, 1, correct: true), _refusal('Task 1 is 0: the test ends here.'));
    final p1 = (await row('crla_part1_english', a))!;
    expect((p1['task1_score'], p1['task2_score']), (0, null));
    expect((await vm.getResult(a))!.part1ReadingLevel, 'Full Refresher');
    expect((await vm.digitized(a)).task2, isNull);
  });

  test('task 1 change switching task 2 needs confirm', () async {
    final a = await attempt('fil', section: _g2);
    await mark(a, CrlaTask.task1, 1, 6);
    await mark(a, CrlaTask.task1, 7, 10, correct: false);
    await mark(a, CrlaTask.task2Low, 1, 3);
    await expectLater(vm.markItem(a, CrlaTask.task1, 7, correct: true),
        _refusal('This changes which Task 2 is given; confirm to clear its marks.'));
    var s = await vm.digitized(a);
    expect((s.task1Score, s.task2, s.task2Score), (6, CrlaTask.task2Low, 3));

    await vm.markItem(a, CrlaTask.task1, 7, correct: true, confirm: true);
    s = await vm.digitized(a);
    expect((s.task1Score, s.task2, s.task2Score), (7, CrlaTask.task2High, null));
    expect(s.evidence.part1.where((m) => m.task == CrlaTask.task2Low), isEmpty);
    final p1 = (await row('crla_part1_standard', a))!;
    expect((p1['task1_score'], p1['task2_low_score'], p1['task2_high_score']), (7, null, null));
    expect((await vm.getResult(a))!.part1TotalScore, 17);
  });

  test('double tap on a word is one toggle', () async {
    final a = await attempt('eng');
    await vm.startStoryTimer(a, 1, at: at(0));
    await Future.wait([vm.toggleWord(a, 5), vm.toggleWord(a, 5)]);
    expect((await vm.digitized(a)).evidence.words, isEmpty);
    await vm.toggleWord(a, 5, kind: CrlaWordMarkKind.selfCorrected);
    await vm.toggleWord(a, 5); // the other kind changes the mark
    final words = (await vm.digitized(a)).evidence.words;
    expect([for (final w in words) (w.wordIndex, w.kind)], [(5, CrlaWordMarkKind.miscue)]);
  });

  test('timed story stopped by the tutor at 95 s, 3 miscues on a 100-word story -> words read 97, time 1:35', () async {
    final a = await attempt('eng');
    await expectLater(vm.toggleWord(a, 1), _refusal('Start the timer on a story first.'));
    await vm.startStoryTimer(a, 1, at: at(0));
    for (final w in [1, 5, 9]) {
      await vm.toggleWord(a, w);
    }
    await vm.toggleWord(a, 12, kind: CrlaWordMarkKind.selfCorrected);
    await vm.pauseStoryTimer(a, at: at(30));
    await vm.resumeStoryTimer(a, at: at(40));
    await vm.stopStoryTimer(a, at: at(105));
    final s = await vm.digitized(a);
    expect((s.timerStatus, s.timedSeconds, s.lastWordNeeded, s.miscues, s.wordsRead), (TimerStatus.stopped, 95, false, 3, 97));
    final r = (await vm.getResult(a))!;
    expect((r.storyNo, r.miscues, r.wordsRead), (1, 3, 97));
    final p2 = (await row('crla_part2_fluency', a))!;
    expect((p2['time_minutes'], p2['time_seconds']), (1, 35));
  });

  test('answers: 4 correct, 1 incorrect, 1 not asked -> comprehension 4', () async {
    final a = await attempt('eng');
    await vm.startStoryTimer(a, 1, at: at(0));
    await vm.stopStoryTimer(a, at: at(60));
    for (final (n, m) in [
      (1, CrlaAnswerMark.correct), (2, CrlaAnswerMark.correct), (3, CrlaAnswerMark.incorrect),
      (4, CrlaAnswerMark.correct), (5, CrlaAnswerMark.notAsked), (6, CrlaAnswerMark.correct),
    ]) {
      await vm.answerQuestion(a, n, m);
    }
    await vm.answerQuestion(a, 2, CrlaAnswerMark.correct); // the same mark again: one row
    expect((await vm.digitized(a)).comprehension, 4);
    expect((await vm.getResult(a))!.comprehensionCorrect, 4);
    await expectLater(vm.answerQuestion(a, 7, CrlaAnswerMark.correct), _refusal('This story has no question 7.'));
  });

  test('auto-stop dated at the limit after reopen', () async {
    final a = await attempt('eng'); // Grade 3 English: 2:00
    await vm.startStoryTimer(a, 1, at: at(0));
    await vm.pauseStoryTimer(a, at: at(50));
    await vm.resumeStoryTimer(a, at: at(60));
    // The app was closed; it is read again long after the limit.
    final s = await vm.storyTimer(a, now: at(600));
    expect((s.timerStatus, s.timedSeconds, s.lastWordNeeded), (TimerStatus.stopped, 120, true));
    // start + 120 s + the 10 s pause
    expect(s.evidence.timer.last.at.isAtSameMomentAs(at(130)), isTrue, reason: '${s.evidence.timer.last.at}');
    expect((await vm.getResult(a))!.storyNo, isNull, reason: 'Part 2 waits for the last word');
    await expectLater(vm.pauseStoryTimer(a, at: at(601)), _refusal('The timer is already stopped.'));

    await vm.toggleWord(a, 3);
    await vm.setLastWordReached(a, 59);
    final p2 = (await row('crla_part2_fluency', a))!;
    expect((p2['time_minutes'], p2['time_seconds'], p2['words_read'], p2['miscues'], p2['last_word_reached']),
        (2, 0, 59, 1, 59));
    expect((await vm.digitized(a)).lastWordNeeded, isFalse);
  });

  test('a stop tapped after the limit is dated at the limit', () async {
    final a = await attempt('eng');
    await vm.startStoryTimer(a, 1, at: at(0));
    final s = await vm.stopStoryTimer(a, at: at(150));
    expect((s.timedSeconds, s.lastWordNeeded), (120, true));
  });

  test('last word before a marked miscue refused', () async {
    final a = await attempt('eng');
    await vm.startStoryTimer(a, 1, at: at(0));
    await vm.toggleWord(a, 70);
    await vm.storyTimer(a, now: at(200));
    await expectLater(
        vm.setLastWordReached(a, 59), _refusal('A word after the last word reached is marked; remove that mark first.'));
    await vm.toggleWord(a, 70); // removed
    await vm.setLastWordReached(a, 59);
    await expectLater(vm.toggleWord(a, 60), _refusal('That word is after the last word reached.'));
  });

  test('a restart clears the last word and the time is taken again', () async {
    final a = await attempt('eng');
    await vm.startStoryTimer(a, 1, at: at(0));
    await vm.storyTimer(a, now: at(200));
    await vm.setLastWordReached(a, 59);
    await vm.resetStoryTimer(a, at: at(210));
    await vm.startStoryTimer(a, 1, at: at(211));
    await vm.stopStoryTimer(a, at: at(281));
    final p2 = (await row('crla_part2_fluency', a))!;
    expect((p2['time_minutes'], p2['time_seconds'], p2['words_read'], p2['last_word_reached']), (1, 10, 100, null));
  });

  test('typed save refused on a digitized attempt', () async {
    final a = await attempt('eng');
    await vm.markItem(a, CrlaTask.task1, 1, correct: true);
    await expectLater(vm.savePart1English(assessmentId: a, task1Score: 5), _refusal(_typedRefusal));
    await expectLater(
        vm.savePart2Fluency(
            assessmentId: a, storyNo: 1, miscues: 0, timeMinutes: 1, timeSeconds: 0, comprehensionCorrect: 3),
        _refusal(_typedRefusal));
  });

  test('typed attempt unchanged, and its totals are not re-marked', () async {
    final a = await attempt('eng');
    await vm.savePart1English(assessmentId: a, task1Score: 5, task2Score: 4);
    final s = await vm.digitized(a);
    expect((s.isDigitized, s.label), (false, 'Totals typed in'));
    expect((await vm.getResult(a))!.part1TotalScore, 9);
    await expectLater(vm.markItem(a, CrlaTask.task1, 1, correct: true),
        _refusal("This attempt's totals were typed in; keep typing them, or remove the attempt and start again."));
  });

  test('observation, learner experience and remarks stay typed on a digitized attempt', () async {
    final a = await attempt('eng');
    await expectLater(vm.saveObservation(a, observationLevel: 2), _refusal('Time the story first.'));
    await vm.startStoryTimer(a, 1, at: at(0));
    await vm.stopStoryTimer(a, at: at(60));
    await vm.saveObservation(a, learnerExperienceRating: 4, observationLevel: 2, remarks: 'Shy at first');
    await vm.toggleWord(a, 0); // a later mark keeps them
    final p2 = (await vm.getResult(a))!;
    expect((p2.learnerExperienceRating, p2.observationLevel, p2.remarks, p2.miscues), (4, 2, 'Shy at first', 1));
  });

  test('profile equals the typed path for the same totals', () async {
    final d = await attempt('eng');
    await mark(d, CrlaTask.task1, 1, 10);
    await mark(d, CrlaTask.task2, 1, 8);
    await vm.closeTask(d, CrlaTask.task2);
    await vm.startStoryTimer(d, 1, at: at(0));
    for (final w in [1, 5, 9]) {
      await vm.toggleWord(d, w);
    }
    await vm.stopStoryTimer(d, at: at(95));
    for (var n = 1; n <= 6; n++) {
      await vm.answerQuestion(d, n, n <= 4 ? CrlaAnswerMark.correct : CrlaAnswerMark.incorrect);
    }
    final typed = await attempt('eng');
    await vm.savePart1English(assessmentId: typed, task1Score: 10, task2Score: 8);
    await vm.savePart2Fluency(
        assessmentId: typed, storyNo: 1, miscues: 3, timeMinutes: 1, timeSeconds: 35, comprehensionCorrect: 4);
    final rd = (await vm.getResult(d))!, rt = (await vm.getResult(typed))!;
    expect(rd.readingProfile, isNotNull);
    expect((rd.part1ReadingLevel, rd.wordsRead, rd.wpm, rd.readingProfile),
        (rt.part1ReadingLevel, rt.wordsRead, rt.wpm, rt.readingProfile));
  }, timeout: const Timeout(Duration(minutes: 3))); // ~40 marks; each write commits to disk on its own

  test('discarding (removeAttempt) leaves no evidence', () async {
    final started = await vm.startAssessment(
        studentId: _student, sectionId: _g3, schoolYear: _year, subjectVariant: 'eng', round: CrlaRound.eosy);
    final a = started.id!;
    await vm.markItem(a, CrlaTask.task1, 1, correct: true);
    await vm.startStoryTimer(a, 1, at: at(0));
    await vm.toggleWord(a, 2);
    await vm.removeAttempt(a);
    for (final t in ['crla_part1_marks', 'crla_part2_word_marks', 'crla_part2_answers', 'crla_timer_events']) {
      expect(await db.query(t, where: 'assessment_id = ?', whereArgs: [a]), isEmpty, reason: t);
    }
  });
}
