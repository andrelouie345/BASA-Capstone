// The Phil-IRI reading screen given from the device (spec
// docs/superpowers/specs/2026-11-28-digitized-assessment-screens-design.md):
// the miscue drawer (tap a word; tapping outside saves nothing) and the
// reading timer.
import 'dart:io';

import 'package:basa_capstone/core/models/phil_iri_assessment.dart' show PhilIriRound;
import 'package:basa_capstone/core/models/phil_iri_reading.dart' show PhilIriReadingMethod;
import 'package:basa_capstone/core/models/phil_iri_miscue.dart';
import 'package:basa_capstone/core/wiring/app_context.dart';
import 'package:basa_capstone/core/wiring/wire_shared.dart';
import 'package:basa_capstone/core/wiring/wire_tutor.dart';
import 'package:basa_capstone/ui/basa_scope.dart';
import 'package:basa_capstone/ui/phil_iri/reading_screen.dart';
import 'package:basa_capstone/ui/common/screen_kit.dart' show LoadingNote;
import 'package:basa_capstone/ui/theme/basa_theme.dart';
import 'package:basa_capstone/viewmodels/app_viewmodels.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../helpers/offline_owner.dart';

const _year = '2026-2027';
const _passage = 'The boat drifted slowly toward the shore while the fishermen pulled their nets';

late AppContext _ctx;
late TutorVms _t;
late AppViewModels _vms;
var _nextStudent = 900;

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// A new learner's BOSY session with an untimed reading of the passage.
Future<({int session, int reading})> _reading({PhilIriReadingMethod method = PhilIriReadingMethod.wholeText}) async {
  final student = _nextStudent++;
  await _ctx.localDb.insert('students', {'id': student, 'lrn': '77777777$student', 'last_name': 'CRUZ', 'first_name': 'Ana', 'school_id': 1});
  await _ctx.localDb.insert('enrollments', {'student_id': student, 'section_id': 93, 'school_year': _year, 'status': 'active'});
  final s = await _t.philIriVm.startSession(studentId: student, sectionId: 93, schoolYear: _year, round: PhilIriRound.bosy);
  final r = await _t.philIriVm.startReading(assessmentId: s.id!, passageId: 601, method: method);
  return (session: s.id!, reading: r.id!);
}

Future<void> _open(WidgetTester tester, ({int session, int reading}) r) async {
  await tester.binding.setSurfaceSize(const Size(400, 860));
  await tester.pumpWidget(BasaScope(
    vms: _vms,
    child: MaterialApp(
      theme: basaThemeData(Brightness.light),
      home: PhilIriReadingScreen(assessmentId: r.session, readingId: r.reading),
    ),
  ));
  await _settle(tester);
}

Future<void> _tapWord(WidgetTester tester, String word) async {
  final w = find.text(word).first;
  await tester.ensureVisible(w);
  await tester.pump();
  await tester.tap(w);
  await _settle(tester);
}

