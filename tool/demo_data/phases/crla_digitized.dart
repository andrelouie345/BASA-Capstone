// Digitized CRLA in the demo (CRLA digitized plan Task 7, spec D13): about 12
// Grade 1-3 learners not read at 2026-2027 MOSY so far get an attempt marked
// in BASA (Part 1 item by item, miscue words, a story timed under the grade's
// limit, answers), by their ARAL class tutor where placed, else by the
// section's first tutor, on that tutor's device. The planned profile
// (crlaPlanFor) is reached through the marks and read back; a learner whose
// stored profile differs is counted in state id mismatch.crla.digitized.
import 'dart:io';
import 'dart:math';

import 'package:basa_capstone/core/models/crla_assessment.dart' show CrlaRound;
import 'package:basa_capstone/core/models/crla_form.dart';
import 'package:basa_capstone/core/services/crla_digitized.dart' show crlaTask2For;

import '../dates.dart';
import '../records.dart';
import '../round_plan.dart';
import '../session.dart';
import '../state.dart';
import '../sync_steps.dart';
import '../world.dart';
import 'crla.dart';
import 'next_year.dart' show mosyPlan;
import 'rosters.dart';
import 'setup.dart' show schoolIdOf;

const crlaDigitizedStep = 'crla-digitized.mosy-2026';

/// Learners per Grade 1-3 section (3 sections x 4 = 12).
const _perSection = 4;

const _y = DemoYear.y2026;

Future<void> runCrlaDigitized(DemoSession s, DemoState st, DemoWorld w, DateTime today) async {
  if (st.done(crlaDigitizedStep)) return;
  final date = roundDate(_y, 'crla', 'mosy', today: today, rng: Random(0));
  if (date == null) throw StateError('the run date has not reached the 2026-2027 CRLA MOSY round');
  final plan = await mosyPlan(s, st, w, round: 'mosy');
  var attempts = 0, mismatches = 0;
  for (final section in w.sections.where((x) => x.year == _y && x.grade <= 3)) {
    final step = '$crlaDigitizedStep.${demoSectionKey(section)}';
    if (st.done(step)) continue;
    // Not read at MOSY so far (the round is still open), no planned gap.
    final learners = [
      for (final l in plan.learnersOf(w, section))
        if (w.gapOf(l) == null && !plan.assesses(l, 'mosy')) l,
    ].take(_perSection).toList();
    final byAssessor = <String, List<DemoLearner>>{};
    for (final l in learners) {
      byAssessor.putIfAbsent(plan.assessorOf(l, section, 'mosy'), () => []).add(l);
    }
    for (final MapEntry(key: tutorKey, value: group) in byAssessor.entries) {
      final sub = '$step.$tutorKey';
      if (st.done(sub)) continue;
      final r = await _markedBy(s, st, w, section, tutorKey, group, plan, today);
      attempts += r.attempts;
      mismatches += r.mismatches;
      await st.markDone(sub);
    }
    stdout.writeln('  ${section.name} MOSY: ${learners.length} attempt(s) marked in BASA by ${byAssessor.keys.join(', ')}');
    await st.markDone(step);
  }
  const key = 'mismatch.crla.digitized';
  await st.putId(key, (st.ids[key] ?? 0) + mismatches);
  stdout.writeln('  $attempts digitized attempt(s), $mismatches profile mismatch(es)');
  await st.markDone(crlaDigitizedStep);
}

Future<({int attempts, int mismatches})> _markedBy(DemoSession s, DemoState st, DemoWorld w, DemoSection section,
    String tutorKey, List<DemoLearner> learners, DemoRoundPlan plan, DateTime today) async {
  final dev = await s.as(tutorKey);
  await dev.shared.syncVm.pull();
  final crla = dev.tutor.crlaVm;
  final sectionId = st.ids[demoSectionIdKey(section)]!;
  final thresholds = await crla.effectiveThresholds(schoolIdOf(st, section.schoolCode));
  final variant = crlaVariantOf(section.grade);
  final language = variant == 'mt' ? demoMotherTongue : null;
  final planned = <int, String>{};
  for (final l in learners) {
    final student = await dev.shared.studentRepo.findByLrn(l.lrn);
    if (student == null) throw StateError('${l.lrn} is not on the device of $tutorKey');
    final rng = Random(int.parse(l.lrn.substring(4)) * 37 + 11);
    final profile = crlaProfileFor(w.band(l, _y, 'mosy'), rng);
    final day = roundDate(_y, 'crla', 'mosy', today: today, rng: rng)!;
    final a = (await crla.startAssessment(
      studentId: student.id!,
      sectionId: sectionId,
      schoolYear: _y.label,
      subjectVariant: variant,
      language: language,
      round: CrlaRound.mosy,
      administeredBy: dev.ctx.authVm.currentUser!.id,
      assessedAt: day,
    ))
        .id!;
    final form = await crla.form(a);
    final story = form.stories.first;
    final p = crlaPlanFor(
        profile: profile, grade: section.grade, variant: variant, storyWords: story.wordCount, rng: rng, t: thresholds);

    // Part 1: the first n items right, then "Done" marks the rest wrong.
    Future<void> task(CrlaTask t, int right) async {
      final items = form.items[t] ?? const [];
      if (items.length < right) throw StateError('${t.value} of the form has ${items.length} items, the plan $right');
      for (final i in items.take(right)) {
        await crla.markItem(a, t, i.itemNo, correct: true);
      }
      await crla.closeTask(a, t);
    }

    await task(CrlaTask.task1, p.task1);
    final task2 = crlaTask2For(variant, p.task1);
    final task2Right = variant == 'eng' ? p.task2 : (task2 == CrlaTask.task2Low ? p.task2Low : p.task2High);
    if (task2 != null && task2Right != null) await task(task2, task2Right);

    // Part 2: timed in BASA at 09:00 of the attempt's day, miscues spread over
    // the story, stopped at the planned time.
    final start = DateTime(day.year, day.month, day.day, 9);
    await crla.startStoryTimer(a, story.storyNo, at: start);
    final words = story.words.length;
    for (var m = 0; m < p.miscues; m++) {
      await crla.toggleWord(a, (m * words) ~/ max(1, p.miscues));
    }
    final state = await crla.stopStoryTimer(a, at: start.add(Duration(seconds: p.minutes * 60 + p.seconds)));
    if (state.lastWordNeeded) await crla.setLastWordReached(a, words - 1);
    for (final q in story.questions) {
      await crla.answerQuestion(
          a, q.questionNo, q.questionNo <= p.comprehension ? CrlaAnswerMark.correct : CrlaAnswerMark.incorrect);
    }
    planned[a] = profile;
  }

  var mismatches = 0;
  for (final e in planned.entries) {
    if ((await crla.getResult(e.key))?.readingProfile != e.value) mismatches++;
  }
  await settlePending(s, tutorKey, coordinatorOf(section.schoolCode));
  if ((await (await s.as(tutorKey)).shared.syncVm.preview()).package.isEmpty == false) {
    await uploadAndDecide(s, tutorKey, coordinatorOf(section.schoolCode));
  }
  return (attempts: planned.length, mismatches: mismatches);
}
