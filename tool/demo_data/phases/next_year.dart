// 2026-2027 phase (demo-data plan Task 11), in the order a school lives it:
//   srp-2025       the HS coordinator builds the 2025-2026 SRP classes (room,
//                  schedule, an HS tutor each)
//   rosters        the June SF1s (continuing learners one grade up, the
//                  leavers still on them; Grade 8 - Narra new)
//   crla-bosy, phil-iri-bosy
//                  BOSY by the section tutors (gap learners: 3 never read,
//                  2 without a GST); the closed round is finalized
//   aral-roster    ARAL from BOSY (one HS class under the minimum: gap 6)
//   leavers-aug    the August Grade 8 SF1 without the four leavers: two
//                  archived, the returner dropped out, one moved to Narra
//   aral-sessions  sessions, IRIP, check-ins up to the run date (one HS class
//                  idle for 25 days)
//   leavers-oct    the October SF1 with the returner back: restored
//   crla-mosy, phil-iri-mosy
//                  MOSY #1, partly done (its window is open): a learner in an
//                  ARAL class by their class tutor (owner 2026-11-26), the
//                  others by the section tutor; Phil-IRI timed in BASA
//   one-minute-ready  four learners not read yet in MOSY #1 (Grades 5, 8, 9,
//                  10) get a session in progress with a one-minute reading
//                  started and no timer tap: the owner times them live
//                  (owner 2026-11-26; the builder doesn't simulate one)
//   anonymize-preview  the list only (never anonymize)
// Each part is a step of its own (`--only next-year` runs them all).
import 'dart:io';
import 'dart:math';

import 'package:basa_capstone/core/models/enrollment.dart';
import 'package:basa_capstone/core/models/phil_iri_assessment.dart';
import 'package:basa_capstone/core/models/phil_iri_reading.dart';
import 'package:basa_capstone/core/services/sf1_column_map.dart';

import '../round_plan.dart';
import '../session.dart';
import '../sf1_files.dart';
import '../state.dart';
import '../sync_steps.dart';
import '../world.dart';
import 'aral.dart';
import 'crla.dart';
import 'phil_iri.dart';
import 'rosters.dart';
import 'setup.dart';

const nextYearStep = 'next-year';

typedef NextYearPart = ({String name, Future<void> Function(DemoSession s, DemoState st, DemoWorld w, DateTime today) run});

const _y = DemoYear.y2026;

final List<NextYearPart> nextYearParts = [
  (name: '$nextYearStep.srp-2025', run: (s, st, w, today) => _srp(s, st)),
  (name: '$nextYearStep.rosters', run: (s, st, w, today) => runRosters(s, st, w, _y)),
  (
    name: '$nextYearStep.crla-bosy',
    run: (s, st, w, today) => runCrla(s, st, w, _y, today: today, plan: const DemoRoundPlan(rounds: {'bosy'})),
  ),
  (
    name: '$nextYearStep.phil-iri-bosy',
    run: (s, st, w, today) => runPhilIri(s, st, w, _y,
        today: today,
        plan: DemoRoundPlan(
          rounds: const {'bosy'},
          assess: (l, round) => w.gapOf(l) != DemoGap.missedBosy,
          recordGst: (l) => w.gapOf(l) != DemoGap.noGst,
        )),
  ),
  (name: '$nextYearStep.aral-roster', run: (s, st, w, today) => runAral(s, st, w, _y, today: today, sessions: false)),
  (name: '$nextYearStep.leavers-aug', run: (s, st, w, today) => _leaversAugust(s, st, w)),
  (name: '$nextYearStep.aral-sessions', run: (s, st, w, today) => runAral(s, st, w, _y, today: today, roster: false)),
  (name: '$nextYearStep.leavers-oct', run: (s, st, w, today) => _leaversOctober(s, st, w)),
  (
    name: '$nextYearStep.crla-mosy',
    run: (s, st, w, today) async =>
        runCrla(s, st, w, _y, today: today, plan: await mosyPlan(s, st, w, round: 'mosy')),
  ),
  (
    name: '$nextYearStep.phil-iri-mosy',
    run: (s, st, w, today) async =>
        runPhilIri(s, st, w, _y, today: today, plan: await mosyPlan(s, st, w, round: 'mosy1')),
  ),
  (name: '$nextYearStep.one-minute-ready', run: (s, st, w, today) => _oneMinuteReady(s, st, w, today)),
  (name: '$nextYearStep.anonymize-preview', run: (s, st, w, today) => _anonymizePreview(s, st)),
];

// ---- SRP 2025-2026 ----

