// A Phil-IRI reading timed in BASA (spec 2026-11-26 timed reading, plan Task 4):
// the timer calls, the seconds and words read they save, and the refusals.
import 'dart:io';

import 'package:basa_capstone/core/models/phil_iri_assessment.dart' show PhilIriRound;
import 'package:basa_capstone/core/models/phil_iri_reading.dart' show PhilIriReadingMethod;
import 'package:basa_capstone/core/models/phil_iri_timer_event.dart';
import 'package:basa_capstone/core/wiring/app_context.dart';
import 'package:basa_capstone/core/wiring/wire_shared.dart';
import 'package:basa_capstone/core/wiring/wire_tutor.dart';
import 'package:basa_capstone/viewmodels/viewmodel_exception.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../helpers/offline_owner.dart';

const _year = '2026-2027';

void main() {
  late AppContext ctx;
  late TutorVms t;
  final dir = Directory.systemTemp.createTempSync('basa_pi_timer_').path;
  var nextStudent = 900;
  final t0 = DateTime.parse('2026-07-01T09:00:00+08:00');
  DateTime at(int s) => t0.add(Duration(seconds: s));

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    ctx = await AppContext.open(dataDir: dir);
    t = wireTutor(ctx, wireShared(ctx));
    final db = ctx.localDb;
    await db.insert('schools', {'id': 1, 'school_id': 'ZZ49T', 'school_name': 'ZZ timer'});
    await seedOfflineOwner(db,
        userId: '00000000-0000-0000-0000-00000000ab49', email: 'timer@test', role: 'coordinator', schoolId: 1);
    await db.insert('sections', {'id': 93, 'school_id': 1, 'school_year': _year, 'grade_level': '7', 'section_name': 'S93'});
    await db.insert('phil_iri_collections', {'id': 1, 'name': 'Graded timer', 'is_grade_leveled': 1, 'has_comprehension': 1});
    for (final id in [601, 602, 603]) {
      await db.insert('phil_iri_passages', {
        'id': id, 'collection_id': 1, 'level': 7, 'title': 'P$id',
        'body': List.filled(100, 'w$id').join(' '), 'word_count': 100, 'is_active': 1,
      });
    }
    expect(await ctx.authVm.signInOffline(email: 'timer@test', password: 'test-pw'), isNull);
  });

  /// A new learner's BOSY session with an untimed reading of passage 601.
  Future<({int session, int reading})> reading({PhilIriReadingMethod method = PhilIriReadingMethod.wholeText}) async {
    final student = nextStudent++;
    await ctx.localDb.insert('students', {'id': student, 'lrn': '77777777$student', 'last_name': 'L', 'first_name': 'F', 'school_id': 1});
    await ctx.localDb.insert('enrollments', {'student_id': student, 'section_id': 93, 'school_year': _year, 'status': 'active'});
    final s = await t.philIriVm.startSession(studentId: student, sectionId: 93, schoolYear: _year, round: PhilIriRound.bosy);
    final r = await t.philIriVm.startReading(assessmentId: s.id!, passageId: 601, method: method);
    return (session: s.id!, reading: r.id!);
  }

  Matcher refusal(String text) => throwsA(isA<ViewModelException>().having((e) => e.message, 'message', contains(text)));

  test('timed whole-text flow saves 107 s', () async {
    final r = await reading();
    await t.philIriVm.startTimer(r.reading, at: at(0));
    await t.philIriVm.pauseTimer(r.reading, at: at(68));
    await t.philIriVm.resumeTimer(r.reading, at: at(99));
    final state = await t.philIriVm.stopTimer(r.reading, at: at(138));
    expect(state.status, PhilIriTimerStatus.stopped);
    expect(state.timedInBasa, isTrue);
    expect(state.events.map((e) => e.kind),
        [PhilIriTimerKind.start, PhilIriTimerKind.pause, PhilIriTimerKind.resume, PhilIriTimerKind.stop]);
    expect((await t.philIriVm.readings(r.session)).first.readingSeconds, 107);
    await t.philIriVm.complete(r.session);
  });

  test('typed flow unchanged', () async {
    final r = await reading();
    await t.philIriVm.saveTiming(r.reading, readingSeconds: 80);
    expect((await t.philIriVm.timer(r.reading)).timedInBasa, isFalse);
    await t.philIriVm.complete(r.session);
  });

  test('saveTiming refused when timed', () async {
    final r = await reading();
    await t.philIriVm.startTimer(r.reading, at: at(0));
    await t.philIriVm.stopTimer(r.reading, at: at(30));
    await expectLater(t.philIriVm.saveTiming(r.reading, readingSeconds: 25),
        refusal('This reading is timed in BASA; restart the timer to time it again.'));
  });

  test('stopTimer twice -> ViewModelException', () async {
    final r = await reading();
    await t.philIriVm.startTimer(r.reading, at: at(0));
    await t.philIriVm.stopTimer(r.reading, at: at(30));
    await expectLater(t.philIriVm.stopTimer(r.reading, at: at(31)), refusal('The timer is already stopped.'));
  });

  test('complete refused while running and while paused', () async {
    final r = await reading();
    await t.philIriVm.startTimer(r.reading, at: at(0));
    await expectLater(t.philIriVm.complete(r.session), refusal('Stop the reading timer'));
    await t.philIriVm.pauseTimer(r.reading, at: at(10));
    await expectLater(t.philIriVm.complete(r.session), refusal('Stop the reading timer'));
  });

  test('reset then complete refused, and the old seconds are cleared', () async {
    final r = await reading();
    await t.philIriVm.startTimer(r.reading, at: at(0));
    await t.philIriVm.stopTimer(r.reading, at: at(40));
    final state = await t.philIriVm.resetTimer(r.reading, at: at(45));
    expect(state.status, PhilIriTimerStatus.none);
    expect(state.timedInBasa, isTrue);
    expect((await t.philIriVm.readings(r.session)).first.readingSeconds, isNull);
    await expectLater(t.philIriVm.complete(r.session), refusal('Record the reading time'));
    // Timed again: the new segment counts.
    await t.philIriVm.startTimer(r.reading, at: at(50));
    await t.philIriVm.stopTimer(r.reading, at: at(95));
    expect((await t.philIriVm.readings(r.session)).first.readingSeconds, 45);
  });

  test('one-minute stop dated at the mark after reopen', () async {
    final r = await reading(method: PhilIriReadingMethod.oneMinute);
    await t.philIriVm.startTimer(r.reading, at: at(0));
    await t.philIriVm.pauseTimer(r.reading, at: at(20));
    await t.philIriVm.resumeTimer(r.reading, at: at(30));
    await expectLater(t.philIriVm.stopTimer(r.reading, at: at(40)), refusal('stops by itself at 60 seconds'));
    // The app reopened 5 minutes later: a new ViewModel over the same data.
    final fresh = wireTutor(ctx, wireShared(ctx)).philIriVm;
    final state = await fresh.timer(r.reading, now: at(300));
    expect(state.status, PhilIriTimerStatus.stopped);
    expect(state.events.last.at.isAtSameMomentAs(at(70)), isTrue); // 60 s of reading + 10 s paused
    expect(state.elapsed, const Duration(seconds: 60));
    expect(state.minuteEndNeeded, isTrue);
    final read = await fresh.setMinuteEnd(r.reading, 41);
    expect(read.wordsRead, 42);
    expect((await fresh.timer(r.reading, now: at(301))).minuteEndNeeded, isFalse);
    await fresh.complete(r.session);
  });

  test('setMinuteEnd beyond the passage refused, and only for a stopped one-minute reading', () async {
    final r = await reading(method: PhilIriReadingMethod.oneMinute);
    await expectLater(t.philIriVm.setMinuteEnd(r.reading, 5), refusal('one-minute timer'));
    await t.philIriVm.startTimer(r.reading, at: at(0));
    await t.philIriVm.timer(r.reading, now: at(61));
    await expectLater(t.philIriVm.setMinuteEnd(r.reading, 100), refusal('outside the passage'));
    final whole = await reading();
    await expectLater(t.philIriVm.setMinuteEnd(whole.reading, 5), refusal('one-minute'));
  });

  group('final review fixes', () {
    Future<int> taps(int readingId) async => (await ctx.localDb
            .rawQuery('SELECT count(*) AS n FROM phil_iri_reading_timer_events WHERE reading_id = ?', [readingId]))
        .first['n'] as int;

    test('discarding a timed session leaves no taps behind (C1)', () async {
      final r = await reading();
      await t.philIriVm.startTimer(r.reading, at: at(0));
      await t.philIriVm.discard(r.session);
      expect(await taps(r.reading), 0);
    });

    test('two stops at once: one stops, the other is a plain refusal (I2)', () async {
      final r = await reading();
      await t.philIriVm.startTimer(r.reading, at: at(0));
      final outcomes = await Future.wait([
        t.philIriVm.stopTimer(r.reading, at: at(30)).then<Object>((_) => 'ok', onError: (Object e) => e),
        t.philIriVm.stopTimer(r.reading, at: at(30)).then<Object>((_) => 'ok', onError: (Object e) => e),
      ]);
      expect(outcomes.where((o) => o == 'ok'), hasLength(1));
      final other = outcomes.firstWhere((o) => o != 'ok');
      expect(other, isA<ViewModelException>().having((e) => e.message, 'message', 'The timer is already stopped.'));
      expect(await taps(r.reading), 2);
    });

    test('starting the timer clears a typed time (I4)', () async {
      final student = nextStudent++;
      await ctx.localDb.insert('students', {'id': student, 'lrn': '77777777$student', 'last_name': 'L', 'first_name': 'F', 'school_id': 1});
      await ctx.localDb.insert('enrollments', {'student_id': student, 'section_id': 93, 'school_year': _year, 'status': 'active'});
      final s = await t.philIriVm.startSession(studentId: student, sectionId: 93, schoolYear: _year, round: PhilIriRound.bosy);
      final read = await t.philIriVm.startReading(
          assessmentId: s.id!, passageId: 601, method: PhilIriReadingMethod.oneMinute, wordsRead: 30);
      await t.philIriVm.startTimer(read.id!, at: at(0));
      expect((await t.philIriVm.readings(s.id!)).first.wordsRead, isNull);
      expect((await t.philIriVm.timer(read.id!, now: at(61))).minuteEndNeeded, isTrue);
    });

    test('no timer tap on a completed session (I5)', () async {
      final r = await reading();
      await t.philIriVm.saveTiming(r.reading, readingSeconds: 80);
      await t.philIriVm.complete(r.session);
      await expectLater(t.philIriVm.startTimer(r.reading, at: at(0)), refusal('Reopen the session to time it again.'));
      await expectLater(t.philIriVm.resetTimer(r.reading, at: at(0)), refusal('Reopen the session to time it again.'));
    });
  });
}
