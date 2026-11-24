// The Night City demo world (spec docs/superpowers/specs/2026-11-24-demo-data-design.md):
// who exists, where they are enrolled and how well they read, decided from a
// fixed seed. Pure Dart; the phases (tool/demo_data/phases/) write it through
// the ViewModels.
import 'dart:math';

import 'package:basa_capstone/core/models/user.dart';
import 'package:basa_capstone/core/models/user_role.dart';

import 'names.dart';

enum DemoYear {
  y2025('2025-2026'),
  y2026('2026-2027');

  final String label;
  const DemoYear(this.label);
}

class DemoSchool {
  final String code, name;
  final int firstGrade, lastGrade;
  const DemoSchool(this.code, this.name, this.firstGrade, this.lastGrade);
  bool hasGrade(int g) => g >= firstGrade && g <= lastGrade;
}

/// Region X (Northern Mindanao): the only region with CRLA stories.
const demoRegionId = 13;
const demoDivision = 'Night City Division';
const demoSchools = [
  DemoSchool('NCES-DEMO', 'Night City Elementary School', 1, 6),
  DemoSchool('NCHS-DEMO', 'Night City High School', 7, 10),
];

DemoSchool demoSchoolOfGrade(int grade) => demoSchools.firstWhere((s) => s.hasGrade(grade));

class DemoAccount {
  /// Short name used by the builder, e.g. 'coord.es'.
  final String key;
  final String email, fullName;
  final UserRole role;
  final String? schoolCode;
  final TutorType? tutorType;
  const DemoAccount(this.key, this.email, this.fullName, this.role, this.schoolCode, [this.tutorType]);
}

const _es = 'NCES-DEMO', _hs = 'NCHS-DEMO';
const demoAccounts = [
  DemoAccount('demo.super', 'demo.super@nightcity.test', 'Regional Demo Superadmin', UserRole.admin, null),
  DemoAccount('coord.es', 'coord.es@nightcity.test', 'Liza M. Tabada', UserRole.coordinator, _es),
  DemoAccount('coord.hs', 'coord.hs@nightcity.test', 'Ramil C. Pacana', UserRole.coordinator, _hs),
  DemoAccount('admin.es', 'admin.es@nightcity.test', 'Josefina R. Abellana', UserRole.admin, _es),
  DemoAccount('tutor1.es', 'tutor1.es@nightcity.test', 'Noel D. Gica', UserRole.tutor, _es, TutorType.internal),
  DemoAccount('tutor2.es', 'tutor2.es@nightcity.test', 'Marites L. Cuizon', UserRole.tutor, _es, TutorType.internal),
  DemoAccount('tutor3.es', 'tutor3.es@nightcity.test', 'Edgar P. Sumalinog', UserRole.tutor, _es, TutorType.external),
  DemoAccount('tutor1.hs', 'tutor1.hs@nightcity.test', 'Rowena A. Villarin', UserRole.tutor, _hs, TutorType.internal),
  DemoAccount('tutor2.hs', 'tutor2.hs@nightcity.test', 'Arnel S. Daclan', UserRole.tutor, _hs, TutorType.internal),
  DemoAccount('tutor3.hs', 'tutor3.hs@nightcity.test', 'Cristina B. Lagura', UserRole.tutor, _hs, TutorType.external),
];

DemoAccount demoAccount(String key) => demoAccounts.firstWhere((a) => a.key == key);

class DemoSection {
  final String schoolCode;
  final DemoYear year;
  final int grade;
  final String name;
  final String adviserName;
  /// The adviser's account when the adviser is one of the demo tutors.
  final String? adviserAccount;
  final List<String> tutorAccounts;
  const DemoSection(this.schoolCode, this.year, this.grade, this.name, this.adviserName, this.adviserAccount,
      this.tutorAccounts);
}

enum DemoStory {
  movesUpThroughAral,
  noImprovement,
  hsNonReader,
  exitsToGradeLevel,
  transferredOut,
  droppedOut,
  movedSection,
  returning,
}

enum DemoTrend { improves, stays, slips }

enum DemoLeave { transferredOut, droppedOut, movedSection, returning }

/// Reading level, lowest first (CRLA maps it in records.dart).
enum DemoBand { nonReader, struggling, frustration, instructional, independent }

class DemoEnrollment {
  final int grade;
  final String schoolCode;
  final String sectionName;
  /// 2026-2027 only: how the learner leaves during the year (story 5).
  final DemoLeave? leave;
  const DemoEnrollment(this.grade, this.schoolCode, this.sectionName, {this.leave});
}

class DemoLearner {
  final String lrn, last, first, middleInitial, sex, birthDate;
  final DemoTrend trend;
  final DemoStory? story;
  final Map<DemoYear, DemoEnrollment> years;
  /// The band at BOSY of the learner's first year in the world.
  final DemoBand base;
  const DemoLearner(this.lrn, this.last, this.first, this.middleInitial, this.sex, this.birthDate, this.trend,
      this.story, this.years, this.base);
}

