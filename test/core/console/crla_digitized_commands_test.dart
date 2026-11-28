// The digitized CRLA console commands (plan Task 6): one per CrlaViewModel
// call, both builds; run through the tutor registry on a device copy.
import 'dart:io';

import 'package:basa_capstone/core/console/console_registry.dart';
import 'package:basa_capstone/core/console/commands/crla_commands.dart';
import 'package:basa_capstone/core/wiring/app_context.dart';
import 'package:basa_capstone/core/wiring/wire_shared.dart';
import 'package:basa_capstone/core/wiring/wire_tutor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../helpers/offline_owner.dart';

void main() {
  late ConsoleRegistry r;
  late Database db;
  var nextId = 9950;

  Future<int> attempt() async {
    final id = ++nextId;
    await db.insert('crla_assessments', {
      'id': id, 'student_id': 9951, 'school_id': 9951, 'section_id': 9951, 'school_year': '2026-2027',
      'subject_variant': 'eng', 'language': 'English', 'round': 'mosy', 'attempt_no': id - 9950,
      'assessed_at': '2026-11-27', 'origin': 'cloud', 'row_version': 1,
    });
    return id;
  }

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final ctx = await AppContext.open(dataDir: Directory.systemTemp.createTempSync('basa_crla_cmds_').path);
    final t = wireTutor(ctx, wireShared(ctx));
    db = ctx.localDb;
    r = ConsoleRegistry();
    registerCrlaCommands(r, ctx.authVm, t.crlaVm);

    await db.insert('schools', {'id': 9951, 'school_id': 'ZZCC1', 'school_name': 'ZZ Cmds', 'region_id': 10});
    await db.insert('sections',
        {'id': 9951, 'school_id': 9951, 'school_year': '2026-2027', 'grade_level': '3', 'section_name': 'S'});
    await db.insert('students',
        {'id': 9951, 'lrn': '999999999951', 'last_name': 'ZZCC', 'first_name': 'One', 'school_id': 9951});
    var item = 0;
    for (final task in ['task1', 'task2']) {
      for (var n = 1; n <= 10; n++) {
        await db.insert('crla_part1_items', {'id': ++item, 'region_id': 10, 'language': 'English', 'grade': 3,
            'task': task, 'item_no': n, 'text': '$task-$n'});
      }
    }
    await db.insert('crla_stories', {'id': 9951, 'region_id': 10, 'language': 'English', 'grade': 3, 'story_no': 1,
        'title': 'The Hundred', 'word_count': 100,
        'body': [for (var s = 0; s < 10; s++) [for (var w = 0; w < 10; w++) 'w${s * 10 + w}'].join(' ')].join('\n')});
    for (var n = 1; n <= 6; n++) {
      await db.insert('crla_story_questions', {'id': n, 'story_id': 9951, 'question_no': n, 'after_sentence': n,
          'question': 'Question $n?', 'accepted_answers': 'Answer $n'});
    }
    await seedOfflineOwner(db, userId: '00000000-0000-0000-0000-00000000cc51', email: 'cc@test', role: 'tutor',
        schoolId: 9951);
    expect(await ctx.authVm.signInOffline(email: 'cc@test', password: 'test-pw'), isNull);
  });

  test('crla-form prints items, sentences with word positions and questions', () async {
    final out = await r.execute('crla-form ${await attempt()}');
    expect(out, contains('Grade 3 English (eng) · time limit 2:00'));
    expect(out, contains('task1: 1 task1-1 | 2 task1-2'));
    expect(out, contains('Story 1 · The Hundred · 100 words'));
    expect(out, contains('  2. [10-19] w10 w11'));
    expect(out, contains('  Q1 (after sentence 1) Question 1? — accepted: Answer 1'));
  });

  test('a marked attempt end to end: items, timer past the limit, last word, answers, observation', () async {
    final a = await attempt();
    for (var n = 1; n <= 10; n++) {
      await r.execute('crla-mark $a task1 $n ${n <= 9 ? 'right' : 'wrong'}');
    }
    expect(await r.execute('crla-mark $a task2 1 self'), contains('Task 1 9 · Task 2 1'));
    expect(await r.execute('crla-task-done $a task2'), contains('Marked in BASA · Task 1 9 · Task 2 1'));
    expect(await r.execute('crla-timer-start $a 1 2026-11-27T09:00:00+08:00'), contains('story 1 timer running'));
    await r.execute('crla-word $a 4');
    await r.execute('crla-word $a 7 self');
    final stopped = await r.execute('crla-timer $a'); // long after the 2:00 limit
    expect(stopped, contains('timer stopped 2:00 (limit 2:00)'));
    expect(stopped, contains('Tap the last word the learner reached (crla-last-word).'));
    expect(await r.execute('crla-last-word $a 49'), contains('miscues 1 · words read 49'));
    expect(await r.execute('crla-answer $a 1 right'), contains('comprehension 1'));
    expect(await r.execute('crla-answer $a 2 na'), contains('comprehension 1'));
    expect(await r.execute('crla-observe $a experience=4 observation=2 remarks=Read slowly at first'),
        'Part 2 of $a: experience 4, observation 2, remarks Read slowly at first.');
    final shown = await r.execute('crla-digitized $a');
    expect(shown, contains('  task2 1: self-corrected'));
    expect(shown, contains('  word 7: self_corrected'));
    expect(shown, contains('  Q2: not_asked'));
    expect(shown, contains('  2. stop 2026-11-27T09:02:00'));
  });

  test('refusals and bad arguments come back as one plain line', () async {
    final a = await attempt();
    expect(await r.execute('crla-mark $a task9 1 right'),
        'Invalid task: "task9" (task1, task2_low, task2_high or task2)');
    expect(await r.execute('crla-mark $a task1 1 maybe'),
        'Usage: crla-mark <assessmentId> <task> <itemNo> <right|wrong|self> [confirm]');
    expect(await r.execute('crla-timer-start $a 1 2026-11-27T25:00:00'),
        '"2026-11-27T25:00:00" is not a real time (YYYY-MM-DDTHH:MM:SS, optionally +08:00)');
    expect(await r.execute('crla-word $a 3'), 'crla-word failed: Start the timer on a story first.');
    expect(await r.execute('crla-timer-stop $a'), 'crla-timer-stop failed: Start the timer on a story first.');
    expect(await r.execute('crla-observe $a observation=2'), 'crla-observe failed: Time the story first.');
  });
}
