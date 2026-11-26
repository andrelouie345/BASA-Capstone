// Phil-IRI phase (demo-data plan Task 9): Grades 4-10, every Phil-IRI round
// the run date has reached (BOSY, MOSY #1, EOSY). The section's first tutor
// records, on their own (tutor build) device and with the round's dates:
// the GST once a year (with BOSY), then per learner a session with one
// grade-level passage the learner hasn't read: miscues on real word
// positions, timing, an answer per question, the collection's rubric, then
// complete. About 1 in 5 learners read silently first; a silent reading at
// Frustration or below gets an oral follow-up of the same passage (another
// attempt of the round, as BASA's rules have it). Each section + round is
// uploaded on its own (the HS waits for its coordinator's approval); a round
// whose window has closed is then finalized by the coordinator. The latest
// reading of each learner is scored back; a profile other than the planned
// band is counted per step in state id mismatch.phil-iri-<yyyy>.<grade>.<round>
// and summed in mismatch.philiri.<year>.
import 'dart:io';
import 'dart:math';

import 'package:basa_capstone/core/models/phil_iri_assessment.dart';
import 'package:basa_capstone/core/models/phil_iri_miscue.dart';
import 'package:basa_capstone/core/models/phil_iri_passage.dart';
import 'package:basa_capstone/core/models/phil_iri_reading.dart';
import 'package:basa_capstone/core/models/phil_iri_question.dart';
import 'package:basa_capstone/core/services/phil_iri_rules.dart';
import 'package:basa_capstone/viewmodels/phil_iri_viewmodel.dart';

import '../../command_pass/device.dart';
import '../dates.dart';
import '../records.dart';
import '../session.dart';
import '../state.dart';
import '../sync_steps.dart';
import '../world.dart';
import 'rosters.dart';

String philIriStep(DemoYear y) => 'phil-iri-${y.label.substring(0, 4)}';

/// The rounds the demo calendar holds (MOSY #2 and #3 are not held).
const demoPhilIriRounds = [PhilIriRound.bosy, PhilIriRound.mosy1, PhilIriRound.eosy];

const _substitutes = ['the', 'a', 'then', 'they', 'was', 'went', 'is', 'and', 'come', 'see'];

