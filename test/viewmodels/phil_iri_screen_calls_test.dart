// Phil-IRI calls a screen needs without console code (screen inventory
// docs/handoff/screens/phil-iri.md, PHILIRI-G1, G3 and G4).
import 'dart:io';

import 'package:basa_capstone/core/models/phil_iri_gst_result.dart';
import 'package:basa_capstone/core/models/phil_iri_reading.dart';
import 'package:basa_capstone/core/models/phil_iri_types.dart';
import 'package:basa_capstone/core/wiring/app_context.dart';
import 'package:basa_capstone/core/wiring/wire_shared.dart';
import 'package:basa_capstone/core/wiring/wire_tutor.dart';
import 'package:basa_capstone/viewmodels/phil_iri_content_viewmodel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../helpers/offline_owner.dart';

PhilIriGstResult _gst(int score, int max) => PhilIriGstResult(
    studentId: 1, schoolId: 1, sectionId: 1, schoolYear: '2026-2027', maxScore: max, totalScore: score, takenAt: '2026-06-20');

PhilIriReading _reading(PhilIriReadingMethod method, {int? seconds, int? words}) => PhilIriReading(
    assessmentId: 1, sequenceNo: 1, passageId: 1, method: method, readingSeconds: seconds, wordsRead: words);

void main() {
  late TutorVms t;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final ctx = await AppContext.open(dataDir: Directory.systemTemp.createTempSync('basa_phil_iri_calls_').path);
    t = wireTutor(ctx, wireShared(ctx));
    await seedOfflineOwner(ctx.localDb, userId: '00000000-0000-0000-0000-00000000ab02', email: 'pi@test', role: 'tutor', schoolId: 1);
    expect(await ctx.authVm.signInOffline(email: 'pi@test', password: 'test-pw'), isNull);
  });

  test('gstPassed at the default pass mark', () async {
    expect(await t.philIriVm.gstPassed(_gst(14, 20)), isTrue);
    expect(await t.philIriVm.gstPassed(_gst(13, 20)), isFalse);
    expect(await t.philIriVm.gstPassed(_gst(28, 40)), isTrue);
    expect(await t.philIriVm.gstPassed(_gst(27, 40)), isFalse);
  });

  test('wholePercent rounds like the report', () {
    expect(_gst(13, 20).wholePercent, 65);
    expect(_gst(1, 40).wholePercent, 3); // 2.5% rounds up
  });

  test('isTimed per method', () {
    expect(_reading(PhilIriReadingMethod.wholeText).isTimed, isFalse);
    expect(_reading(PhilIriReadingMethod.wholeText, seconds: 80).isTimed, isTrue);
    expect(_reading(PhilIriReadingMethod.silent).isTimed, isFalse);
    expect(_reading(PhilIriReadingMethod.silent, seconds: 60).isTimed, isTrue);
    expect(_reading(PhilIriReadingMethod.oneMinute, seconds: 60).isTimed, isFalse);
    expect(_reading(PhilIriReadingMethod.oneMinute, words: 90).isTimed, isTrue);
  });

  test('observation labels in order', () {
    const o = PhilIriObservation(
        wordByWord: true,
        lacksExpression: true,
        voiceInaudible: true,
        disregardsPunctuation: true,
        pointsToWords: true,
        littleAnalysis: true,
        other: 'yawns');

    expect(o.labels, [
      'word-by-word reading',
      'lacks expression',
      'voice hardly audible',
      'disregards punctuation',
      'points to each word',
      'little or no word analysis',
      'other: yawns',
    ]);
    expect(const PhilIriObservation().labels, isEmpty);
  });

  test('threshold layers carry the defaults', () {
    final layers = PhilIriThresholdLayers(null, null, PhilIriThresholds.defaults);

    expect(layers.defaults.toMap(), PhilIriThresholds.defaults.toMap());
  });
}
