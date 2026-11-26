// Leftovers (demo-data plan Task 12): the rest of the deliberate gaps and
// the sync story, after 2026-2027.
//   gap4-philiri  a Phil-IRI MOSY #1 session left in progress (Grade 7 -
//                 Molave, tutor1.hs): passage started, a few miscues, no time
//   gap4-crla     a CRLA MOSY attempt with Part 1 only (Grade 2 - Gumamela,
//                 tutor1.es): no Part 2, so no reading profile
//   gap5-sf1      an October Grade 7 SF1: one new learner with a blank birth
//                 date, one row whose LRN is a Grade 9 learner's under another
//                 name (an import conflict, left for the coordinator)
//   pending       tutor2.hs rates a few IRIP weeks and uploads: left pending
//   rejected      tutor3.hs logs a session and uploads: coord.hs rejects it
//                 ("Wrong date on the session, please fix and resend"); its
//                 rows stay on tutor3.hs's builder device
//   sign-ins      every demo account signs in once more; tutor1.es once
//                 offline (logged on that device only)
import 'dart:io';
import 'dart:math';

import 'package:basa_capstone/core/models/aral_irip.dart';
import 'package:basa_capstone/core/models/aral_session.dart';
import 'package:basa_capstone/core/models/crla_assessment.dart';
import 'package:basa_capstone/core/models/phil_iri_assessment.dart';
import 'package:basa_capstone/core/models/phil_iri_miscue.dart';
import 'package:basa_capstone/core/services/sf1_column_map.dart';

import '../records.dart';
import '../session.dart';
import '../sf1_files.dart';
import '../state.dart';
import '../sync_steps.dart';
import '../world.dart';
import 'crla.dart';
import 'next_year.dart';
import 'rosters.dart';
import 'setup.dart';

const leftoversStep = 'leftovers';
const demoRejectReason = 'Wrong date on the session, please fix and resend';

/// The new learner and the conflicting row of the October Grade 7 SF1.
const demoBlankBirthLrn = '999100009001';

typedef LeftoverPart = ({String name, Future<void> Function(DemoSession s, DemoState st, DemoWorld w, DateTime today) run});

final List<LeftoverPart> leftoverParts = [
  (name: '$leftoversStep.gap4-philiri', run: _philIriInProgress),
  (name: '$leftoversStep.gap4-crla', run: _crlaPart1Only),
  (name: '$leftoversStep.gap5-sf1', run: (s, st, w, today) => _sf1Problems(s, st, w)),
  (name: '$leftoversStep.pending', run: _pendingUpload),
  (name: '$leftoversStep.rejected', run: _rejectedUpload),
  (name: '$leftoversStep.sign-ins', run: (s, st, w, today) => _signIns(s)),
];

const _y = DemoYear.y2026;

DemoSection _section(DemoWorld w, int grade) =>
    w.sections.singleWhere((x) => x.year == _y && x.grade == grade && x.name == demoSectionName(grade));

/// A learner of [section] not read yet in the open MOSY, with no gap, no
/// story, no ARAL class and not one of the one-minute learners.
Future<DemoLearner> _unread(DemoSession s, DemoState st, DemoWorld w, DemoSection section, String round) async {
  final plan = await mosyPlan(s, st, w, round: round);
  final reserved = {for (final e in st.ids.entries) if (e.key.startsWith('one-minute.')) e.value};
  for (final l in plan.learnersOf(w, section)) {
    if (w.gapOf(l) != null || l.story != null || plan.classTutor!(l, round) != null || plan.assesses(l, round)) continue;
    final dev = await s.as(section.tutorAccounts.first);
    final id = (await dev.shared.studentRepo.findByLrn(l.lrn))!.id!;
    if (!reserved.contains(id)) return l;
  }
  throw StateError('no unread learner left in ${section.name}');
}

DateTime _yesterday(DateTime today) => DateTime(today.year, today.month, today.day - 1);

