// ARAL phase (demo-data plan Task 10): one school year of ARAL-Reading, as
// the people who do it would record it.
//   - Materials (demo.super, written to the server at once): 8 catalog
//     entries over Foundational/KS1/KS2/KS3 at each demo school (the schools'
//     own, so no other school sees them) and a per-school link.
//   - Roster and classes (each coordinator, on their device, then uploaded):
//     every learner BASA proposes from the basis round is enrolled, dated the
//     day after that round's window closed; one teacher referral at the HS;
//     classes per home grade and program of at most the school's maximum
//     (10), small leftovers of a grade in one mixed-program class, tutors in
//     turn; two ES learners stay waiting for a class.
//   - Each month, each class tutor on their own device: sessions on three
//     fixed weekdays up to the EOSY window (attendance: all present, then 5-10%
//     absent and 2% excused), the IRIP rated weekly (by the learner's trend)
//     with the next week or cycle, the check-ins after sessions 16 and 32
//     (KS2-3), readability entries at the HS (SHARP on); then the month is
//     uploaded and decided.
//   - At the end each coordinator applies the results (exits: grade-level
//     ready, KS1 classroom support) and uploads.
// Each step is resumable: roster entries by learner, classes by grade and
// program, sessions by class and date, check-ins by checkpoint, IRIP by its
// unrated weeks.
import 'dart:io';
import 'dart:math';

import 'package:basa_capstone/core/models/aral_checkin.dart';
import 'package:basa_capstone/core/models/aral_class.dart';
import 'package:basa_capstone/core/models/aral_enrollment.dart';
import 'package:basa_capstone/core/models/aral_irip.dart';
import 'package:basa_capstone/core/models/aral_session.dart';
import 'package:basa_capstone/viewmodels/aral_checkin_viewmodel.dart';
import 'package:basa_capstone/viewmodels/aral_irip_viewmodel.dart';
import 'package:basa_capstone/viewmodels/aral_viewmodel.dart';

import '../../command_pass/device.dart';
import '../dates.dart';
import '../session.dart';
import '../state.dart';
import '../sync_steps.dart';
import '../world.dart';
import 'rosters.dart';
import 'setup.dart';

String aralStep(DemoYear y) => 'aral-${y.label.substring(0, 4)}';

const _schools = ['NCES-DEMO', 'NCHS-DEMO'];

List<String> _tutorsOf(String school) => [
      for (final a in demoAccounts)
        if (a.schoolCode == school && a.key.startsWith('tutor')) a.key,
    ];