Future<void> runPhilIri(DemoSession s, DemoState st, DemoWorld w, DemoYear y, {required DateTime today}) async {
  final pulled = <String>{};
  for (final section in w.sections.where((x) => x.year == y && x.grade >= 4)) {
    for (final round in demoPhilIriRounds) {
      final step = '${philIriStep(y)}.G${section.grade}.${round.name}';
      if (st.done(step)) continue;
      final window = demoWindows(y).singleWhere((x) => x.instrument == 'phil_iri' && x.round == round.name);
      if (roundDate(y, 'phil_iri', round.name, today: today, rng: Random(0)) == null) {
        await st.markDone(step); // the run date hasn't reached this round
        continue;
      }
      final tutorKey = section.tutorAccounts.first;
      final coordinator = coordinatorOf(section.schoolCode);
      final sectionId = st.ids['section.${y.label}.${section.schoolCode}.G${section.grade}']!;
      final dev = await s.as(tutorKey);
      if (pulled.add(tutorKey)) await dev.shared.syncVm.pull();
      final vm = dev.tutor.philIriVm;
      final t = await vm.effectiveThresholds(st.ids['school.${section.schoolCode}']!);

      var gst = 0, sessions = 0, silent = 0;
      final latestReading = <int, ({int readingId, DemoBand band})>{};
      final have = round == PhilIriRound.bosy
          ? {for (final g in await vm.gstForSection(sectionId, schoolYear: y.label)) g.studentId}
          : <int>{};
      await vm.loadForSection(sectionId, schoolYear: y.label, round: round);
      final existing = [...vm.assessments];

      for (final l in w.inSection(section)) {
        final student = await dev.shared.studentRepo.findByLrn(l.lrn);
        if (student == null) throw StateError('${l.lrn} is not on $tutorKey\'s device');
        final studentId = student.id!;
        final rng = Random(int.parse(l.lrn.substring(4)) * 37 + round.index * 11 + y.index);
        final band = w.band(l, y, round.name);
        final date = roundDate(y, 'phil_iri', round.name, today: today, rng: rng)!;

        if (round == PhilIriRound.bosy && !have.contains(studentId)) {
          final total = gstScoreFor(target: band, grade: section.grade, rng: rng, t: t);
          final split = gstSplitFor(total, rng);
          await vm.recordGst(
              studentId: studentId,
              sectionId: sectionId,
              schoolYear: y.label,
              totalScore: total,
              literalCorrect: split.literal,
              inferentialCorrect: split.inferential,
              criticalCorrect: split.critical,
              takenAt: date);
          gst++;
        }

        // What this learner already has in the round (a run that stopped).
        final mine = existing.where((a) => a.studentId == studentId).toList()
          ..sort((a, b) => (a.attemptNo ?? 0).compareTo(b.attemptNo ?? 0));
        for (final a in mine.where((a) => a.status == PhilIriStatus.inProgress)) {
          await vm.discard(a.id!);
        }
        final done = mine.where((a) => a.status != PhilIriStatus.inProgress).toList();
        final readSilently = band != DemoBand.nonReader && rng.nextInt(5) == 0;
        final needsFollowUp = readSilently && band.index <= DemoBand.frustration.index;

        if (done.isEmpty) {
          final first = await _session(vm, studentId, sectionId, y, round, date, band, rng, t,
              method: readSilently ? PhilIriReadingMethod.silent : PhilIriReadingMethod.wholeText);
          sessions++;
          if (readSilently) silent++;
          if (!needsFollowUp) {
            latestReading[studentId] = (readingId: first.readingId, band: band);
            continue;
          }
          final follow = await _session(vm, studentId, sectionId, y, round, date, band, rng, t,
              method: PhilIriReadingMethod.wholeText, passageId: first.passageId);
          sessions++;
          if (await vm.silentReadingFollowedUp(follow.readingId) == null) {
            throw StateError('the oral follow-up of ${l.lrn} (${round.label}) is not linked to its silent reading');
          }
          latestReading[studentId] = (readingId: follow.readingId, band: band);
        } else {
          final last = done.last;
          final reading = (await vm.readings(last.id!)).first;
          if (reading.method == PhilIriReadingMethod.silent && needsFollowUp) {
            final follow = await _session(vm, studentId, sectionId, y, round, date, band, rng, t,
                method: PhilIriReadingMethod.wholeText, passageId: reading.passageId);
            sessions++;
            latestReading[studentId] = (readingId: follow.readingId, band: band);
          } else {
            // Recorded by a run that stopped: still scored back below.
            latestReading[studentId] = (readingId: reading.id!, band: band);
          }
        }
      }

      var mismatches = 0;
      for (final r in latestReading.values) {
        if ((await vm.scoreReading(r.readingId)).profile != demoPhilIriLevel(r.band)) mismatches++;
      }
      await settlePending(s, tutorKey, coordinator); // a run stopped before the decision
      if ((await (await s.as(tutorKey)).shared.syncVm.preview()).package.isEmpty == false) {
        await uploadAndDecide(s, tutorKey, coordinator);
      }

      var finalized = 0;
      if (window.closes.isBefore(DateTime(today.year, today.month, today.day))) {
        finalized = await _finalizeRound(s, coordinator, sectionId, y, round);
      }
      // Per step, overwritten, so a rerun counts the round once; the year's
      // total is the sum of its steps.
      final stepPrefix = 'mismatch.${philIriStep(y)}.';
      await st.putId('$stepPrefix${section.grade}.${round.name}', mismatches);
      await st.putId('mismatch.philiri.${y.label}', [
        for (final e in st.ids.entries)
          if (e.key.startsWith(stepPrefix)) e.value,
      ].fold<int>(0, (a, b) => a + b));
      stdout.writeln('  ${section.name} ${round.label}: GST $gst, $sessions session(s) ($silent silent first), '
          '$mismatches profile mismatch(es), $finalized finalized');
      await st.markDone(step);
    }
  }
}

