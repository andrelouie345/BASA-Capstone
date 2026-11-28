// v51 (cloud 20261127010000; spec 2026-11-27 digitized CRLA D1, D3-D6, D10):
// the content tables, the four evidence tables and their rules on the device,
// pulled taps can't change, an attempt's evidence goes with it, and the
// tables are synced after the attempt.
import 'dart:io';

import 'package:basa_capstone/core/data/local/crla_digitized_repository_sqlite.dart';
import 'package:basa_capstone/core/data/local/crla_assessment_repository_sqlite.dart';
import 'package:basa_capstone/core/data/local/local_database.dart';
import 'package:basa_capstone/core/data/local/sync_local_writes.dart';
import 'package:basa_capstone/core/data/pull_tables.dart';
import 'package:basa_capstone/core/models/crla_marks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _year = '2026-2027';

void main() {
  late Database db;
  late CrlaDigitizedRepositorySqlite repo;
  final dir = Directory.systemTemp.createTempSync('basa_v51_').path;
  var learner = 800;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    db = await LocalDatabase.instance(dir);
    repo = CrlaDigitizedRepositorySqlite(db);
    await db.insert('schools', {'id': 1, 'school_id': 'ZZ51', 'school_name': 'ZZ v51', 'region_id': 13});
    await db.insert('sections', {'id': 51, 'school_id': 1, 'school_year': _year, 'grade_level': '3', 'section_name': 'S51'});
    await db.insert('sections', {'id': 52, 'school_id': 1, 'school_year': _year, 'grade_level': '2', 'section_name': 'S52'});
  });

  Future<int> localId() async => -(await db.rawInsert("INSERT INTO local_ids (made_at) VALUES (datetime('now'))"));

  /// A new (device) attempt of a new learner: English Grade 3 or Filipino Grade 2.
  Future<int> attempt({String variant = 'eng'}) async {
    final student = ++learner;
    final section = variant == 'eng' ? 51 : 52;
    await db.insert('students', {'id': student, 'lrn': '88888888$student', 'last_name': 'L', 'first_name': 'F', 'school_id': 1});
    await db.insert('enrollments', {'student_id': student, 'section_id': section, 'school_year': _year, 'status': 'active'});
    final id = await localId();
    await db.insert('crla_assessments', {
      'id': id, 'student_id': student, 'school_id': 1, 'section_id': section, 'school_year': _year,
      'subject_variant': variant, 'language': variant == 'eng' ? 'English' : 'Tagalog', 'round': 'bosy',
      'assessed_at': '2026-07-01', 'origin': 'local',
    });
    return id;
  }

  final t0 = DateTime.parse('2026-07-01T09:00:00+08:00');
  CrlaTimerEvent tap(int a, int seq, TimerTapKind kind, int s) =>
      CrlaTimerEvent(assessmentId: a, storyNo: 1, seq: seq, kind: kind, at: t0.add(Duration(seconds: s)));
  CrlaPart1Mark mark(int a, CrlaTask t, int n, bool ok) => CrlaPart1Mark(assessmentId: a, task: t, itemNo: n, correct: ok);
  CrlaWordMark word(int a, int i, {int story = 1}) =>
      CrlaWordMark(assessmentId: a, storyNo: story, wordIndex: i, kind: CrlaWordMarkKind.miscue);

  test('the database is v51 with the tables and columns', () async {
    expect((await db.rawQuery('PRAGMA user_version')).first.values.first, 51);
    Future<Set<Object?>> cols(String t) async => {for (final c in await db.rawQuery('PRAGMA table_info($t)')) c['name']};
    expect(await cols('crla_part1_marks'), containsAll(['assessment_id', 'task', 'item_no', 'correct', 'self_corrected', 'row_version']));
    expect(await cols('crla_part2_word_marks'), containsAll(['story_no', 'word_index', 'kind']));
    expect(await cols('crla_part2_answers'), containsAll(['question_no', 'mark']));
    expect(await cols('crla_timer_events'), containsAll(['seq', 'kind', 'at']));
    expect(await cols('crla_part1_items'), containsAll(['task', 'item_no', 'text', 'sentence_no', 'answer_key']));
    expect(await cols('crla_story_questions'), containsAll(['story_id', 'question_no', 'after_sentence', 'accepted_answers']));
    expect(await cols('crla_stories'), contains('body'));
    expect(await cols('crla_part2_fluency'), contains('last_word_reached'));
  });

  test('marks stored and read back (new rows get negative ids)', () async {
    final a = await attempt();
    await repo.setPart1Mark(mark(a, CrlaTask.task1, 1, true));
    await repo.setPart1Mark(mark(a, CrlaTask.task1, 1, false)); // the same item marked again
    await repo.setWordMark(word(a, 4));
    await repo.setAnswer(CrlaAnswer(assessmentId: a, storyNo: 1, questionNo: 2, mark: CrlaAnswerMark.notAsked));
    await repo.insertTimerEvent(tap(a, 1, TimerTapKind.start, 0));
    final e = await repo.evidence(a);
    expect(e.part1.single.correct, isFalse);
    expect(e.words.single.wordIndex, 4);
    expect(e.answers.single.mark, CrlaAnswerMark.notAsked);
    expect(e.timer.single.kind, TimerTapKind.start);
    expect([...e.part1.map((m) => m.id!), ...e.words.map((m) => m.id!), ...e.timer.map((m) => m.id!)].every((id) => id < 0), isTrue);
    expect(await repo.hasEvidence(a), isTrue);
    await repo.deleteWordMark(a, 4);
    expect((await repo.evidence(a)).words, isEmpty);
  });

  test('trigger refuses task2_low after task 1 score 8', () async {
    final a = await attempt(variant: 'fil');
    for (var i = 1; i <= 10; i++) {
      await repo.setPart1Mark(mark(a, CrlaTask.task1, i, i <= 8));
    }
    await expectLater(repo.setPart1Mark(mark(a, CrlaTask.task2Low, 1, true)),
        throwsA(predicate((e) => '$e'.contains("This Task 2 is not the one Task 1 leads to."))));
    await repo.setPart1Mark(mark(a, CrlaTask.task2High, 1, true));
  });

  test('English: no Task 2 after Task 1 = 0', () async {
    final a = await attempt();
    await repo.setPart1Mark(mark(a, CrlaTask.task1, 1, false));
    await expectLater(repo.setPart1Mark(mark(a, CrlaTask.task2, 1, true)),
        throwsA(predicate((e) => '$e'.contains('Task 1 is 0: the test ends here.'))));
  });

  test('word mark after last_word_reached refused; one story per attempt', () async {
    final a = await attempt();
    await db.insert('crla_part2_fluency', {
      'assessment_id': a, 'story_no': 1, 'miscues': 0, 'words_read': 60, 'time_minutes': 2, 'time_seconds': 0,
      'comprehension_correct': 0, 'last_word_reached': 59,
    });
    await expectLater(repo.setWordMark(word(a, 70)),
        throwsA(predicate((e) => '$e'.contains('That word is after the last word reached.'))));
    await repo.setWordMark(word(a, 10));
    await expectLater(repo.setWordMark(word(a, 11, story: 2)),
        throwsA(predicate((e) => '$e'.contains('This attempt is marked on its other story.'))));
  });

  test('timer order and clock rules on the device', () async {
    final a = await attempt();
    await expectLater(repo.insertTimerEvent(tap(a, 1, TimerTapKind.pause, 0)),
        throwsA(predicate((e) => '$e'.contains('Start the timer first.'))));
    await repo.insertTimerEvent(tap(a, 1, TimerTapKind.start, 100));
    await expectLater(repo.insertTimerEvent(tap(a, 2, TimerTapKind.stop, 50)),
        throwsA(predicate((e) => '$e'.contains("earlier than the timer's last tap"))));
    await repo.insertTimerEvent(tap(a, 2, TimerTapKind.reset, 50)); // restart after a clock jump
    await repo.insertTimerEvent(tap(a, 3, TimerTapKind.start, 60));
    await repo.insertTimerEvent(tap(a, 4, TimerTapKind.stop, 90));
    await expectLater(repo.insertTimerEvent(tap(a, 5, TimerTapKind.stop, 91)),
        throwsA(predicate((e) => '$e'.contains('The timer is already stopped.'))));
  });

  test('a pulled tap cannot be changed or deleted', () async {
    final a = await attempt();
    await db.transaction((txn) => withSyncBypass(txn, () async {
          await txn.insert('crla_timer_events', {
            'id': 9101, 'assessment_id': a, 'story_no': 1, 'seq': 1, 'kind': 'start',
            'at': '2026-07-01T09:00:00.000+08:00', 'row_version': 1,
          });
        }));
    await expectLater(db.update('crla_timer_events', {'kind': 'pause'}, where: 'id = 9101'), throwsA(anything));
    await expectLater(db.delete('crla_timer_events', where: 'id = 9101'), throwsA(anything));
  });

  test('deleting a device attempt removes its evidence, unjournaled', () async {
    final a = await attempt();
    await repo.setPart1Mark(mark(a, CrlaTask.task1, 1, true));
    await repo.insertTimerEvent(tap(a, 1, TimerTapKind.start, 0));
    await CrlaAssessmentRepositorySqlite(db).deleteNew(a);
    expect(await repo.hasEvidence(a), isFalse);
    expect(await db.query('sync_changes', where: "table_name LIKE 'crla_%'"), isEmpty);
  });

  test('content is read back for a form and a story', () async {
    await db.insert('crla_stories', {'id': 701, 'region_id': 13, 'language': 'English', 'grade': 3, 'story_no': 1,
      'title': 'Para the Parrot', 'word_count': 3, 'body': 'Para flies away.'});
    await db.insert('crla_part1_items', {'id': 1, 'region_id': 13, 'language': 'English', 'grade': 3, 'task': 'task1',
      'item_no': 1, 'text': 'bed'});
    await db.insert('crla_story_questions', {'id': 1, 'story_id': 701, 'question_no': 1, 'after_sentence': 1,
      'question': 'Who flies?', 'accepted_answers': 'Para'});
    expect((await repo.part1Items(regionId: 13, language: 'English', grade: 3)).single.text, 'bed');
    expect(await repo.storyBody(701), 'Para flies away.');
    expect((await repo.questions(701)).single.acceptedAnswers, 'Para');
  });

  test('the tables are synced and pulled after crla_assessments', () {
    const tables = ['crla_part1_marks', 'crla_part2_word_marks', 'crla_part2_answers', 'crla_timer_events'];
    final synced = syncedTables.keys.toList(), pull = pullOrder.keys.toList();
    for (final t in tables) {
      expect(synced.indexOf(t), greaterThan(synced.indexOf('crla_assessments')), reason: t);
      expect(syncedParents[t], ('crla_assessments', 'assessment_id'), reason: t);
      expect(pull.indexOf(t), greaterThan(pull.indexOf('crla_assessments')), reason: t);
      expect(pullClearOrder.indexOf(t), lessThan(pullClearOrder.indexOf('crla_assessments')), reason: t);
    }
    expect(pull, containsAll(['crla_part1_items', 'crla_story_questions']));
    expect(pullClearOrder.indexOf('crla_story_questions'), lessThan(pullClearOrder.indexOf('crla_stories')));
  });
}