void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    _ctx = await AppContext.open(dataDir: Directory.systemTemp.createTempSync('basa_pi_reading_ui_').path);
    final s = wireShared(_ctx);
    _t = wireTutor(_ctx, s);
    _vms = appViewModels(_ctx, s, _t);
    final db = _ctx.localDb;
    await db.insert('schools', {'id': 1, 'school_id': 'ZZRUI', 'school_name': 'ZZ reading UI'});
    await seedOfflineOwner(db, userId: '00000000-0000-0000-0000-0000000000r1', email: 'rui@test', role: 'coordinator', schoolId: 1);
    await db.insert('sections', {'id': 93, 'school_id': 1, 'school_year': _year, 'grade_level': '7', 'section_name': 'S93'});
    await db.insert('phil_iri_collections', {'id': 1, 'name': 'Graded UI', 'is_grade_leveled': 1, 'has_comprehension': 1});
    await db.insert('phil_iri_passages', {
      'id': 601, 'collection_id': 1, 'level': 7, 'title': 'The boat', 'body': _passage,
      'word_count': _passage.split(' ').length, 'is_active': 1,
    });
    expect(await _ctx.authVm.signInOffline(email: 'rui@test', password: 'test-pw'), isNull);
  });

  group('miscue drawer', () {
    testWidgets('tap opens the drawer', (tester) async {
      await _open(tester, (await tester.runAsync(_reading))!);
      await _tapWord(tester, 'boat');
      expect(find.byType(BottomSheet), findsOneWidget);
      for (final t in PhilIriMiscueType.values) {
        expect(find.descendant(of: find.byType(BottomSheet), matching: find.text(t.label)), findsOneWidget);
      }
      expect(find.text('Self-corrected (recorded, not counted)'), findsOneWidget);
      expect(find.text('Done'), findsOneWidget);
    });

    testWidgets('pick and done saves', (tester) async {
      final r = (await tester.runAsync(_reading))!;
      await _open(tester, r);
      await _tapWord(tester, 'boat');
      await tester.tap(find.descendant(of: find.byType(BottomSheet), matching: find.text(PhilIriMiscueType.omission.label)));
      await tester.pump();
      await tester.tap(find.text('Done'));
      await _settle(tester);
      expect(find.byType(BottomSheet), findsNothing);
      final m = await tester.runAsync(() => _t.philIriVm.miscues(r.reading));
      expect(m!.map((x) => (x.wordIndex, x.type)), [(1, PhilIriMiscueType.omission)]);
    });

    testWidgets('outside tap saves nothing', (tester) async {
      final r = (await tester.runAsync(_reading))!;
      await _open(tester, r);
      await _tapWord(tester, 'boat');
      await tester.tapAt(const Offset(200, 20));
      await _settle(tester);
      expect(find.byType(BottomSheet), findsNothing);
      expect(await tester.runAsync(() => _t.philIriVm.miscues(r.reading)), isEmpty);
    });

    testWidgets('outside tap on a marked word keeps it', (tester) async {
      final r = (await tester.runAsync(_reading))!;
      await tester.runAsync(() =>
          _t.philIriVm.markMiscue(readingId: r.reading, wordIndex: 1, type: PhilIriMiscueType.substitution));
      await _open(tester, r);
      await _tapWord(tester, 'boat');
      await tester.tap(find.descendant(of: find.byType(BottomSheet), matching: find.text(PhilIriMiscueType.omission.label)));
      await tester.pump();
      await tester.tapAt(const Offset(200, 20));
      await _settle(tester);
      final m = await tester.runAsync(() => _t.philIriVm.miscues(r.reading));
      expect(m!.single.type, PhilIriMiscueType.substitution);
    });

    testWidgets('remove', (tester) async {
      final r = (await tester.runAsync(_reading))!;
      await tester.runAsync(() =>
          _t.philIriVm.markMiscue(readingId: r.reading, wordIndex: 1, type: PhilIriMiscueType.substitution));
      await _open(tester, r);
      await _tapWord(tester, 'boat');
      await tester.tap(find.text('Remove miscue'));
      await _settle(tester);
      expect(await tester.runAsync(() => _t.philIriVm.miscues(r.reading)), isEmpty);
    });
  });

  group('timer bar', () {
    Finder button(String label) =>
        find.ancestor(of: find.text(label), matching: find.byWidgetPredicate((w) => w is ButtonStyleButton));

    Future<void> tap(WidgetTester tester, String label) async {
      final f = button(label).first;
      await tester.ensureVisible(f);
      await tester.pump();
      await tester.tap(f);
      await _settle(tester);
    }


    testWidgets('not timed yet', (tester) async {
      await _open(tester, (await tester.runAsync(_reading))!);
      expect(find.text('00:00'), findsOneWidget);
      expect(button('Start'), findsOneWidget);
      expect(find.text('Enter the time'), findsOneWidget);
    });

    testWidgets('start', (tester) async {
      await _open(tester, (await tester.runAsync(_reading))!);
      await tap(tester, 'Start');
      expect(button('Pause'), findsOneWidget);
      expect(button('Stop'), findsOneWidget);
      expect(find.text('Enter the time'), findsNothing);
      expect(find.text('Timed in BASA'), findsOneWidget);
    });

    testWidgets('one minute has no Stop', (tester) async {
      await _open(tester, (await tester.runAsync(() => _reading(method: PhilIriReadingMethod.oneMinute)))!);
      await tap(tester, 'Start');
      expect(button('Pause'), findsOneWidget);
      expect(button('Stop'), findsNothing);
    });

    testWidgets('pause and resume', (tester) async {
      await _open(tester, (await tester.runAsync(_reading))!);
      await tap(tester, 'Start');
      await tap(tester, 'Pause');
      expect(button('Resume'), findsOneWidget);
      expect(button('Stop'), findsOneWidget);
      await tap(tester, 'Resume');
      expect(button('Pause'), findsOneWidget);
    });

    testWidgets('stop whole text', (tester) async {
      final r = (await tester.runAsync(_reading))!;
      await tester.runAsync(() => _t.philIriVm.startTimer(r.reading, at: DateTime.now().subtract(const Duration(seconds: 40))));
      await _open(tester, r);
      await tap(tester, 'Stop');
      expect(button('Restart'), findsOneWidget);
      final rows = await tester.runAsync(() => _t.philIriVm.readings(r.session));
      expect(rows!.single.readingSeconds, inInclusiveRange(39, 45));
    });

    testWidgets('restart asks', (tester) async {
      final r = (await tester.runAsync(_reading))!;
      await tester.runAsync(() async {
        await _t.philIriVm.startTimer(r.reading, at: DateTime.now().subtract(const Duration(seconds: 20)));
        await _t.philIriVm.stopTimer(r.reading);
      });
      await _open(tester, r);
      await tap(tester, 'Restart');
      expect(find.text('Time this reading again?'), findsOneWidget);
      expect(find.text('The first timing stays in the record.'), findsOneWidget);
      await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('Restart')));
      await _settle(tester);
      expect(button('Start'), findsOneWidget);
      expect(find.text('00:00'), findsOneWidget);
    });

    testWidgets('reopen a running reading', (tester) async {
      final r = (await tester.runAsync(_reading))!;
      await tester.runAsync(() => _t.philIriVm.startTimer(r.reading, at: DateTime.now().subtract(const Duration(seconds: 30))));
      await _open(tester, r);
      expect(button('Pause'), findsOneWidget);
      expect(find.textContaining(RegExp(r'^00:3\d$')), findsOneWidget);
    });

    testWidgets('one minute past 60 s on open', (tester) async {
      final r = (await tester.runAsync(() => _reading(method: PhilIriReadingMethod.oneMinute)))!;
      await tester.runAsync(() => _t.philIriVm.startTimer(r.reading, at: DateTime.now().subtract(const Duration(seconds: 70))));
      await _open(tester, r);
      expect(find.text('Tap the last word the learner read'), findsOneWidget);
      await _tapWord(tester, 'shore');
      expect(find.byType(BottomSheet), findsNothing);
      expect(find.text('Tap the last word the learner read'), findsNothing);
      final rows = await tester.runAsync(() => _t.philIriVm.readings(r.session));
      expect(rows!.single.wordsRead, isNotNull);
    });
  });

  // Final review C1: marking a miscue keeps the page where it is.
  testWidgets('marking a late word keeps the scroll position', (tester) async {
    final r = (await tester.runAsync(_reading))!;
    await _open(tester, r);
    final word = find.text('nets');
    await tester.ensureVisible(word);
    await tester.pump();
    final before = tester.state<ScrollableState>(find.ancestor(of: word, matching: find.byType(Scrollable)).first).position.pixels;
    expect(before, greaterThan(0));
    await tester.tap(word);
    await _settle(tester);
    await tester.tap(find.text('Done'));
    // No spinner in place of the page while the miscue is saved (no blink).
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pump(const Duration(milliseconds: 20));
      expect(find.byType(LoadingNote), findsNothing);
    }
    await _settle(tester);
    expect(tester.state<ScrollableState>(find.ancestor(of: find.text('nets'), matching: find.byType(Scrollable)).first).position.pixels,
        before);
  });

  // Final review I2: Start on a reading timed on paper asks before it replaces the typed time.
  testWidgets('start on a typed time asks first', (tester) async {
    final r = (await tester.runAsync(() async {
      final r = await _reading();
      await _t.philIriVm.saveTiming(r.reading, readingSeconds: 80);
      return r;
    }))!;
    await _open(tester, r);
    final start = find.ancestor(of: find.text('Start'), matching: find.byWidgetPredicate((w) => w is ButtonStyleButton)).first;
    await tester.ensureVisible(start);
    await tester.pump();
    await tester.tap(start);
    await _settle(tester);
    expect(find.text('This replaces the typed time (80 s).'), findsOneWidget);
    await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('Cancel')));
    await _settle(tester);
    final rows = await tester.runAsync(() => _t.philIriVm.readings(r.session));
    expect(rows!.single.readingSeconds, 80);
    expect((await tester.runAsync(() => _t.philIriVm.timer(r.reading)))!.events, isEmpty);
  });
}