Future<void> _srp(DemoSession s, DemoState st) async {
  const year = '2025-2026';
  final tutorEmails = [for (final k in ['tutor1.hs', 'tutor2.hs', 'tutor3.hs']) demoAccount(k).email];
  final vm = (await s.as('coord.hs')).tutor.srpVm;
  final schoolId = schoolIdOf(st, 'NCHS-DEMO');
  var classes = await vm.classes(schoolId: schoolId, schoolYear: year);
  if (classes.isEmpty) classes = await vm.buildClasses(schoolId: schoolId, schoolYear: year);
  for (final (i, c) in classes.indexed) {
    await vm.updateClass(
      c.srpClass.id!,
      room: 'Room ${101 + i}',
      schedule: 'Apr 20 - May 22, Mon-Fri ${i.isEven ? '8:00-10:00 AM' : '10:00 AM-12:00 NN'}',
      tutorEmail: tutorEmails[i % tutorEmails.length],
    );
  }
  final learners = classes.fold<int>(0, (n, c) => n + c.learners.length);
  stdout.writeln('  SRP $year: ${classes.length} class(es), $learners learner(s), room, schedule and tutor set');
}

// ---- SF1 leavers ----

DemoSection _section(DemoWorld w, String name) =>
    w.sections.singleWhere((x) => x.year == _y && x.schoolCode == 'NCHS-DEMO' && x.name == name);

DemoLeave? _leave(DemoLearner l) => l.years[_y]?.leave;

/// The August re-import of Grade 8 - Acacia (as of 2026-08-17) without the
/// four leavers; the coordinator decides each from the missing list.
Future<void> _leaversAugust(DemoSession s, DemoState st, DemoWorld w) async {
  final acacia = _section(w, demoSectionName(8)), narra = _section(w, demoNarraSection);
  final learners = w.inSection(acacia);
  final byLrn = {for (final l in learners) l.lrn: l};
  final dev = await s.as('coord.hs');
  final admin = dev.admin!;
  final path = writeDemoSf1(s.dir, acacia, [for (final l in learners) if (_leave(l) == null) l],
      await Sf1ColumnMap.load(dev.dir.path),
      tag: '2026-08');
  final r = await admin.importVm.import(path);
  if (r.conflicts > 0) throw StateError('the August Grade 8 SF1 gave ${r.conflicts} conflict(s)');
  final narraId = st.ids[demoSectionIdKey(narra)]!;
  final acaciaId = st.ids[demoSectionIdKey(acacia)]!;
  final vm = admin.learnerLeaversVm;
  final done = <String>[];
  for (final m in await vm.missing(sectionId: acaciaId)) {
    final leave = byLrn[m.lrn] == null ? null : _leave(byLrn[m.lrn]!);
    switch (leave) {
      case DemoLeave.transferredOut:
        await vm.archive(m.enrollmentId, EnrollmentStatus.transferredOut, note: 'Moved to a school in Cebu');
      case DemoLeave.droppedOut:
        await vm.archive(m.enrollmentId, EnrollmentStatus.droppedOut, note: 'Family moved to the farm; stopped attending');
      case DemoLeave.returning:
        await vm.archive(m.enrollmentId, EnrollmentStatus.droppedOut, note: 'Stopped attending in July');
      case DemoLeave.movedSection:
        await vm.move(m.enrollmentId, narraId);
      case null:
        throw StateError('${m.lrn} (${m.name}) is missing from the August SF1 but is no leaver');
    }
    done.add('${m.name}: ${leave?.name}');
  }
  await dev.shared.syncVm.pull();
  stdout.writeln('  August Grade 8 SF1: ${done.isEmpty ? 'nothing left to decide' : done.join('; ')}');
}

/// The October re-import with the returner back on it: restored.
Future<void> _leaversOctober(DemoSession s, DemoState st, DemoWorld w) async {
  final acacia = _section(w, demoSectionName(8));
  final learners = [
    for (final l in w.inSection(acacia))
      if (_leave(l) == null || _leave(l) == DemoLeave.returning) l,
  ];
  final dev = await s.as('coord.hs');
  final admin = dev.admin!;
  final path = writeDemoSf1(s.dir, acacia, learners, await Sf1ColumnMap.load(dev.dir.path), tag: '2026-10');
  final trial = await admin.importVm.trial(path);
  var restored = 0;
  for (final row in trial.rows.where((r) => r.outcome == 'returning')) {
    await admin.learnerLeaversVm.restore(row.enrollmentId!);
    restored++;
  }
  final r = await admin.importVm.import(path);
  if (r.conflicts + r.waiting > 0) {
    throw StateError('the October Grade 8 SF1 gave ${r.conflicts} conflict(s), ${r.waiting} waiting');
  }
  await dev.shared.syncVm.pull();
  stdout.writeln('  October Grade 8 SF1: $restored returning learner(s) restored');
}

Future<void> _anonymizePreview(DemoSession s, DemoState st) async {
  final admin = (await s.as('coord.hs')).admin!;
  final p = await admin.learnerLeaversVm.anonymizePreview();
  stdout.writeln('  anonymize preview (not run): ${p.learners.length} learner(s) may be anonymized now');
}

// ---- MOSY #1 ----

