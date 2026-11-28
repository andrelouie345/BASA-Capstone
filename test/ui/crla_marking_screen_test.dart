// The digitized CRLA marking screen (spec
// docs/superpowers/specs/2026-11-28-digitized-assessment-screens-design.md):
// opened with "Mark in BASA" where the region has a form; Part 1 items,
// the Task 2 confirm, story words, questions; refusals shown as they come.
import 'dart:io';

import 'package:basa_capstone/core/models/crla_form.dart';
import 'package:basa_capstone/core/wiring/app_context.dart';
import 'package:basa_capstone/core/wiring/wire_shared.dart';
import 'package:basa_capstone/core/wiring/wire_tutor.dart';
import 'package:basa_capstone/ui/basa_scope.dart';
import 'package:basa_capstone/ui/crla/crla_entry_screen.dart';
import 'package:basa_capstone/ui/crla/crla_marking_screen.dart';
import 'package:basa_capstone/ui/common/screen_kit.dart' show LoadingNote;
import 'package:basa_capstone/ui/theme/basa_theme.dart';
import 'package:basa_capstone/viewmodels/app_viewmodels.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../helpers/offline_owner.dart';

const _school = 9901;
const _g2 = 9902, _g1 = 9903, _g3 = 9904;
const _year = '2026-2027';

late AppContext _ctx;
late TutorVms _t;
late AppViewModels _vms;
var _nextId = 9900, _nextStudent = 9900;

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// A pulled MOSY attempt of a new learner in [section] (Filipino, or English).
Future<int> _attempt({int section = _g2, bool english = false}) async {
  final s = ++_nextStudent, id = ++_nextId;
  await _ctx.localDb.insert('students', {'id': s, 'lrn': '9999999$s', 'last_name': 'CRUZ', 'first_name': 'Ana', 'school_id': _school});
  await _ctx.localDb.insert('enrollments', {'student_id': s, 'section_id': section, 'school_year': _year, 'status': 'active'});
  await _ctx.localDb.insert('crla_assessments', {
    'id': id, 'student_id': s, 'school_id': _school, 'section_id': section, 'school_year': _year,
    'subject_variant': english ? 'eng' : 'fil', 'language': english ? 'English' : 'Tagalog', 'round': 'mosy', 'attempt_no': 1, 'assessed_at': '2026-11-28',
    'origin': 'cloud', 'row_version': 1,
  });
  return id;
}

Future<void> _open(WidgetTester tester, Widget screen) async {
  await tester.binding.setSurfaceSize(const Size(400, 860));
  await tester.pumpWidget(BasaScope(
    vms: _vms,
    child: MaterialApp(theme: basaThemeData(Brightness.light), home: screen),
  ));
  await _settle(tester);
}

Future<void> _tap(WidgetTester tester, Finder f, {bool long = false}) async {
  await tester.ensureVisible(f.first);
  await tester.pump();
  long ? await tester.longPress(f.first) : await tester.tap(f.first);
  await _settle(tester);
}

Finder _button(String label) =>
    find.ancestor(of: find.text(label), matching: find.byWidgetPredicate((w) => w is ButtonStyleButton));

Future<CrlaDigitizedState> _state(WidgetTester tester, int a) async => (await tester.runAsync(() => _t.crlaVm.digitized(a)))!;