Future<void> _philIriInProgress(DemoSession s, DemoState st, DemoWorld w, DateTime today) async {
  final section = _section(w, 7);
  final l = await _unread(s, st, w, section, 'mosy1');
  final tutor = section.tutorAccounts.first;
  final dev = await s.as(tutor);
  final vm = dev.tutor.philIriVm;
  final studentId = (await dev.shared.studentRepo.findByLrn(l.lrn))!.id!;
  final a = await vm.startSession(
      studentId: studentId,
      sectionId: st.ids[demoSectionIdKey(section)]!,
      schoolYear: _y.label,
      round: PhilIriRound.mosy1,
      assessedAt: _yesterday(today));
  final options = [
    for (final p in await vm.availablePassages(a.id!)) if (p.level != null && (await vm.questions(p.id!)).isNotEmpty) p,
  ];
  final passage = options[Random(int.parse(l.lrn.substring(4))).nextInt(options.length)];
  final reading = await vm.startReading(assessmentId: a.id!, passageId: passage.id!);
  await vm.markMiscue(readingId: reading.id!, wordIndex: 3, type: PhilIriMiscueType.substitution, spokenText: 'the');
  await vm.markMiscue(readingId: reading.id!, wordIndex: 8, type: PhilIriMiscueType.omission);
  await vm.markMiscue(readingId: reading.id!, wordIndex: 15, type: PhilIriMiscueType.omission);
  await uploadAndDecide(s, tutor, coordinatorOf(section.schoolCode));
  stdout.writeln('  ${section.name}: ${l.last}, ${l.first} (LRN ${l.lrn}) has a MOSY #1 session in progress '
      '("${passage.title}", 3 miscues, no time)');
  await st.putId('leftover.philiri-in-progress', studentId);
}

Future<void> _crlaPart1Only(DemoSession s, DemoState st, DemoWorld w, DateTime today) async {
  final section = _section(w, 2);
  final l = await _unread(s, st, w, section, 'mosy');
  final tutor = section.tutorAccounts.first;
  final dev = await s.as(tutor);
  final crla = dev.tutor.crlaVm;
  final studentId = (await dev.shared.studentRepo.findByLrn(l.lrn))!.id!;
  final rng = Random(int.parse(l.lrn.substring(4)) * 31 + CrlaRound.mosy.index * 7 + _y.index);
  final a = await crla.startAssessment(
    studentId: studentId,
    sectionId: st.ids[demoSectionIdKey(section)]!,
    schoolYear: _y.label,
    subjectVariant: crlaVariantOf(section.grade),
    round: CrlaRound.mosy,
    administeredBy: dev.ctx.authVm.currentUser!.id,
    assessedAt: _yesterday(today),
  );
  final story = (await crla.storiesForAttempt(a.id!)).first;
  final p = crlaPlanFor(
      profile: crlaProfileFor(w.band(l, _y, 'mosy'), rng),
      grade: section.grade,
      variant: crlaVariantOf(section.grade),
      storyWords: story.wordCount,
      rng: rng,
      t: await crla.effectiveThresholds(st.ids['school.${section.schoolCode}']!));
  await crla.savePart1Standard(
      assessmentId: a.id!, task1Score: p.task1, task2LowScore: p.task2Low, task2HighScore: p.task2High);
  await uploadAndDecide(s, tutor, coordinatorOf(section.schoolCode));
  stdout.writeln('  ${section.name}: ${l.last}, ${l.first} (LRN ${l.lrn}) has a CRLA MOSY attempt with Part 1 only');
  await st.putId('leftover.crla-part1', studentId);
}

