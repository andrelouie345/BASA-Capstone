// CRLA phase (demo-data plan Task 8): Grades 1-3 at the ES, every CRLA round
// the run date has reached. The section's first tutor assesses on their own
// (tutor build) device with the round's date, Part 1 and Part 2 come from
// crlaPlanFor (checked against BASA's rules), and each section + round is
// uploaded on its own. The stored profile is read back; a learner whose
// profile differs from the plan is counted in state id mismatch.crla.<year>.
import 'dart:io';
import 'dart:math';

import 'package:basa_capstone/core/models/crla_assessment.dart';
import 'package:basa_capstone/core/models/crla_result.dart';
import 'package:basa_capstone/viewmodels/crla_viewmodel.dart';

import '../dates.dart';
import '../records.dart';
import '../round_plan.dart';
import '../session.dart';
import '../state.dart';
import '../sync_steps.dart';
import '../world.dart';
import 'rosters.dart';

String crlaStep(DemoYear y) => 'crla-${y.label.substring(0, 4)}';

/// The CRLA test of each grade: G1 Mother Tongue, G2 Filipino, G3 English.
String crlaVariantOf(int grade) => switch (grade) { 1 => 'mt', 2 => 'fil', _ => 'eng' };

Future<void> runCrla(DemoSession s, DemoState st, DemoWorld w, DemoYear y,
    {required DateTime today, DemoRoundPlan plan = const DemoRoundPlan()}) async {
  final sections = w.sections.where((x) => x.year == y && x.grade <= 3).toList();
  final pulled = <String>{};
  for (final section in sections) {
    for (final round in CrlaRound.values) {
      if (!plan.runs(round.name)) continue;
      final step = '${crlaStep(y)}.${demoSectionKey(section)}.${round.name}';
      if (st.done(step)) continue;
      // The round's dates: none = the run date hasn't reached it.
      if (roundDate(y, 'crla', round.name, today: today, rng: Random(0)) == null) {
        await st.markDone(step);
        continue;
      }
      // Who records whom: the section's first tutor, or a learner's ARAL
      // class tutor (on their own device, in turn).
      final byAssessor = <String, List<DemoLearner>>{};
      for (final l in plan.learnersOf(w, section)) {
        if (!plan.assesses(l, round.name)) continue;
        byAssessor.putIfAbsent(plan.assessorOf(l, section, round.name), () => []).add(l);
      }
      var attempts = 0, mismatches = 0;
      for (final MapEntry(key: tutorKey, value: learners) in byAssessor.entries) {
        final sub = '$step.$tutorKey';
        if (st.done(sub)) continue;
        final r = await _crlaBy(s, st, w, y, section, round, tutorKey, learners, pulled, today);
        attempts += r.attempts;
        mismatches += r.mismatches;
        await st.markDone(sub);
      }
      final key = 'mismatch.crla.${y.label}';
      await st.putId(key, (st.ids[key] ?? 0) + mismatches);
      stdout.writeln('  ${section.name} ${round.label}: $attempts attempts by ${byAssessor.keys.join(', ')}, '
          '$mismatches profile mismatch(es)');
      await st.markDone(step);
    }
  }
}

/// [tutorKey] records [learners]' CRLA [round] on their device and uploads.
Future<({int attempts, int mismatches})> _crlaBy(DemoSession s, DemoState st, DemoWorld w, DemoYear y,
    DemoSection section, CrlaRound round, String tutorKey, List<DemoLearner> learners, Set<String> pulled,
    DateTime today) async {
  final dev = await s.as(tutorKey);
  if (pulled.add(tutorKey)) await dev.shared.syncVm.pull();
  final crla = dev.tutor.crlaVm;
  final sectionId = st.ids[demoSectionIdKey(section)]!;
  final schoolId = st.ids['school.${section.schoolCode}']!;
  final thresholds = await crla.effectiveThresholds(schoolId);
  final variant = crlaVariantOf(section.grade);
  final language = variant == 'mt' ? await _motherTongue(dev.tutor.crlaVm, section.grade) : null;

  await crla.loadResultsForSection(sectionId, schoolYear: y.label);
  final existing = {
    for (final r in crla.results)
      if (r.round == round) r.studentId: r,
  };
  final planned = <int, String>{}; // assessment id -> planned profile
  for (final l in learners) {
    final student = await dev.shared.studentRepo.findByLrn(l.lrn);
    if (student == null) throw StateError('${l.lrn} is not on the device of $tutorKey');
    final rng = Random(int.parse(l.lrn.substring(4)) * 31 + round.index * 7 + y.index);
    final profile = crlaProfileFor(w.band(l, y, round.name), rng);
    final CrlaResult? have = existing[student.id];
    if (have != null && have.readingProfile != null && have.storyNo != null) continue;
    final assessmentId = have?.assessmentId ??
        (await crla.startAssessment(
          studentId: student.id!,
          sectionId: sectionId,
          schoolYear: y.label,
          subjectVariant: variant,
          language: language,
          round: round,
          administeredBy: dev.ctx.authVm.currentUser!.id, // a user id, like the console
          assessedAt: roundDate(y, 'crla', round.name, today: today, rng: rng),
        ))
            .id!;
    final story = (await crla.storiesForAttempt(assessmentId)).first;
    final p = crlaPlanFor(
        profile: profile, grade: section.grade, variant: variant, storyWords: story.wordCount, rng: rng, t: thresholds);
    if (variant == 'eng') {
      await crla.savePart1English(assessmentId: assessmentId, task1Score: p.task1, task2Score: p.task2);
    } else {
      await crla.savePart1Standard(
          assessmentId: assessmentId, task1Score: p.task1, task2LowScore: p.task2Low, task2HighScore: p.task2High);
    }
    await crla.savePart2Fluency(
      assessmentId: assessmentId,
      storyNo: story.storyNo,
      miscues: p.miscues,
      timeMinutes: p.minutes,
      timeSeconds: p.seconds,
      comprehensionCorrect: p.comprehension,
    );
    planned[assessmentId] = profile;
  }

  var mismatches = 0;
  for (final e in planned.entries) {
    if ((await crla.getResult(e.key))?.readingProfile != e.value) mismatches++;
  }
  await settlePending(s, tutorKey, coordinatorOf(section.schoolCode)); // a run stopped before the decision
  if ((await (await s.as(tutorKey)).shared.syncVm.preview()).package.isEmpty == false) {
    await uploadAndDecide(s, tutorKey, coordinatorOf(section.schoolCode));
  }
  return (attempts: planned.length, mismatches: mismatches);
}

/// The Mother Tongue of the Night City schools (Northern Mindanao: Cebuano).
const demoMotherTongue = 'Sinugbuanong Binisaya';

/// [demoMotherTongue], checked against the region's Grade [grade] stories.
Future<String> _motherTongue(CrlaViewModel crla, int grade) async {
  await crla.loadStories(demoRegionId, language: demoMotherTongue, grade: grade);
  if (crla.stories.isEmpty) throw StateError('no Grade $grade $demoMotherTongue stories in region $demoRegionId');
  return demoMotherTongue;
}