/// MOSY: who is in the round's sections now, who assesses them (a learner in
/// an ARAL class: the class tutor), and who is done so far (the window is
/// open: about 3 in 4 class learners, 3 in 5 of the others; gap 1 learners
/// not at all).
Future<DemoRoundPlan> mosyPlan(DemoSession s, DemoState st, DemoWorld w, {required String round}) async {
  final classTutor = <String, String>{}; // LRN -> tutor key
  for (final school in ['NCES-DEMO', 'NCHS-DEMO']) {
    final tutorKeys = [for (final a in demoAccounts) if (a.schoolCode == school && a.key.startsWith('tutor')) a.key];
    final keyOfId = <String, String>{
      for (final k in tutorKeys) (await s.as(k)).ctx.authVm.currentUser!.id: k,
    };
    final dev = await s.as(coordinatorOf(school));
    await dev.shared.syncVm.pull();
    final schoolId = schoolIdOf(st, school);
    final tutorOfClass = {
      for (final c in await dev.tutor.aralClassVm.classes(schoolId: schoolId, schoolYear: _y.label))
        if (c.tutorId != null && keyOfId.containsKey(c.tutorId)) c.id!: keyOfId[c.tutorId]!,
    };
    final lrnOf = <int, String>{};
    for (final l in w.learners.where((l) => l.years[_y]?.schoolCode == school)) {
      final student = await dev.shared.studentRepo.findByLrn(l.lrn);
      if (student != null) lrnOf[student.id!] = l.lrn;
    }
    for (final e in await dev.tutor.aralVm.schoolRoster(schoolId: schoolId, schoolYear: _y.label)) {
      final tutor = tutorOfClass[e.classId];
      final lrn = lrnOf[e.studentId];
      if (e.isActive && tutor != null && lrn != null) classTutor[lrn] = tutor;
    }
  }
  final narra = _section(w, demoNarraSection);
  final moved = w.learners.where((l) => _leave(l) == DemoLeave.movedSection).toList();
  bool doneSoFar(DemoLearner l) =>
      Random(int.parse(l.lrn.substring(4)) * 13 + 5).nextDouble() < (classTutor.containsKey(l.lrn) ? 0.75 : 0.60);
  stdout.writeln('  MOSY plan: ${classTutor.length} learner(s) in ARAL classes, assessed by their class tutor');
  return DemoRoundPlan(
    rounds: {round},
    roster: (sec) => [
      for (final l in w.inSection(sec))
        if (_leave(l) == null || _leave(l) == DemoLeave.returning) l,
      if (sec.year == narra.year && sec.name == narra.name) ...moved,
    ],
    assess: (l, r) => w.gapOf(l) != DemoGap.missedMosy && doneSoFar(l),
    classTutor: (l, r) => classTutor[l.lrn],
    timedRounds: const {'mosy1'},
  );
}

// ---- One-minute readings left for the owner ----

/// LRN of the learner of each Grade 5, 8, 9 and 10 section (2026-2027) the
/// step prepares: not assessed in MOSY #1 so far, no gap, no ARAL class.
Future<void> _oneMinuteReady(DemoSession s, DemoState st, DemoWorld w, DateTime today) async {
  final plan = await mosyPlan(s, st, w, round: 'mosy1');
  for (final grade in [5, 8, 9, 10]) {
    final section = w.sections
        .singleWhere((x) => x.year == _y && x.grade == grade && x.name == demoSectionName(grade));
    final key = 'one-minute.${demoSectionKey(section)}';
    if (st.ids.containsKey(key)) continue;
    final l = plan.learnersOf(w, section).firstWhere(
        (l) => w.gapOf(l) == null && l.story == null && plan.classTutor!(l, 'mosy1') == null && !plan.assesses(l, 'mosy1'));
    final tutor = section.tutorAccounts.first;
    final dev = await s.as(tutor);
    await dev.shared.syncVm.pull();
    final vm = dev.tutor.philIriVm;
    final student = (await dev.shared.studentRepo.findByLrn(l.lrn))!;
    final a = await vm.startSession(
        studentId: student.id!,
        sectionId: st.ids[demoSectionIdKey(section)]!,
        schoolYear: _y.label,
        round: PhilIriRound.mosy1,
        assessedAt: today);
    final options = [
      for (final p in await vm.availablePassages(a.id!, method: PhilIriReadingMethod.oneMinute))
        if (p.level != null && (await vm.questions(p.id!)).isNotEmpty) p,
    ];
    final passage = options[Random(int.parse(l.lrn.substring(4))).nextInt(options.length)];
    final reading = await vm.startReading(assessmentId: a.id!, passageId: passage.id!, method: PhilIriReadingMethod.oneMinute);
    await uploadAndDecide(s, tutor, coordinatorOf(section.schoolCode));
    await st.putId(key, student.id!);
    stdout.writeln('  ${section.name}: ${l.last}, ${l.first} (LRN ${l.lrn}) ready for a one-minute reading of '
        '"${passage.title}" on $tutor (session ${a.id}, reading ${reading.id}, before the upload)');
  }
}