const _sectionNames = {
  1: 'Sampaguita', 2: 'Gumamela', 3: 'Rosal', 4: 'Ilang-Ilang', 5: 'Orchid',
  6: 'Dahlia', 7: 'Molave', 8: 'Acacia', 9: 'Mahogany', 10: 'Yakal',
};
const demoNarraSection = 'Grade 8 - Narra';

String demoSectionName(int grade) => 'Grade $grade - ${_sectionNames[grade]}';

/// Fixed bands per story learner: [year] -> [BOSY, MOSY, EOSY].
const _storyBands = <DemoStory, Map<DemoYear, List<DemoBand>>>{
  DemoStory.movesUpThroughAral: {
    DemoYear.y2025: [DemoBand.struggling, DemoBand.frustration, DemoBand.instructional],
    DemoYear.y2026: [DemoBand.instructional, DemoBand.instructional, DemoBand.independent],
  },
  DemoStory.noImprovement: {
    DemoYear.y2025: [DemoBand.frustration, DemoBand.frustration, DemoBand.frustration],
    DemoYear.y2026: [DemoBand.frustration, DemoBand.frustration, DemoBand.frustration],
  },
  DemoStory.hsNonReader: {
    DemoYear.y2025: [DemoBand.nonReader, DemoBand.nonReader, DemoBand.nonReader],
    DemoYear.y2026: [DemoBand.nonReader, DemoBand.nonReader, DemoBand.struggling],
  },
  DemoStory.exitsToGradeLevel: {
    DemoYear.y2025: [DemoBand.frustration, DemoBand.frustration, DemoBand.instructional],
    DemoYear.y2026: [DemoBand.instructional, DemoBand.instructional, DemoBand.instructional],
  },
};

class DemoWorld {
  final List<DemoSection> sections;
  final List<DemoLearner> learners;
  DemoWorld._(this.sections, this.learners);