Future<void> _sf1Problems(DemoSession s, DemoState st, DemoWorld w) async {
  final g7 = _section(w, 7);
  final other = w.inSection(_section(w, 9)).firstWhere((l) => l.story == null && w.gapOf(l) == null);
  final rows = [
    ...w.inSection(g7),
    const DemoLearner(demoBlankBirthLrn, 'Dela Cruz', 'Andrea', 'M.', 'F', '', DemoTrend.stays, null, {},
        DemoBand.instructional),
    // The Grade 9 learner's LRN under another name: a typing slip on the SF1.
    DemoLearner(other.lrn, 'Ramos', 'Kevin', 'T.', 'M', '2013-03-14', DemoTrend.stays, null, const {},
        DemoBand.instructional),
  ];
  final dev = await s.as('coord.hs');
  final admin = dev.admin!;
  final path = writeDemoSf1(s.dir, g7, rows, await Sf1ColumnMap.load(dev.dir.path), tag: '2026-10-g7');
  final trial = await admin.importVm.trial(path);
  if (trial.wouldConflict != 1 || trial.wouldInsert != 1) {
    throw StateError('the October Grade 7 SF1 trial: ${trial.wouldInsert} insert(s), ${trial.wouldConflict} '
        'conflict(s) (expected 1 and 1): ${[for (final r in trial.rows) if (r.outcome != 'enrolled') '${r.name}: ${r.outcome} ${r.reason ?? ''}']}');
  }
  final r = await admin.importVm.import(path);
  await dev.shared.syncVm.pull();
  stdout.writeln('  October Grade 7 SF1: new ${r.inserted} (blank birth date, warnings ${trial.rowWarnings.length}), '
      'conflict ${r.conflicts} (LRN ${other.lrn} as Ramos, Kevin; on file as ${other.last}, ${other.first})');
}

Future<void> _pendingUpload(DemoSession s, DemoState st, DemoWorld w, DateTime today) async {
  const tutor = 'tutor2.hs';
  final dev = await s.as(tutor);
  final t = dev.tutor;
  final schoolId = schoolIdOf(st, 'NCHS-DEMO');
  final me = dev.ctx.authVm.currentUser!.id;
  var rated = 0;
  for (final c in (await t.aralClassVm.classes(schoolId: schoolId, schoolYear: _y.label)).where((c) => c.tutorId == me)) {
    for (final e in (await t.aralClassVm.classRoster(c.id!)).where((e) => e.isActive)) {
      final plan = await t.aralIripVm.plan(e.id!);
      if (!plan.hasIrip || !plan.started) continue;
      for (final week in plan.weeks.where((x) => x.cycleNo == plan.currentCycle && !x.isRated).take(1)) {
        await t.aralIripVm.rate(week.id!, AralIripStatus.partial, on: today);
        rated++;
      }
      if (rated >= 3) break;
    }
    if (rated >= 3) break;
  }
  if (rated == 0) throw StateError('$tutor has no unrated IRIP week to rate');
  final id = await uploadAndDecide(s, tutor, 'coord.hs', approve: false);
  await st.putId('leftover.pendingUpload', id);
  stdout.writeln('  $tutor: $rated IRIP rating(s) in upload $id, left pending for coord.hs');
}

Future<void> _rejectedUpload(DemoSession s, DemoState st, DemoWorld w, DateTime today) async {
  const tutor = 'tutor3.hs';
  final dev = await s.as(tutor);
  final t = dev.tutor;
  final schoolId = schoolIdOf(st, 'NCHS-DEMO');
  final me = dev.ctx.authVm.currentUser!.id;
  final c = (await t.aralClassVm.classes(schoolId: schoolId, schoolYear: _y.label)).firstWhere((c) => c.tutorId == me);
  final session = await t.aralSessionVm.logSession(
    classId: c.id!,
    heldOn: DateTime(today.year, today.month, today.day),
    minutes: 50,
    setup: AralSetup.pullOut,
    lesson: 'Reading lesson (sent with the wrong date)',
  );
  await t.aralSessionVm.markRest(session.id!, AralMark.present);
  final id = await uploadAndDecide(s, tutor, 'coord.hs', rejectReason: demoRejectReason);
  await st.putId('leftover.rejectedUpload', id);
  stdout.writeln('  $tutor: upload $id (a session of ${c.className}) rejected: "$demoRejectReason"');
}

Future<void> _signIns(DemoSession s) async {
  for (final a in demoAccounts) {
    await s.signInAgain(a.key);
  }
  final refused = await s.signInOffline('tutor1.es');
  if (refused != null) throw StateError('tutor1.es offline sign-in refused: $refused');
  stdout.writeln('  ${demoAccounts.length} accounts signed in again; tutor1.es signed in offline once');
}