void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    _ctx = await AppContext.open(dataDir: Directory.systemTemp.createTempSync('basa_crla_marking_ui_').path);
    final s = wireShared(_ctx);
    _t = wireTutor(_ctx, s);
    _vms = appViewModels(_ctx, s, _t);
    final db = _ctx.localDb;
    await db.insert('schools', {'id': _school, 'school_id': 'ZZCMU', 'school_name': 'ZZ CRLA marking', 'region_id': 10});
    for (final (id, grade) in [(_g2, '2'), (_g1, '1'), (_g3, '3')]) {
      await db.insert('sections', {'id': id, 'school_id': _school, 'school_year': _year, 'grade_level': grade, 'section_name': 'S$id'});
    }
    // Region 10, Tagalog Grade 2 only (Grade 1 has no form): Task 1, Task 2 low and high, 10 items each.
    var item = 0;
    for (final task in ['task1', 'task2_low', 'task2_high']) {
      for (var n = 1; n <= 10; n++) {
        await db.insert('crla_part1_items',
            {'id': ++item, 'region_id': 10, 'language': 'Tagalog', 'grade': 2, 'task': task, 'item_no': n, 'text': '$task-$n'});
      }
    }
    // English Grade 3: Task 1 + Task 2 and a story (English Task 1 = 0 ends the test).
    for (final task in ['task1', 'task2']) {
      for (var n = 1; n <= 10; n++) {
        await db.insert('crla_part1_items',
            {'id': ++item, 'region_id': 10, 'language': 'English', 'grade': 3, 'task': task, 'item_no': n, 'text': 'e$task-$n'});
      }
    }
    await db.insert('crla_stories', {
      'id': 9903, 'region_id': 10, 'language': 'English', 'grade': 3, 'story_no': 1, 'title': 'The Ten', 'word_count': 10,
      'body': [for (var w = 0; w < 10; w++) 'e$w'].join(' '),
    });
    await db.insert('crla_stories', {
      'id': 9902, 'region_id': 10, 'language': 'Tagalog', 'grade': 2, 'story_no': 1, 'title': 'Ang Dalawampu', 'word_count': 20,
      'body': '${[for (var w = 0; w < 10; w++) 't$w'].join(' ')}\n${[for (var w = 10; w < 20; w++) 't$w'].join(' ')}',
    });
    for (var n = 1; n <= 6; n++) {
      await db.insert('crla_story_questions',
          {'id': n, 'story_id': 9902, 'question_no': n, 'after_sentence': 1, 'question': 'Question $n?', 'accepted_answers': 'Answer $n'});
    }
    await seedOfflineOwner(db, userId: '00000000-0000-0000-0000-0000000000cm', email: 'cm@test', role: 'coordinator', schoolId: _school);
    expect(await _ctx.authVm.signInOffline(email: 'cm@test', password: 'test-pw'), isNull);
  });

  testWidgets('button with a form', (tester) async {
    final a = (await tester.runAsync(_attempt))!;
    await _open(tester, CrlaEntryScreen(assessmentId: a));
    expect(_button('Mark in BASA'), findsOneWidget);
    await _tap(tester, _button('Mark in BASA'));
    expect(find.byType(CrlaMarkingScreen), findsOneWidget);
  });

  testWidgets('no button without a form', (tester) async {
    final a = (await tester.runAsync(() => _attempt(section: _g1)))!;
    await _open(tester, CrlaEntryScreen(assessmentId: a));
    expect(_button('Mark in BASA'), findsNothing);
  });

  testWidgets('part 1', (tester) async {
    final a = (await tester.runAsync(_attempt))!;
    await _open(tester, CrlaMarkingScreen(assessmentId: a));
    expect(find.text('1. task1-1'), findsOneWidget);
    await _tap(tester, find.byKey(const Key('item-task1-1-right')));
    await _tap(tester, find.byKey(const Key('item-task1-2-wrong')));
    expect(find.textContaining('1/10'), findsWidgets);
    await _tap(tester, _button('Done with Task 1'));
    expect(find.text('8 items not marked will count as wrong.'), findsOneWidget);
    await _tap(tester, find.descendant(of: find.byType(AlertDialog), matching: find.text('Done')));
    final s = await _state(tester, a);
    expect((s.task1Done, s.task1Score, s.task2), (true, 1, CrlaTask.task2Low));
    expect(find.textContaining('Task 2 low'), findsWidgets);
    expect(find.text('1. task2_low-1'), findsOneWidget);
  });

  testWidgets('task 2 confirm', (tester) async {
    final a = (await tester.runAsync(() async {
      final a = await _attempt();
      for (var n = 1; n <= 6; n++) {
        await _t.crlaVm.markItem(a, CrlaTask.task1, n, correct: true);
      }
      await _t.crlaVm.closeTask(a, CrlaTask.task1); // 6: Task 2 low
      await _t.crlaVm.markItem(a, CrlaTask.task2Low, 1, correct: true); // Task 2 low has a mark
      return a;
    }))!;
    await _open(tester, CrlaMarkingScreen(assessmentId: a));
    await _tap(tester, find.byKey(const Key('item-task1-7-right'))); // 7: Task 2 high
    expect(find.text('This changes which Task 2 is given; confirm to clear its marks.'), findsOneWidget);
    await _tap(tester, find.descendant(of: find.byType(AlertDialog), matching: find.text('Confirm')));
    final s = await _state(tester, a);
    expect((s.task1Score, s.task2), (7, CrlaTask.task2High));
  });

  testWidgets('story', (tester) async {
    final a = (await tester.runAsync(_attempt))!;
    await _open(tester, CrlaMarkingScreen(assessmentId: a));
    await _tap(tester, _button('Start'));
    expect(_button('Pause'), findsOneWidget);
    expect(_button('Stop'), findsOneWidget);
    await _tap(tester, find.text('t3'));
    expect((await _state(tester, a)).miscues, 1);
    await _tap(tester, find.text('t3'));
    expect((await _state(tester, a)).miscues, 0);
    await _tap(tester, find.text('t4'), long: true);
    final s = await _state(tester, a);
    expect(s.miscues, 0);
    expect(s.evidence.words.map((w) => (w.wordIndex, w.kind)), [(4, CrlaWordMarkKind.selfCorrected)]);
  });

  testWidgets('question', (tester) async {
    final a = (await tester.runAsync(() async {
      final a = await _attempt();
      await _t.crlaVm.startStoryTimer(a, 1, at: DateTime.now().subtract(const Duration(seconds: 30)));
      await _t.crlaVm.stopStoryTimer(a);
      return a;
    }))!;
    await _open(tester, CrlaMarkingScreen(assessmentId: a));
    expect(find.text('1. Question 1?'), findsOneWidget);
    expect(find.textContaining('Answer 1'), findsOneWidget);
    await _tap(tester, find.byKey(const Key('q-1-correct')));
    expect((await _state(tester, a)).comprehension, 1);
  });

  testWidgets('refusal shown', (tester) async {
    final a = (await tester.runAsync(_attempt))!;
    await _open(tester, CrlaMarkingScreen(assessmentId: a));
    await _tap(tester, find.text('t3')); // before the timer starts
    expect(find.text('Start the timer on a story first.'), findsOneWidget);
    await _tap(tester, _button('Start'));
    expect(_button('Pause'), findsOneWidget);
  });

  // Final review C1: marking keeps the page where it is (no spinner, no jump to the top).
  testWidgets('marking a late word keeps the scroll position', (tester) async {
    final a = (await tester.runAsync(_attempt))!;
    await _open(tester, CrlaMarkingScreen(assessmentId: a));
    await _tap(tester, _button('Start'));
    final word = find.text('t15');
    await tester.ensureVisible(word);
    await tester.pump();
    final scroll = find.ancestor(of: word, matching: find.byType(Scrollable)).first;
    final before = tester.state<ScrollableState>(scroll).position.pixels;
    expect(before, greaterThan(0));
    await tester.tap(word);
    // No spinner in place of the page while the mark is saved (no blink).
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pump(const Duration(milliseconds: 20));
      expect(find.byType(LoadingNote), findsNothing);
    }
    await _settle(tester);
    expect(tester.state<ScrollableState>(find.ancestor(of: find.text('t15'), matching: find.byType(Scrollable)).first).position.pixels,
        before);
    expect((await _state(tester, a)).miscues, 1);
  });

  // Final review (re-graded): a stray "Done" doesn't fill Task 1 with wrongs.
  testWidgets('done with unmarked items asks first', (tester) async {
    final a = (await tester.runAsync(_attempt))!;
    await _open(tester, CrlaMarkingScreen(assessmentId: a));
    await _tap(tester, _button('Done with Task 1'));
    expect(find.text('10 items not marked will count as wrong.'), findsOneWidget);
    await _tap(tester, find.descendant(of: find.byType(AlertDialog), matching: find.text('Cancel')));
    expect((await _state(tester, a)).task1Done, isFalse);
  });

  // Review focus: an attempt with typed totals can't be marked.
  testWidgets('typed totals: no Mark in BASA', (tester) async {
    final a = (await tester.runAsync(() async {
      final a = await _attempt();
      await _t.crlaVm.savePart1Standard(assessmentId: a, task1Score: 5, task2LowScore: 3);
      return a;
    }))!;
    await _open(tester, CrlaEntryScreen(assessmentId: a));
    expect(_button('Mark in BASA'), findsNothing);
  });

  // Owner 2026-11-28: when Task 1 ends the test, Part 2 is hidden (as on paper).
  testWidgets('test ends at Task 1: no Part 2', (tester) async {
    final a = (await tester.runAsync(() async {
      final a = await _attempt(section: _g3, english: true);
      await _t.crlaVm.closeTask(a, CrlaTask.task1); // nothing right: English Task 1 = 0
      return a;
    }))!;
    await _open(tester, CrlaMarkingScreen(assessmentId: a));
    expect(find.text('No Task 2: the test ends at Task 1.'), findsOneWidget);
    expect(_button('Start'), findsNothing);
    expect(find.text('e3'), findsNothing);
  });
}