  factory DemoWorld.build({int seed = 2026}) {
    final rng = Random(seed);
    var lrnCounter = 0;
    String nextLrn() => '9991${(10000000 + ++lrnCounter).toString().substring(1).padLeft(8, '0')}';
    T pick<T>(List<T> l) => l[rng.nextInt(l.length)];

    // Bands and trends drawn from bags so every section has a realistic mix.
    List<DemoBand> bandBag(int n) {
      final nonReader = max(1, (n * 0.05).round());
      final struggling = (n * 0.10).round();
      final frustration = (n * 0.22).round();
      final independent = (n * 0.25).round();
      final instructional = n - nonReader - struggling - frustration - independent;
      return [
        for (var i = 0; i < nonReader; i++) DemoBand.nonReader,
        for (var i = 0; i < struggling; i++) DemoBand.struggling,
        for (var i = 0; i < frustration; i++) DemoBand.frustration,
        for (var i = 0; i < instructional; i++) DemoBand.instructional,
        for (var i = 0; i < independent; i++) DemoBand.independent,
      ]..shuffle(rng);
    }

    List<DemoTrend> trendBag(int n) {
      final improves = (n * 0.45).round();
      final slips = (n * 0.15).round();
      return [
        for (var i = 0; i < improves; i++) DemoTrend.improves,
        for (var i = 0; i < slips; i++) DemoTrend.slips,
        for (var i = 0; i < n - improves - slips; i++) DemoTrend.stays,
      ]..shuffle(rng);
    }

    String birthDate(DemoYear y, int grade) {
      final start = DateTime(int.parse(y.label.substring(0, 4)), 6, 1);
      final age = grade + 5 + rng.nextInt(2);
      final latest = DateTime(start.year - age, 6, 1);
      final earliest = DateTime(start.year - age - 1, 6, 2);
      final d = earliest.add(Duration(days: rng.nextInt(latest.difference(earliest).inDays + 1)));
      return d.toIso8601String().substring(0, 10);
    }

    // A section's first-year learners (raw: story and leave set below).
    final raw = <({String lrn, String last, String first, String mi, String sex, String born, DemoTrend trend,
        DemoBand base, Map<DemoYear, DemoEnrollment> years})>[];
    void newcomers(DemoYear y, int grade, String sectionName) {
      final n = 36 + rng.nextInt(9);
      final bands = bandBag(n), trends = trendBag(n);
      final school = demoSchoolOfGrade(grade).code;
      for (var i = 0; i < n; i++) {
        final sex = i.isEven ? 'M' : 'F';
        raw.add((
          lrn: nextLrn(),
          last: pick(demoSurnames),
          first: pick(sex == 'M' ? demoMaleNames : demoFemaleNames),
          mi: '${String.fromCharCode(65 + rng.nextInt(26))}.',
          sex: sex,
          born: birthDate(y, grade),
          trend: trends[i],
          base: bands[i],
          years: {y: DemoEnrollment(grade, school, sectionName)},
        ));
      }
    }

    for (var g = 1; g <= 10; g++) {
      newcomers(DemoYear.y2025, g, demoSectionName(g));
    }
    // Moving up: everyone but Grade 6 (ES) and Grade 10 (HS) continues.
    for (final l in raw) {
      final e = l.years[DemoYear.y2025]!;
      if (e.grade == 6 || e.grade == 10) continue;
      l.years[DemoYear.y2026] = DemoEnrollment(e.grade + 1, e.schoolCode, demoSectionName(e.grade + 1));
    }
    newcomers(DemoYear.y2026, 1, demoSectionName(1));
    newcomers(DemoYear.y2026, 7, demoSectionName(7));
    newcomers(DemoYear.y2026, 8, demoNarraSection);

    // Stories: fixed picks in fixed sections (index into that section's 2025 list).
    final stories = <String, DemoStory>{};
    final leaves = <String, DemoLeave>{};
    List<String> lrnsOf(DemoYear y, int grade) => [
          for (final l in raw)
            if (l.years[y]?.grade == grade && l.years[y]!.sectionName == demoSectionName(grade)) l.lrn,
        ];
    stories[lrnsOf(DemoYear.y2025, 3)[0]] = DemoStory.movesUpThroughAral;
    stories[lrnsOf(DemoYear.y2025, 5)[0]] = DemoStory.exitsToGradeLevel;
    stories[lrnsOf(DemoYear.y2025, 8)[1]] = DemoStory.noImprovement;
    final g7 = lrnsOf(DemoYear.y2025, 7);
    stories[g7[2]] = DemoStory.hsNonReader;
    for (final (i, story, leave) in [
      (3, DemoStory.transferredOut, DemoLeave.transferredOut),
      (4, DemoStory.droppedOut, DemoLeave.droppedOut),
      (5, DemoStory.movedSection, DemoLeave.movedSection),
      (6, DemoStory.returning, DemoLeave.returning),
    ]) {
      stories[g7[i]] = story;
      leaves[g7[i]] = leave;
    }

    final learners = [
      for (final l in raw)
        DemoLearner(
          l.lrn,
          l.last,
          l.first,
          l.mi,
          l.sex,
          l.born,
          switch (stories[l.lrn]) {
            DemoStory.movesUpThroughAral || DemoStory.exitsToGradeLevel => DemoTrend.improves,
            DemoStory.noImprovement || DemoStory.hsNonReader => DemoTrend.stays,
            _ => l.trend,
          },
          stories[l.lrn],
          {
            for (final MapEntry(key: y, value: e) in l.years.entries)
              y: y == DemoYear.y2026 && leaves.containsKey(l.lrn)
                  ? DemoEnrollment(e.grade, e.schoolCode, e.sectionName, leave: leaves[l.lrn])
                  : e,
          },
          l.base,
        ),
    ];

    // Sections: who advises and which tutors are assigned.
    // Grades 1, 2, 5, 6, 9, 10 and Narra take the plain advisers in order.
    const plainAdvised = [1, 2, 5, 6, 9, 10];
    String adviserFor(int grade, String name) =>
        demoAdviserNames[name == demoNarraSection ? plainAdvised.length : plainAdvised.indexOf(grade)];
    DemoSection section(DemoYear y, int grade, String name) {
      final es = grade <= 6;
      final school = es ? _es : _hs;
      final String? adviserKey = switch (grade) {
        3 => 'tutor1.es',
        4 => 'tutor2.es',
        7 => 'tutor1.hs',
        8 when name != demoNarraSection => 'tutor2.hs',
        _ => null,
      };
      final tutors = es
          ? (grade <= 3 ? ['tutor1.es'] : ['tutor2.es', 'tutor3.es'])
          : (grade <= 8 ? ['tutor1.hs', 'tutor3.hs'] : ['tutor2.hs']);
      return DemoSection(school, y, grade, name,
          adviserKey == null ? adviserFor(grade, name) : demoAccount(adviserKey).fullName, adviserKey, tutors);
    }

    final sections = [
      for (final y in DemoYear.values)
        for (var g = 1; g <= 10; g++) section(y, g, demoSectionName(g)),
      section(DemoYear.y2026, 8, demoNarraSection),
    ];
    return DemoWorld._(sections, learners);
  }

  List<DemoLearner> inSection(DemoSection s) => [
        for (final l in learners)
          if (l.years[s.year] case final e?)
            if (e.schoolCode == s.schoolCode && e.sectionName == s.name) l,
      ];

  DemoLearner story(DemoStory s) => learners.singleWhere((l) => l.story == s);

  /// The learner's band in [round] of [y]: 'bosy', 'mosy' (CRLA) or 'mosy1'
  /// (Phil-IRI), 'eosy'. A continuing learner starts a year where the last one
  /// ended (their EOSY band).
  DemoBand band(DemoLearner l, DemoYear y, String round) {
    final i = switch (round) {
      'bosy' => 0,
      'mosy' || 'mosy1' => 1,
      'eosy' => 2,
      _ => throw ArgumentError('round "$round"'),
    };
    final fixed = _storyBands[l.story]?[y];
    if (fixed != null) return fixed[i];
    final first = l.years.keys.first;
    final start = y == first ? l.base : band(l, DemoYear.values[y.index - 1], 'eosy');
    final step = switch (l.trend) {
      DemoTrend.improves => [0, 0, 1],
      DemoTrend.stays => [0, 0, 0],
      DemoTrend.slips => [0, -1, -1],
    }[i];
    return DemoBand.values[(start.index + step).clamp(0, DemoBand.values.length - 1)];
  }
}