/// One completed session with its reading; [passageId] = re-read that passage
/// (an oral follow-up), else a grade-level passage with questions the learner
/// hasn't read.
Future<({int readingId, int passageId})> _session(PhilIriViewModel vm, int studentId, int sectionId, DemoYear y,
    PhilIriRound round, DateTime date, DemoBand band, Random rng, PhilIriThresholds t,
    {required PhilIriReadingMethod method, int? passageId}) async {
  final a = await vm.startSession(
      studentId: studentId, sectionId: sectionId, schoolYear: y.label, round: round, assessedAt: date);
  final PhilIriPassage passage;
  if (passageId != null) {
    passage = (await vm.passage(passageId))!;
  } else {
    final options = <PhilIriPassage>[];
    for (final p in await vm.availablePassages(a.id!, method: method)) {
      if (p.level != null && (await vm.questions(p.id!)).isNotEmpty) options.add(p);
    }
    if (options.isEmpty) throw StateError('no unread grade-level passage with questions left for learner $studentId');
    passage = options[rng.nextInt(options.length)];
  }
  final questions = await vm.questions(passage.id!);
  final plan = philIriPlanFor(
      target: band,
      words: passage.words,
      questionCount: questions.length,
      rng: rng,
      silent: method == PhilIriReadingMethod.silent,
      t: t);
  final reading = await vm.startReading(assessmentId: a.id!, passageId: passage.id!, method: method);
  for (final m in plan.miscues) {
    final word = passage.words[m.wordIndex];
    await vm.markMiscue(
      readingId: reading.id!,
      wordIndex: m.wordIndex,
      type: m.type,
      spokenText: switch (m.type) {
        PhilIriMiscueType.substitution => _substitutes[rng.nextInt(_substitutes.length)],
        PhilIriMiscueType.mispronunciation => _mispronounce(word, rng),
        PhilIriMiscueType.insertion => _substitutes[rng.nextInt(_substitutes.length)],
        _ => null,
      },
      selfCorrected: m.selfCorrected,
    );
  }
  await vm.saveTiming(reading.id!, readingSeconds: plan.readingSeconds);
  final right = ([for (var i = 0; i < questions.length; i++) i < plan.correctAnswers]..shuffle(rng));
  for (final (i, q) in questions.indexed) {
    final key = q.answerKey.toLowerCase();
    final wrong = [
      for (var c = 0; c < q.choices.length; c++)
        if (PhilIriQuestion.letterOf(c) != key) PhilIriQuestion.letterOf(c),
    ];
    await vm.answer(readingId: reading.id!, questionId: q.id!, chosen: right[i] ? key : wrong[rng.nextInt(wrong.length)]);
  }
  final score = switch (band) {
    DemoBand.nonReader || DemoBand.struggling => 1,
    DemoBand.frustration => 2,
    DemoBand.instructional => 3,
    DemoBand.independent => 4,
  };
  for (final c in await vm.rubricCriteria(passage.collectionId)) {
    await vm.scoreRubric(assessmentId: a.id!, criterionId: c.id!, score: score.clamp(c.scaleMin, c.scaleMax));
  }
  await vm.complete(a.id!);
  return (readingId: reading.id!, passageId: passage.id!);
}

/// A word said wrongly: one letter changed (a short word gets a sound added).
String _mispronounce(String word, Random rng) {
  final letters = word.replaceAll(RegExp(r'[^A-Za-z]'), '');
  if (letters.length < 3) return '${letters}h';
  final i = 1 + rng.nextInt(letters.length - 2);
  const vowels = 'aeiou';
  final swap = vowels[(vowels.indexOf(letters[i].toLowerCase()) + 1 + rng.nextInt(4)) % 5];
  return letters.substring(0, i) + swap + letters.substring(i + 1);
}

/// The coordinator takes the round in (pull), closes it for the section and
/// sends the finalized sessions (applied at once: an admin's own upload).
Future<int> _finalizeRound(DemoSession s, String coordinator, int sectionId, DemoYear y, PhilIriRound round) async {
  final Device dev = await s.as(coordinator);
  await dev.shared.syncVm.pull();
  final closure = await dev.tutor.philIriVm.finalizeRound(sectionId: sectionId, schoolYear: y.label, round: round);
  if (closure.stillInProgress.isNotEmpty) {
    throw StateError('${closure.stillInProgress.length} session(s) still in progress in section $sectionId');
  }
  if (closure.finalized.isNotEmpty) await uploadAndDecide(s, coordinator, coordinator);
  return closure.finalized.length;
}
