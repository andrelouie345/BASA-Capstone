// Every public ViewModel method checks the sign-in itself; screens call the
// ViewModels directly, so a check in the console command is not enough
// (command pass finding F5). Signed out, each call must be refused before it
// touches the device's data.
import 'dart:io';

import 'package:basa_capstone/core/models/aral_class.dart';
import 'package:basa_capstone/core/models/aral_enrollment.dart';
import 'package:basa_capstone/core/models/aral_irip.dart';
import 'package:basa_capstone/core/models/aral_session.dart';
import 'package:basa_capstone/core/models/crla_assessment.dart' show CrlaRound;
import 'package:basa_capstone/core/models/sync_upload.dart' show SyncChoice;
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
  late SharedVms wiredShared;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final ctx = await AppContext.open(dataDir: Directory.systemTemp.createTempSync('basa_guard_').path);
    wiredShared = wireShared(ctx);
    t = wireTutor(ctx, wiredShared); // nobody signed in
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

  test('the ARAL ViewModels refuse every call while signed out', () async {
    final aral = t.aralVm, ses = t.aralSessionVm, irip = t.aralIripVm;
    final ck = t.aralCheckinVm, read = t.aralReadabilityVm, mat = t.aralMaterialVm;
    final cls = t.aralClassVm;
    const y = '2026-2027';
    final calls = <String, Future<Object?> Function()>{
      'aral.propose': () => aral.propose(sectionId: 1, schoolYear: y),
      'aral.freePlaces': () => aral.freePlaces(sectionId: 1, schoolYear: y),
      'aral.programSettings': () => aral.programSettings(1),
      'aral.enroll': () => aral.enroll(sectionId: 1, schoolYear: y, studentId: 1),
      'aral.enrollProposed': () => aral.enrollProposed(sectionId: 1, schoolYear: y),
      'aral.setPlacement': () => aral.setPlacement(1, AralKeyStage.ks3, AralTrack.basic),
      'aral.assignTutor': () => aral.assignTutor(1, null),
      'aral.exit': () => aral.exit(1, AralExitReason.gradeLevelReady),
      'aral.reactivate': () => aral.reactivate(1),
      'aral.setNotes': () => aral.setNotes(1, 'x'),
      'aral.remove': () => aral.remove(1),
      'aral.applyResults': () => aral.applyResults(sectionId: 1, schoolYear: y),
      'aral.applySchoolResults': () => aral.applySchoolResults(schoolId: 1, schoolYear: y),
      'aral.roster': () => aral.roster(sectionId: 1),
      'aral.schoolRoster': () => aral.schoolRoster(schoolId: 1),
      'aral.tutorRoster': () => aral.tutorRoster(),
      'aral.getEnrollment': () => aral.getEnrollment(1),
      'aral.rosterCsv': () => aral.rosterCsv(schoolId: 1, schoolYear: y),
      'aral.tutors': () => aral.tutors(schoolId: 1, schoolYear: y),
      'aral.learnerNames': () => aral.learnerNames(1),
      'class.classes': () => cls.classes(schoolId: 1),
      'class.getClass': () => cls.getClass(1),
      'class.createClass': () => cls.createClass(
          schoolId: 1, schoolYear: y, className: 'x', program: AralClassProgram.ks1, gradeBand: AralGradeBand.g1to3),
      'class.editClass': () => cls.editClass(const AralClass(
          id: 1, schoolId: 1, schoolYear: y, className: 'x', program: AralClassProgram.ks1, gradeBand: AralGradeBand.g1to3)),
      'class.deleteClass': () => cls.deleteClass(1),
      'session.logSession': () => ses.logSession(schoolYear: y, minutes: 30, setup: AralSetup.pullOut),
      'session.editSession': () => ses.editSession(1, minutes: 5),
      'session.deleteSession': () => ses.deleteSession(1),
      'session.getSession': () => ses.getSession(1),
      'session.tutorSessions': () => ses.tutorSessions(),
      'session.schoolSessions': () => ses.schoolSessions(schoolId: 1),
      'session.sheet': () => ses.sheet(1),
      'session.mark': () => ses.mark(1, 1, AralMark.present),
      'session.markRest': () => ses.markRest(1, AralMark.present),
      'session.unmark': () => ses.unmark(1, 1),
      'session.learnerAttendance': () => ses.learnerAttendance(1),
      'session.tutorSummary': () => ses.tutorSummary(schoolYear: y),
      'session.setMultipleSessionsPerDay': () => ses.setMultipleSessionsPerDay('t', true),
      'session.allowsMultipleSessionsPerDay': () => ses.allowsMultipleSessionsPerDay('t'),
      'session.learnerNames': () => ses.learnerNames(const []),
      'irip.targets': () => irip.targets(AralIripProgram.basicKs23),
      'irip.plan': () => irip.plan(1),
      'irip.startCycle': () => irip.startCycle(1),
      'irip.rate': () => irip.rate(1, AralIripStatus.observed),
      'irip.clearRating': () => irip.clearRating(1),
      'irip.setNotes': () => irip.setNotes(1, 'x'),
      'irip.changeTarget': () => irip.changeTarget(1, 1),
      'irip.nextWeek': () => irip.nextWeek(1, strand: AralIripStrand.filipino),
      'irip.deleteWeek': () => irip.deleteWeek(1),
      'checkin.tools': () => ck.tools(),
      'checkin.items': () => ck.items(1),
      'checkin.learnerCheckins': () => ck.learnerCheckins(1),
      'checkin.result': () => ck.result(1),
      'checkin.checkinReport': () => ck.checkinReport(schoolId: 1, schoolYear: y),
      'checkin.checkinReportCsv': () => ck.checkinReportCsv(schoolId: 1, schoolYear: y),
      'checkin.startCheckin': () => ck.startCheckin(1, 16),
      'checkin.editCheckin': () => ck.editCheckin(1, notes: 'x'),
      'checkin.deleteCheckin': () => ck.deleteCheckin(1),
      'checkin.answerChoices': () => ck.answerChoices(1, 1, ['a']),
      'checkin.markOpen': () => ck.markOpen(1, 1, true),
      'checkin.clearAnswer': () => ck.clearAnswer(1, 1),
      'checkin.localSettings': () => ck.localSettings(1),
      'checkin.settingLayers': () => ck.settingLayers(1),
      'checkin.setPassPct': () => ck.setPassPct(1, 75),
      'checkin.foundationalProgramLayers': () => ck.foundationalProgramLayers(1),
      'checkin.setFoundationalProgram': () => ck.setFoundationalProgram(1, true),
      'checkin.ks1ExtendedLayers': () => ck.ks1ExtendedLayers(1),
      'checkin.setKs1Extended': () => ck.setKs1Extended(1, true),
      'checkin.localSessionSettings': () => ck.localSessionSettings(1),
      'checkin.idleSessionDaysLayers': () => ck.idleSessionDaysLayers(1),
      'checkin.setIdleSessionDays': () => ck.setIdleSessionDays(1, 7),
      'checkin.resetSchoolSettings': () => ck.resetSchoolSettings(1),
      'readability.available': () => read.available(1),
      'readability.entries': () => read.entries(1),
      'readability.add': () => read.add(enrollmentId: 1, words: 100, sentences: 8, syllables: 140),
      'readability.update': () => read.update(1, title: 'x'),
      'readability.delete': () => read.delete(1),
      'material.catalog': () => mat.catalog(),
      'material.material': () => mat.material(1),
      'material.addMaterial': () => mat.addMaterial(title: 'x', keyStage: AralKeyStage.ks3),
      'material.updateMaterial': () => mat.updateMaterial(1, title: 'x'),
      'material.setActive': () => mat.setActive(1, true),
      'material.deleteMaterial': () => mat.deleteMaterial(1),
      'material.setSchoolLink': () => mat.setSchoolLink(1, 1, null),
      'material.recommendations': () => mat.recommendations(1),
      'material.sectionRecommendations': () => mat.sectionRecommendations(sectionId: 1, schoolYear: y),
    };
    final open = <String>[];
    for (final e in calls.entries) {
      try {
        await e.value();
        open.add('${e.key}: went through');
      } on ViewModelException catch (x) {
        if (x.message != notSignedInMessage) open.add('${e.key}: "${x.message}"');
      } catch (x) {
        open.add('${e.key}: ${x.runtimeType}');
      }
    }
    expect(open, isEmpty);
  });

  test('SyncViewModel refuses every call while signed out', () async {
    final vm = wiredShared.syncVm;
    final calls = <String, Future<Object?> Function()>{
      'pullPreview': () => vm.pullPreview(),
      'pull': () => vm.pull(),
      'preview': () => vm.preview(),
      'resolve': () => vm.resolve('aral_sessions', '1', SyncChoice.server),
      'refreshStatus': () => vm.refreshStatus(),
      'upload': () => vm.upload(),
      'withdraw': () => vm.withdraw(1),
      'uploads': () => vm.uploads(),
      'lockedCounts': () => vm.lockedCounts(),
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
