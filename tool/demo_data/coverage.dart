// The demo coverage report (spec docs/superpowers/specs/2026-11-24-demo-data-design.md
// section 6, demo-data plan Task 12): each spec row with the counts that
// show it, read back from the devices (tool/demo_data/phases/report.dart),
// OK when every check reaches its minimum, GAP otherwise. Pure Dart; never
// prints a password.

/// One count a coverage line needs: its key in the counts map, what it
/// counts, and the least that shows the feature.
class CoverageCheck {
  final String key, label;
  final int min;
  const CoverageCheck(this.key, this.label, this.min);
}

class CoverageRow {
  final String area, feature, shownBy;
  final List<CoverageCheck> checks;
  /// How the owner sees it when the app can't (decided 2026-11-27).
  final String? note;
  const CoverageRow(this.area, this.feature, this.shownBy, this.checks, {this.note});
}

class CoverageLine {
  final String area, feature, shownBy;
  final List<({String label, int count, int min})> checks;
  final String? note;
  const CoverageLine(this.area, this.feature, this.shownBy, this.checks, {this.note});
  bool get ok => checks.every((c) => c.count >= c.min);
}

/// The spec's section 6 table, in its order (19 rows).
const coverageRows = <CoverageRow>[
  CoverageRow('Accounts', 'Users, tutor types, login logs, offline sign-in', 'the 10 demo accounts; each signs in', [
    CoverageCheck('accounts.users', 'demo accounts on the server', 10),
    CoverageCheck('accounts.tutorTypes', 'tutor types set (internal + external)', 2),
    CoverageCheck('accounts.loginLogs', 'login log rows on the demo devices', 10),
  ], note: 'offline sign-in: tutor1.es, logged on the builder device only (console)'),
  CoverageRow('Admin', 'Schools, sections + advisers, tutor assignments', '2 schools, 21 sections, tutors assigned', [
    CoverageCheck('admin.schools', 'demo schools', 2),
    CoverageCheck('admin.sections', 'sections (both years)', 21),
    CoverageCheck('admin.advisers', 'sections with an adviser', 21),
    CoverageCheck('admin.assignments', 'tutor assignments', 20),
  ]),
  CoverageRow('Admin', 'Learners, roster CSV, SF1 import + trial', 'SF1 files for both years', [
    CoverageCheck('admin.learners', 'learners', 400),
    CoverageCheck('admin.enrollments', 'enrollments (both years)', 700),
    CoverageCheck('admin.sf1Warnings', 'new learners with a blank birth date (gap 5)', 1),
    CoverageCheck('admin.importConflicts', 'open import conflicts (gap 5)', 1),
  ]),
  CoverageRow('Admin', 'Learner history', 'stories 1-5', [
    CoverageCheck('history.storiesBothYears', 'story learners enrolled in both years', 8),
  ]),
  CoverageRow('Leavers', 'Not on SF1, archive, move, restore, anonymize preview', 'story 5 (anonymize: preview only)', [
    CoverageCheck('leavers.archived', 'archived enrollments (transferred out, dropped out)', 2),
    CoverageCheck('leavers.moves', 'section moves', 1),
  ], note: 'restored: Omandam, Miguel (Grade 8 - Acacia)'),
  CoverageRow('CRLA', 'Section list, attempts, Part 1/2, profiles, thresholds, scoresheet export', 'Grades 1-3, both years', [
    CoverageCheck('crla.attempts2025', 'attempts with a profile, 2025-2026', 300),
    CoverageCheck('crla.attempts2026', 'attempts with a profile, 2026-2027', 150),
    CoverageCheck('crla.part1Only', 'attempts with Part 1 only (gap 4)', 1),
    CoverageCheck('crla.digitized', 'attempts marked in BASA (items, words, timer), 2026-2027 MOSY', 10),
  ]),
  CoverageRow('Phil-IRI', 'GST, sessions, miscues on words, answers, rubric, learner results, finalize round, thresholds',
      'Grades 4-10', [
    CoverageCheck('philiri.gst', 'GST scores', 500),
    CoverageCheck('philiri.sessions', 'completed sessions', 1000),
    CoverageCheck('philiri.miscues', 'miscues on words', 10000),
    CoverageCheck('philiri.finalized', 'finalized sessions', 500),
    CoverageCheck('philiri.timed', 'readings timed in BASA', 100),
    CoverageCheck('philiri.inProgress', 'sessions in progress (gap 4 + one-minute)', 2),
  ]),
  CoverageRow('Phil-IRI', 'Content (collections, passages)', 'the seeded passages (no new content)', [
    CoverageCheck('philiri.passages', 'passages', 100),
  ]),
  CoverageRow('Phil-IRI', 'Value sources, ranking list', 'one carried list; ranking per section', [
    CoverageCheck('philiri.carried', 'learners read at BOSY, not yet at MOSY #1 (carried over)', 3),
  ]),
  CoverageRow('ARAL', 'Roster (proposed, enrolled, waiting, placed, exited, referral)', 'both years', [
    CoverageCheck('aral.enrolled', 'roster entries', 300),
    CoverageCheck('aral.waiting', 'waiting for a class', 2),
    CoverageCheck('aral.exited', 'exited', 20),
    CoverageCheck('aral.referrals', 'teacher referrals', 2),
  ]),
  CoverageRow('ARAL', 'Classes, sessions, attendance, idle-class reminder', '6+ classes; one idle class', [
    CoverageCheck('aral.classes', 'classes', 20),
    CoverageCheck('aral.sessions', 'sessions', 1000),
    CoverageCheck('aral.attendance', 'attendance marks', 10000),
    CoverageCheck('aral.idleClasses', 'classes idle 20+ days (2026-2027)', 1),
    CoverageCheck('aral.underMin', 'classes under the minimum (gap 6)', 1),
  ]),
  CoverageRow('ARAL', 'IRIP, check-ins + check-in report', 'placed learners', [
    CoverageCheck('aral.iripWeeks', 'rated IRIP weeks', 1000),
    CoverageCheck('aral.checkins', 'check-ins', 100),
  ]),
  CoverageRow('ARAL', 'Settings (memo keys, KS1 extended, SHARP, cut-off)', 'one memo school', [
    CoverageCheck('aral.settings', 'schools with ARAL settings', 2),
  ]),
  CoverageRow('ARAL', 'Materials, recommendations, readability log', '6+ demo materials', [
    CoverageCheck('aral.materials', 'school materials', 16),
    CoverageCheck('aral.readability', 'readability entries', 100),
  ]),
  CoverageRow('ARAL', 'Implementation report, Forms 1, 2, 4, roster/check-in CSV', 'both schools', [
    CoverageCheck('aral.classesWithSessions', 'classes with sessions', 20),
  ]),
  CoverageRow('Reports',
      'NLA Form 2b + Division ARAL, progress monitoring, BOSY masterlist, SRP (candidates + classes)', 'HS Phil-IRI data', [
    CoverageCheck('reports.hsFinalized', 'HS finalized Phil-IRI sessions', 300),
    CoverageCheck('reports.srpClasses', 'SRP classes', 1),
  ]),
  CoverageRow('Dashboard',
      'Summary per role, years, round calendar, coordinator + tutor reminders, trends (bands, completion, CRLA profiles, ARAL exits, activity)',
      'both years', [
    CoverageCheck('dashboard.calendarRows', 'round calendar rows', 6),
    CoverageCheck('dashboard.overdueBosy', 'learners not read in the closed 2026-2027 BOSY (gap 3)', 3),
    CoverageCheck('dashboard.noGst', 'Phil-IRI learners without a 2026-2027 GST (gap 2)', 2),
    CoverageCheck('dashboard.mosyOpen', 'learners not yet read in the open MOSY #1', 1),
  ]),
  CoverageRow('Sync', 'Pull, upload, approve, pending, reject, auto-approve', 'story 6', [
    CoverageCheck('sync.pending', 'pending uploads', 1),
    CoverageCheck('sync.rejected', 'rejected uploads', 1),
  ], note: "the rejected upload's rows stay on tutor3.hs's builder device (console)"),
  CoverageRow('Settings', 'Report settings, offline days, FLT switch', 'one school each', [
    CoverageCheck('settings.reportSettings', 'schools with report settings', 2),
  ]),
];

