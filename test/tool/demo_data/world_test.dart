// The Night City demo world (spec docs/superpowers/specs/2026-11-24-demo-data-design.md,
// plan Task 2): fixed seed, sections of 36-44, LRNs 9991..., learners move up
// one grade, Grade 6 / Grade 10 leave, the stories, a realistic band mix.
import 'package:basa_capstone/core/models/user.dart';
import 'package:basa_capstone/core/models/user_role.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../tool/demo_data/names.dart';
import '../../../tool/demo_data/world.dart';

void main() {
  final w = DemoWorld.build();

  test('same seed gives the same world', () {
    final again = DemoWorld.build();
    expect(again.learners.map((l) => '${l.lrn} ${l.last}, ${l.first} ${l.middleInitial}'),
        w.learners.map((l) => '${l.lrn} ${l.last}, ${l.first} ${l.middleInitial}'));
  });

  test('sections and sizes', () {
    expect(w.sections.where((s) => s.year == DemoYear.y2025), hasLength(10));
    // 2026-2027: one per grade + HS Grade 8 - Narra.
    expect(w.sections.where((s) => s.year == DemoYear.y2026), hasLength(11));
    expect(w.sections.where((s) => s.year == DemoYear.y2026 && s.grade == 8).map((s) => s.name),
        unorderedEquals(['Acacia', 'Narra']));
    // Names as a real SF1 writes them: the grade is not part of the name
    // (screens show "Grade 8 · Acacia"; walkthrough finding 1).
    for (final s in w.sections) {
      expect(s.name, isNot(startsWith('Grade')));
      expect(demoOldSectionName(s), 'Grade ${s.grade} - ${s.name}');
    }
    for (final s in w.sections) {
      expect(w.inSection(s).length, inInclusiveRange(36, 44), reason: '${s.year.label} ${s.name}');
      expect(s.schoolCode, s.grade <= 6 ? 'NCES-DEMO' : 'NCHS-DEMO');
      expect(s.tutorAccounts, isNotEmpty);
    }
  });

  test('LRNs: 12 digits, 9991 prefix, unique', () {
    for (final l in w.learners) {
      expect(l.lrn, matches(RegExp(r'^9991\d{8}$')));
    }
    expect(w.learners.map((l) => l.lrn).toSet(), hasLength(w.learners.length));
  });

  test('grades move up; Grade 6 and Grade 10 leave; Grade 1 and 7 are new', () {
    for (final l in w.learners) {
      final a = l.years[DemoYear.y2025];
      final b = l.years[DemoYear.y2026];
      if (a != null && b != null) {
        expect(b.grade, a.grade + 1, reason: l.lrn);
        expect(b.schoolCode, a.schoolCode, reason: l.lrn);
      }
      if (a != null && (a.grade == 6 || a.grade == 10)) expect(b, isNull, reason: l.lrn);
      if (b != null && (b.grade == 1 || b.grade == 7)) expect(a, isNull, reason: l.lrn);
    }
  });

  test('stories', () {
    for (final s in DemoStory.values) {
      expect(w.learners.where((l) => l.story == s), hasLength(1), reason: s.name);
    }
    final up = w.story(DemoStory.movesUpThroughAral);
    expect((up.years[DemoYear.y2025]!.schoolCode, up.years[DemoYear.y2025]!.grade), ('NCES-DEMO', 3));
    expect(w.story(DemoStory.hsNonReader).years[DemoYear.y2025]!.grade, 7);
    for (final (story, leave) in [
      (DemoStory.transferredOut, DemoLeave.transferredOut),
      (DemoStory.droppedOut, DemoLeave.droppedOut),
      (DemoStory.movedSection, DemoLeave.movedSection),
      (DemoStory.returning, DemoLeave.returning),
    ]) {
      final e = w.story(story).years[DemoYear.y2026]!;
      expect(e.leave, leave);
      expect((e.schoolCode, e.grade), ('NCHS-DEMO', 8));
    }
    expect(w.band(up, DemoYear.y2025, 'bosy'), DemoBand.struggling);
    expect(w.band(up, DemoYear.y2025, 'eosy'), DemoBand.instructional);
    expect(w.band(w.story(DemoStory.hsNonReader), DemoYear.y2025, 'bosy'), DemoBand.nonReader);
    final none = w.story(DemoStory.noImprovement);
    expect(w.band(none, DemoYear.y2025, 'mosy1'), w.band(none, DemoYear.y2025, 'bosy'));
  });

  test('band mix of a Phil-IRI round looks like a real school', () {
    final bands = [
      for (final l in w.learners)
        if ((l.years[DemoYear.y2025]?.grade ?? 0) >= 4) w.band(l, DemoYear.y2025, 'bosy'),
    ];
    double share(Set<DemoBand> b) => bands.where(b.contains).length / bands.length;
    expect(share({DemoBand.independent, DemoBand.instructional}), inInclusiveRange(0.55, 0.75));
    expect(share({DemoBand.nonReader}), inInclusiveRange(0.02, 0.08));
  });

  test('birth dates fit the grade', () {
    for (final l in w.learners) {
      final (year, e) = l.years.entries.map((x) => (x.key, x.value)).first;
      final start = DateTime(int.parse(year.label.substring(0, 4)), 6, 1);
      final born = DateTime.parse(l.birthDate);
      var age = start.year - born.year;
      if (DateTime(start.year, born.month, born.day).isAfter(start)) age--;
      expect(age, inInclusiveRange(e.grade + 5, e.grade + 6), reason: '${l.lrn} ${l.birthDate} G${e.grade}');
    }
  });

  test('names come from the lists', () {
    for (final l in w.learners) {
      expect(demoSurnames, contains(l.last));
      expect(l.sex == 'M' ? demoMaleNames : demoFemaleNames, contains(l.first));
      expect(l.middleInitial, matches(RegExp(r'^[A-Z]\.$')));
    }
  });

  test("advisers who aren't demo tutors never share a demo account's name", () {
    final accountNames = {for (final a in demoAccounts) a.fullName};
    for (final s in w.sections) {
      if (s.adviserAccount == null) {
        expect(accountNames, isNot(contains(s.adviserName)), reason: '${s.year.label} ${s.name}');
      } else {
        expect(s.adviserName, demoAccount(s.adviserAccount!).fullName);
      }
    }
    // One adviser per section name, the same both years.
    final byName = <String, Set<String>>{};
    for (final s in w.sections) {
      (byName[s.name] ??= {}).add(s.adviserName);
    }
    expect(byName.values.every((v) => v.length == 1), isTrue);
    expect(byName.values.map((v) => v.single).toSet(), hasLength(byName.length));
  });

  test('accounts', () {
    expect(demoAccounts.map((a) => a.email).toSet(), hasLength(demoAccounts.length));
    expect(demoAccounts.every((a) => a.email.endsWith('@nightcity.test')), isTrue);
    final superadmin = demoAccounts.singleWhere((a) => a.key == 'demo.super');
    expect((superadmin.role, superadmin.schoolCode), (UserRole.admin, null));
    for (final school in demoSchools) {
      final tutors = demoAccounts.where((a) => a.role == UserRole.tutor && a.schoolCode == school.code);
      expect(tutors, hasLength(3));
      expect(tutors.map((t) => t.tutorType).toSet(), containsAll([TutorType.internal, TutorType.external]));
    }
  });

  group('2026-2027 (plan Task 11)', () {
    test('the two Grade 8 sections have different keys; 2025 keys are unchanged', () {
      final g8 = w.sections.where((s) => s.year == DemoYear.y2026 && s.grade == 8).toList();
      expect(g8.map(demoSectionKey), unorderedEquals(['G8', 'G8N']));
      expect(g8.map(demoSectionIdKey).toSet(), hasLength(2));
      final g3 = w.sections.singleWhere((s) => s.year == DemoYear.y2025 && s.grade == 3);
      expect(demoSectionIdKey(g3), 'section.2025-2026.NCES-DEMO.G3');
    });

    test('gap learners: 3 missed MOSY (G8-10), 2 without GST, 3 HS never read in BOSY; no story learner', () {
      List<int> grades(DemoGap g) => [
            for (final e in w.gapLearners.entries)
              if (e.value == g) w.learners.singleWhere((l) => l.lrn == e.key).years[DemoYear.y2026]!.grade,
          ]..sort();
      expect(grades(DemoGap.missedMosy), [8, 9, 10]);
      expect(grades(DemoGap.noGst), [5, 9]);
      expect(grades(DemoGap.missedBosy), [10, 10, 10]);
      for (final lrn in w.gapLearners.keys) {
        final l = w.learners.singleWhere((x) => x.lrn == lrn);
        expect(l.story, isNull);
        expect(w.band(l, DemoYear.y2026, 'bosy').index, greaterThanOrEqualTo(DemoBand.instructional.index));
      }
      expect(DemoWorld.build().gapLearners, w.gapLearners);
    });
  });
}
