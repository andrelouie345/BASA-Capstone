// Every public ViewModel method checks the sign-in itself; screens call the
// ViewModels directly, so a check in the console command is not enough
// (command pass finding F5). Signed out, each call must be refused before it
// touches the device's data.
import 'dart:io';

import 'package:basa_capstone/core/models/crla_assessment.dart' show CrlaRound;
import 'package:basa_capstone/core/models/phil_iri_assessment.dart' show PhilIriRound;
import 'package:basa_capstone/core/models/phil_iri_miscue.dart';
import 'package:basa_capstone/core/models/phil_iri_reading.dart';
import 'package:basa_capstone/core/services/auth_messages.dart';
import 'package:basa_capstone/core/wiring/app_context.dart';
import 'package:basa_capstone/core/wiring/wire_shared.dart';
import 'package:basa_capstone/core/wiring/wire_tutor.dart';
import 'package:basa_capstone/viewmodels/viewmodel_exception.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

final _refused = throwsA(isA<ViewModelException>().having((e) => e.message, 'message', notSignedInMessage));

void main() {
  late TutorVms t;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final ctx = await AppContext.open(dataDir: Directory.systemTemp.createTempSync('basa_guard_').path);
    t = wireTutor(ctx, wireShared(ctx)); // nobody signed in
  });

  test('CrlaViewModel refuses every call while signed out', () async {
    final vm = t.crlaVm;
    final calls = <String, Future<Object?> Function()>{
      'loadForSection': () => vm.loadForSection(1),
      'refresh': () => vm.refresh(),
      'effectiveThresholds': () => vm.effectiveThresholds(1),
      'startAssessment': () => vm.startAssessment(
          studentId: 1, sectionId: 1, schoolYear: '2026-2027', subjectVariant: 'fil', language: 'Tagalog',
          round: CrlaRound.bosy),
      'savePart1Standard': () => vm.savePart1Standard(assessmentId: 1, task1Score: 8, task2HighScore: 9),
      'savePart1English': () => vm.savePart1English(assessmentId: 1, task1Score: 5),
      'savePart2Fluency': () => vm.savePart2Fluency(
          assessmentId: 1, storyNo: 1, miscues: 0, wordsRead: 50, timeMinutes: 1, timeSeconds: 0,
          comprehensionCorrect: 3),
      'getResult': () => vm.getResult(1),
      'getAssessment': () => vm.getAssessment(1),
      'loadResultsForSection': () => vm.loadResultsForSection(1),
      'loadResultsForStudent': () => vm.loadResultsForStudent(1),
      'loadStories': () => vm.loadStories(13),
    };
    for (final e in calls.entries) {
      await expectLater(e.value(), _refused, reason: e.key);
    }
  });

  test('PhilIriViewModel refuses every call while signed out', () async {
    final vm = t.philIriVm;
    final calls = <String, Future<Object?> Function()>{
      'loadForSection': () => vm.loadForSection(1),
      'refresh': () => vm.refresh(),
      'effectiveThresholds': () => vm.effectiveThresholds(1),
      'recordGst': () => vm.recordGst(studentId: 1, sectionId: 1, schoolYear: '2026-2027', totalScore: 20),
      'gstForSection': () => vm.gstForSection(1),
      'startSession': () => vm.startSession(studentId: 1, sectionId: 1, schoolYear: '2026-2027', round: PhilIriRound.bosy),
      'getSession': () => vm.getSession(1),
      'availablePassages': () => vm.availablePassages(1),
      'startReading': () => vm.startReading(assessmentId: 1, passageId: 1),
      'saveTiming': () => vm.saveTiming(1, readingSeconds: 60),
      'saveObservation': () => vm.saveObservation(1, const PhilIriObservation()),
      'deleteReading': () => vm.deleteReading(1),
      'markMiscue': () => vm.markMiscue(readingId: 1, wordIndex: 0, type: PhilIriMiscueType.omission),
      'updateMiscue': () =>
          vm.updateMiscue(PhilIriMiscue(id: 1, readingId: 1, wordIndex: 0, type: PhilIriMiscueType.omission)),
      'removeMiscue': () => vm.removeMiscue(1),
      'miscues': () => vm.miscues(1),
      'answer': () => vm.answer(readingId: 1, questionId: 1, chosen: 'a'),
      'answers': () => vm.answers(1),
      'readings': () => vm.readings(1),
      'passage': () => vm.passage(1),
      'questions': () => vm.questions(1),
      'collection': () => vm.collection(1),
      'rubricCriteria': () => vm.rubricCriteria(1),
      'rubricScores': () => vm.rubricScores(1),
      'scoreRubric': () => vm.scoreRubric(assessmentId: 1, criterionId: 1, score: 1),
      'complete': () => vm.complete(1),
      'reopen': () => vm.reopen(1),
      'discard': () => vm.discard(1),
      'finalize': () => vm.finalize(1),
      'finalizeRound': () => vm.finalizeRound(sectionId: 1, schoolYear: '2026-2027', round: PhilIriRound.bosy),
      'silentReadingFollowedUp': () => vm.silentReadingFollowedUp(1),
      'scoreReading': () => vm.scoreReading(1),
      'learnerResults': () => vm.learnerResults(studentId: 1, sectionId: 1, schoolYear: '2026-2027'),
      'reportResults': () => vm.reportResults(studentId: 1, sectionId: 1, schoolYear: '2026-2027'),
    };
    for (final e in calls.entries) {
      await expectLater(e.value(), _refused, reason: e.key);
    }
  });
}