String _iso(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

Future<void> runAral(DemoSession s, DemoState st, DemoWorld w, DemoYear y, {required DateTime today}) async {
  final base = aralStep(y);
  // materials-school: the demo's materials belong to its schools (2026-11-26).
  if (!st.done('$base.materials-school')) {
    await _materials(s, st);
    await st.markDone('$base.materials-school');
  }
  for (final school in _schools) {
    final step = '$base.$school.roster';
    if (st.done(step)) continue;
    await _roster(s, st, w, y, school);
    await st.markDone(step);
  }

  // Sessions month by month, every tutor of both schools.
  final windows = demoWindows(y);
  final eosyOpens = windows.firstWhere((x) => x.round == 'eosy').opens;
  final days = sessionDays(y, today: today, perWeek: 3).where((d) => d.isBefore(eosyOpens)).toList();
  final months = <String>{for (final d in days) _iso(d).substring(0, 7)}.toList()..sort();
  final pulled = <String>{};
  for (final month in months) {
    for (final school in _schools) {
      for (final tutor in _tutorsOf(school)) {
        final step = '$base.$tutor.$month';
        if (st.done(step)) continue;
        final dev = await s.as(tutor);
        if (pulled.add(tutor)) await dev.shared.syncVm.pull(); // the coordinator's classes
        final n = await _month(s, st, w, y, school, tutor, [for (final d in days) if (_iso(d).startsWith(month)) d]);
        await settlePending(s, tutor, coordinatorOf(school)); // may switch devices
        if ((await (await s.as(tutor)).shared.syncVm.preview()).package.isEmpty == false) {
          await uploadAndDecide(s, tutor, coordinatorOf(school));
        }
        stdout.writeln('  $tutor $month: $n');
        await st.markDone(step);
      }
    }
  }

  for (final school in _schools) {
    final step = '$base.$school.exits';
    if (st.done(step)) continue;
    final coordinator = coordinatorOf(school);
    final dev = await s.as(coordinator);
    await dev.shared.syncVm.pull(); // the tutors' months
    final updates = await dev.tutor.aralVm.applySchoolResults(schoolId: schoolIdOf(st, school), schoolYear: y.label);
    final exits = updates.where((u) => u.kind == AralUpdateKind.exited).length;
    final moved = updates.where((u) => u.kind == AralUpdateKind.programChanged).length;
    if ((await dev.shared.syncVm.preview()).package.isEmpty == false) {
      await uploadAndDecide(s, coordinator, coordinator);
    }
    stdout.writeln('  $school results: $exits exit(s), $moved program change(s)');
    await st.markDone(step);
  }
}

// ---- Materials ----

const _catalog = [
  ('Pagbasa sa Baryo - Level 1', AralKeyStage.foundational, null, 1, 3),
  ('Tunog at Titik - Unang Hakbang', AralKeyStage.ks1, null, 1, 3),
  ('Kuwento ng Aking Barangay', AralKeyStage.ks1, null, 1, 3),
  ('Reading Bridges - Basic', AralKeyStage.ks2, AralTrack.basic, 4, 6),
  ('Reading Bridges - Plus', AralKeyStage.ks2, AralTrack.plus, 4, 6),
  ('Stories from the Coast - Basic', AralKeyStage.ks3, AralTrack.basic, 7, 10),
  ('Stories from the Coast - Plus', AralKeyStage.ks3, AralTrack.plus, 7, 10),
  ('Word Power for Young Readers', AralKeyStage.ks3, AralTrack.basic, 7, 10),
];

Future<void> _materials(DemoSession s, DemoState st) async {
  final vm = (await s.as('demo.super')).tutor.aralMaterialVm;
  final titles = {for (final c in _catalog) c.$1};
  // The first demo build added these region-wide, where every school (the
  // command pass's too) sees them; the demo's materials are its schools' own.
  var removed = 0;
  for (final m in await vm.catalog()) {
    if (m.schoolId != null || !titles.contains(m.title)) continue;
    for (final school in _schools) {
      try {
        await vm.setSchoolLink(m.id!, schoolIdOf(st, school), null);
      } on Exception catch (e) {
        if (!'$e'.contains('the school has none')) rethrow; // only the first entry had links
      }
    }
    await vm.deleteMaterial(m.id!);
    removed++;
  }
  var added = 0;
  for (final school in _schools) {
    final schoolId = schoolIdOf(st, school);
    final have = {for (final m in await vm.catalog()) if (m.schoolId == schoolId) m.title};
    for (final (title, ks, track, minG, maxG) in _catalog) {
      if (have.contains(title)) continue;
      final slug = title.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-');
      await vm.addMaterial(
        schoolId: schoolId,
        title: title,
        keyStage: ks,
        track: track,
        language: minG <= 3 ? 'Filipino' : 'English',
        minGrade: minG,
        maxGrade: maxG,
        fileName: '$slug.pdf',
        link: 'https://example.org/basa-demo/$slug',
      );
      added++;
    }
    final first = (await vm.catalog()).firstWhere((m) => m.schoolId == schoolId && m.title == _catalog.first.$1);
    await vm.setSchoolLink(first.id!, schoolId, 'https://example.org/basa-demo/${school.toLowerCase()}/level-1');
  }
  stdout.writeln('  materials: $removed region-wide demo entr${removed == 1 ? 'y' : 'ies'} removed, '
      '$added added as the schools’ own, a school link at each school');
}

// ---- Roster and classes ----

/// The day after the basis round's window closed (the learner joins ARAL
/// once that round's results are in).
DateTime _enteredOn(DemoYear y, int grade, String? basisRound) {
  final instrument = grade <= 3 ? 'crla' : 'phil_iri';
  final w = demoWindows(y).where((x) => x.instrument == instrument && x.round == basisRound).firstOrNull ??
      demoWindows(y).firstWhere((x) => x.instrument == instrument && x.round == 'bosy');
  return w.closes.add(const Duration(days: 1));
}

Future<void> _roster(DemoSession s, DemoState st, DemoWorld w, DemoYear y, String school) async {
  final coordinator = coordinatorOf(school);
  // The tutors' user ids first: one device is open at a time, so signing in
  // as a tutor later would close the coordinator's database.
  final tutorIds = <String, String>{
    for (final t in _tutorsOf(school)) t: (await s.as(t)).ctx.authVm.currentUser!.id,
  };
  final dev = await s.as(coordinator);
  await dev.shared.syncVm.pull();
  final aral = dev.tutor.aralVm, classes = dev.tutor.aralClassVm;
  final schoolId = schoolIdOf(st, school);
  var enrolled = 0, referred = 0;

  for (final section in w.sections.where((x) => x.year == y && x.schoolCode == school)) {
    final sectionId = st.ids['section.${y.label}.$school.G${section.grade}']!;
    final candidates = await aral.propose(sectionId: sectionId, schoolYear: y.label);
    for (final c in candidates.where((c) => c.status == AralCandidateStatus.proposed)) {
      await aral.enroll(
          sectionId: sectionId,
          schoolYear: y.label,
          studentId: c.student.id!,
          enteredOn: _enteredOn(y, section.grade, c.basisRound));
      enrolled++;
    }
    // One teacher referral at the HS: a Grade 9 learner reading at grade level.
    if (school == 'NCHS-DEMO' && section.grade == 9) {
      final already = (await aral.roster(sectionId: sectionId, schoolYear: y.label)).any((e) => e.basisSource == AralBasisSource.referral);
      final pick = candidates.where((c) => c.status == AralCandidateStatus.notQualified).firstOrNull;
      if (!already && pick != null) {
        await aral.refer(
            sectionId: sectionId,
            schoolYear: y.label,
            studentId: pick.student.id!,
            keyStage: AralKeyStage.ks3,
            track: AralTrack.basic,
            referredBy: section.adviserName,
            reason: 'Struggles with longer texts in class',
            enteredOn: _enteredOn(y, 9, 'bosy'));
        referred++;
      }
    }
  }

  // Classes: per home grade and program, at most the school's maximum; a
  // grade's groups below the minimum go together in one mixed class.
  final maxSize = await classes.classMax(schoolId), minSize = await classes.classMin(schoolId);
  final roster = (await aral.schoolRoster(schoolId: schoolId, schoolYear: y.label)).where((e) => e.isActive).toList()
    ..sort((a, b) => a.id!.compareTo(b.id!));
  final gradeOf = <int, int>{
    for (final section in w.sections.where((x) => x.year == y && x.schoolCode == school))
      st.ids['section.${y.label}.$school.G${section.grade}']!: section.grade,
  };
  final groups = <(int, AralClassProgram?), List<AralEnrollment>>{};
  for (final e in roster) {
    final grade = gradeOf[e.sectionId]!;
    groups.putIfAbsent((grade, AralClassProgram.of(e.keyStage, e.track)), () => []).add(e);
  }
  // Small groups of a grade -> one mixed group (when more than one is small).
  for (final grade in {for (final k in groups.keys) k.$1}) {
    final small = [for (final k in groups.keys) if (k.$1 == grade && k.$2 != null && groups[k]!.length < minSize) k];
    if (small.length < 2) continue;
    final mixed = groups.putIfAbsent((grade, null), () => []);
    for (final k in small) {
      mixed.addAll(groups.remove(k)!);
    }
  }
  // Two ES learners wait for a class: the last two of the largest group.
  final held = <int>{};
  if (school == 'NCES-DEMO' && groups.isNotEmpty) {
    final largest = groups.values.reduce((a, b) => a.length >= b.length ? a : b);
    held.addAll(largest.skip(max(0, largest.length - 2)).map((e) => e.id!));
  }

  final tutors = _tutorsOf(school);
  var made = 0, placed = 0, turn = 0;
  final keys = groups.keys.toList()..sort((a, b) => a.$1 != b.$1 ? a.$1.compareTo(b.$1) : (a.$2?.index ?? 99).compareTo(b.$2?.index ?? 99));
  for (final key in keys) {
    final (grade, program) = key;
    var existing = (await classes.classes(schoolId: schoolId, schoolYear: y.label))
        .where((c) => c.gradeLevel == grade && c.program == program)
        .toList();
    for (final e in groups[key]!) {
      if (e.classId != null || held.contains(e.id)) continue;
      AralClass? room;
      for (final c in existing) {
        if (await classes.activeCount(c.id!) < maxSize) {
          room = c;
          break;
        }
      }
      if (room == null) {
        final tutor = tutors[turn++ % tutors.length];
        room = await classes.createClass(
          schoolId: schoolId,
          schoolYear: y.label,
          className: await classes.suggestClassName(schoolId: schoolId, schoolYear: y.label, grade: grade),
          gradeLevel: grade,
          program: program,
          tutorId: tutorIds[tutor],
          room: 'Reading Room ${made % 3 + 1}',
          schedule: 'Mon, Wed, Fri ${made.isEven ? '1:00-2:00 PM' : '2:00-3:00 PM'}',
          sessionType: made.isEven ? AralSessionType.pullOut : AralSessionType.beforeAfter,
        );
        existing = [...existing, room];
        made++;
      }
      await classes.place(e.id!, room.id!);
      placed++;
    }
  }
  if ((await dev.shared.syncVm.preview()).package.isEmpty == false) {
    await uploadAndDecide(s, coordinator, coordinator);
  }
  stdout.writeln('  $school roster: $enrolled enrolled, $referred referred, $made class(es) made, $placed placed, '
      '${held.length} waiting (class size $minSize-$maxSize)');
}

// ---- A tutor's month ----

AralIripStatus _iripStatus(DemoLearner? l, Random rng) {
  final r = rng.nextDouble();
  final (observed, partial) = l?.story == DemoStory.noImprovement
      ? (0.05, 0.40)
      : switch (l?.trend) {
          DemoTrend.improves => (0.70, 0.95),
          DemoTrend.slips => (0.25, 0.70),
          _ => (0.40, 0.85),
        };
  return r < observed ? AralIripStatus.observed : (r < partial ? AralIripStatus.partial : AralIripStatus.notObserved);
}

double _checkinRight(DemoLearner? l, int checkpoint) {
  if (l?.story == DemoStory.noImprovement) return 0.35; // fails both
  return switch (l?.trend) {
    DemoTrend.improves => checkpoint == 16 ? 0.75 : 0.9,
    DemoTrend.slips => 0.55,
    _ => checkpoint == 16 ? 0.65 : 0.8,
  };
}

final _idCache = <String, Map<int, DemoLearner>>{};

/// The school's learners of [y] on [tutor]'s device, by student id (ids are
/// the server's), looked up once per run.
Future<Map<int, DemoLearner>> _learnersById(Device dev, String tutor, DemoWorld w, DemoYear y, String school) async {
  final cached = _idCache[tutor];
  if (cached != null) return cached;
  final out = <int, DemoLearner>{};
  for (final l in w.learners.where((l) => l.years[y]?.schoolCode == school)) {
    final student = await dev.shared.studentRepo.findByLrn(l.lrn);
    if (student != null) out[student.id!] = l;
  }
  return _idCache[tutor] = out;
}

/// Records [days] for every class [tutor] teaches; returns a summary line.
Future<String> _month(DemoSession s, DemoState st, DemoWorld w, DemoYear y, String school, String tutor,
    List<DateTime> days) async {
  final dev = await s.as(tutor);
  final t = dev.tutor;
  final schoolId = schoolIdOf(st, school);
  final learners = await _learnersById(dev, tutor, w, y, school);
  final sharp = school == 'NCHS-DEMO' && await t.aralReadabilityVm.available(schoolId);
  var sessions = 0, marks = 0, ratings = 0, checkins = 0, readability = 0;

  for (final c in await t.aralClassVm.classes(schoolId: schoolId, schoolYear: y.label)) {
    final roster = await t.aralClassVm.classRoster(c.id!);
    if (roster.isEmpty) continue;
    final learner = <int, DemoLearner?>{};
    for (final e in roster) {
      learner[e.id!] = learners[e.studentId];
    }
    final start = roster.map((e) => e.enteredOn).reduce((a, b) => a.compareTo(b) <= 0 ? a : b);
    final held = {for (final x in await t.aralSessionVm.classSessions(c.id!)) x.heldOn};
    for (final day in days) {
      final date = _iso(day);
      if (date.compareTo(start) < 0 || held.contains(date)) continue;
      final rng = Random(c.id!.abs() * 1000 + day.difference(DateTime(2025)).inDays);
      final session = await t.aralSessionVm.logSession(
        classId: c.id!,
        heldOn: day,
        minutes: 45 + rng.nextInt(4) * 5,
        setup: c.sessionType == AralSessionType.beforeAfter ? AralSetup.afterClass : AralSetup.pullOut,
        lesson: 'Reading lesson ${(held.length + sessions) % 24 + 1}',
      );
      sessions++;
      final here = roster.where((e) => e.enteredOn.compareTo(date) <= 0).toList();
      if (here.isEmpty) continue;
      await t.aralSessionVm.markRest(session.id!, AralMark.present);
      for (final e in here) {
        final r = rng.nextDouble();
        if (r < 0.02) {
          await t.aralSessionVm.mark(session.id!, e.id!, AralMark.excused, note: 'Sick');
          marks++;
        } else if (r < 0.02 + 0.05 + rng.nextDouble() * 0.05) {
          await t.aralSessionVm.mark(session.id!, e.id!, AralMark.absent);
          marks++;
        }
      }

      // Check-ins after the class's 16th and 32nd session (KS2-3).
      final checkpoint = switch (session.sessionNo) { 16 => 16, 32 => 32, _ => null };
      if (checkpoint != null) {
        for (final e in here.where((e) => e.track != null)) {
          checkins += await _checkin(t.aralCheckinVm, e, checkpoint, day, learner[e.id], rng);
        }
      }

      // The IRIP on the week's last session (Friday): rate, then go on.
      if (day.weekday == DateTime.friday) {
        for (final e in here) {
          ratings += await _irip(t.aralIripVm, e.id!, day, learner[e.id], rng);
        }
      }

      // Readability at the HS: an entry for each learner about once a month.
      if (sharp && day.day <= 7 && day.weekday == DateTime.monday) {
        for (final e in here) {
          final words = 120 + rng.nextInt(180);
          final sentences = max(6, words ~/ (10 + rng.nextInt(8)));
          await t.aralReadabilityVm.add(
            enrollmentId: e.id!,
            title: 'Class story, ${_iso(day)}',
            words: words,
            sentences: sentences,
            syllables: (words * (1.3 + rng.nextDouble() * 0.4)).round(),
            readOn: day,
          );
          readability++;
        }
      }
    }
  }
  return '$sessions session(s), $marks absent/excused mark(s), $ratings IRIP rating(s), $checkins check-in(s), '
      '$readability readability entr${readability == 1 ? 'y' : 'ies'}';
}

/// Rates the learner's unrated weeks on [day] and adds the next week (or the
/// next cycle). Returns the ratings made.
Future<int> _irip(AralIripViewModel vm, int enrollmentId, DateTime day, DemoLearner? l, Random rng) async {
  var plan = await vm.plan(enrollmentId);
  if (!plan.hasIrip) return 0;
  if (!plan.started) {
    await vm.startCycle(enrollmentId);
    plan = await vm.plan(enrollmentId);
  }
  var n = 0;
  for (final week in plan.weeks.where((x) => x.cycleNo == plan.currentCycle && !x.isRated)) {
    await vm.rate(week.id!, _iripStatus(l, rng), on: day);
    n++;
  }
  plan = await vm.plan(enrollmentId);
  if (plan.canStartCycle) {
    await vm.startCycle(enrollmentId);
    return n;
  }
  // The next week of each strand: BASA's suggested target, or, when every
  // target of the list is observed, one the tutor picks to review.
  for (final strand in plan.strands.where((x) => !x.cycleDone)) {
    final review = plan.targets.where((x) => x.strand == strand.strand).toList();
    final pick = strand.suggestion?.id ?? (review.isEmpty ? null : review[rng.nextInt(review.length)].id);
    if (pick == null) continue;
    await vm.nextWeek(enrollmentId, strand: strand.strand, targetId: strand.suggestion == null ? pick : null);
  }
  return n;
}

/// The learner's check-in at [checkpoint] on [day], unless they have one.
Future<int> _checkin(AralCheckinViewModel vm, AralEnrollment e, int checkpoint, DateTime day, DemoLearner? l, Random rng) async {
  final history = await vm.learnerCheckins(e.id!);
  final tool = history.toolsByCheckpoint[checkpoint];
  if (tool == null) return 0;
  if (history.results.any((r) => r.tool.id == tool.id)) return 0;
  final c = await vm.startCheckin(e.id!, checkpoint, on: day);
  final right = _checkinRight(l, checkpoint);
  for (final item in await vm.items(c.toolId)) {
    final ok = rng.nextDouble() < right;
    if (item.kind == AralCheckinItemKind.choice) {
      final key = item.answerKey ?? 'A';
      final wrong = ['A', 'B', 'C', 'D'].where((x) => x != key).toList();
      await vm.answerChoices(c.id!, item.itemNo, [ok ? key : wrong[rng.nextInt(wrong.length)]]);
    } else {
      await vm.markOpen(c.id!, item.itemNo, ok);
    }
  }
  return 1;
}