/// Every check of every row (the keys the counts map should hold).
List<CoverageCheck> get coverageChecks => [for (final r in coverageRows) ...r.checks];

/// The rows with [counts] filled in (a missing key counts as 0).
List<CoverageLine> coverageLines(Map<String, int> counts) => [
      for (final r in coverageRows)
        CoverageLine(r.area, r.feature, r.shownBy,
            [for (final c in r.checks) (label: c.label, count: counts[c.key] ?? 0, min: c.min)],
            note: r.note),
    ];

/// Who entered a school's records of one round (spec: who administered what,
/// owner 2026-11-26, objective ii).
class AdministeredRow {
  final String school, year, instrument, round;
  /// [both]: the section's tutor who is also the learner's ARAL class tutor.
  final int sectionTutors, classTutors, both, coordinators, other;
  const AdministeredRow(this.school, this.year, this.instrument, this.round,
      {required this.sectionTutors, required this.classTutors, this.both = 0, required this.coordinators, this.other = 0});
}

/// The report as Markdown. [accounts]: key -> {email, password, ...}; only
/// the key and email are printed. [sections]: extra titled lists (the gap
/// learners, the one-minute learners).
String coverageReport(
  List<CoverageLine> lines, {
  required String server,
  required DateTime today,
  Map<String, Map<String, dynamic>> accounts = const {},
  Map<String, int> mismatches = const {},
  List<AdministeredRow> administered = const [],
  Map<String, List<String>> sections = const {},
}) {
  final b = StringBuffer();
  final ok = lines.where((l) => l.ok).length;
  final day = today.toIso8601String().substring(0, 10);
  b
    ..writeln('# Night City demo: coverage report')
    ..writeln()
    ..writeln('Server: $server  ')
    ..writeln('Read on: $day  ')
    ..writeln('Result: $ok of ${lines.length} lines OK${ok == lines.length ? '' : ', ${lines.length - ok} gap(s)'}')
    ..writeln()
    ..writeln('| Area | Feature | Shown by | Counts | Result |')
    ..writeln('|---|---|---|---|---|');
  for (final l in lines) {
    final counts = [
      for (final c in l.checks) '${c.label}: ${c.count}${c.count < c.min ? ' (needs ${c.min})' : ''}',
    ].join('; ');
    b.writeln('| ${l.area} | ${l.feature} | ${l.shownBy}${l.note == null ? '' : ' (${l.note})'} | $counts | '
        '${l.ok ? 'OK' : 'GAP'} |');
  }
  if (mismatches.isNotEmpty) {
    b
      ..writeln()
      ..writeln('## Profile mismatches (planned vs scored by BASA)')
      ..writeln();
    for (final e in mismatches.entries) {
      b.writeln('- ${e.key}: ${e.value}');
    }
  }
  if (administered.isNotEmpty) {
    b
      ..writeln()
      ..writeln('## Who administered what')
      ..writeln()
      ..writeln("Section tutor = a tutor assigned to the learner's section; ARAL class tutor = the learner's class "
          "tutor that year, from outside the section; both = the section's tutor who also teaches the learner's class.")
      ..writeln()
      ..writeln('| School | Year | Instrument | Round | Section tutors | ARAL class tutors | Both | Coordinators | Other |')
      ..writeln('|---|---|---|---|---|---|---|---|---|');
    for (final r in administered) {
      b.writeln('| ${r.school} | ${r.year} | ${r.instrument} | ${r.round} | ${r.sectionTutors} | ${r.classTutors} | '
          '${r.both} | ${r.coordinators} | ${r.other} |');
    }
  }
  for (final e in sections.entries) {
    b
      ..writeln()
      ..writeln('## ${e.key}')
      ..writeln();
    for (final line in e.value) {
      b.writeln('- $line');
    }
  }
  if (accounts.isNotEmpty) {
    b
      ..writeln()
      ..writeln(r'## Accounts (passwords: D:\0_CAPSTONE\verify\demo\accounts.json, never printed)')
      ..writeln();
    for (final e in accounts.entries) {
      b.writeln('- ${e.key}: ${e.value['email']}');
    }
  }
  return b.toString();
}
