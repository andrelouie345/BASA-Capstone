// The coverage report and walkthrough (demo-data plan Task 12): reads the
// counts back from the coordinators' pulled device copies (what the app
// shows; ledger ruling 2026-11-27) and the sync review ViewModel, then
// writes <dir>/report.md and <dir>/walkthrough.md. Written on every run
// (not a resumable step): `--only report` writes them again.
import 'dart:convert';
import 'dart:io';

import '../coverage.dart';
import '../session.dart';
import '../state.dart';
import '../world.dart';
import 'leftovers.dart';
import 'setup.dart';

const reportStep = 'report';

const _schools = ['NCES-DEMO', 'NCHS-DEMO'];
String _coord(String school) => school == 'NCES-DEMO' ? 'coord.es' : 'coord.hs';

Future<int> _n(dynamic db, String sql, [List<Object?> args = const []]) async =>
    ((await db.rawQuery(sql, args) as List).first as Map).values.first as int? ?? 0;

/// The counts [coverageRows] check, read back from the devices.
Future<Map<String, int>> readCounts(DemoSession s, DemoState st, DemoWorld w, DateTime today) async {
  final c = <String, int>{};
  void add(String key, int n) => c[key] = (c[key] ?? 0) + n;
  void most(String key, int n) => c[key] = (c[key] ?? 0) > n ? c[key]! : n;
  final storyLrns = [for (final l in w.learners) if (l.story != null) l.lrn];
  final idleBefore = DateTime(today.year, today.month, today.day - 20).toIso8601String().substring(0, 10);
  const y26 = '2026-2027';

  for (final school in _schools) {
    final dev = await s.as(_coord(school));
    await dev.shared.syncVm.pull();
    final db = dev.ctx.localDb;
    add('admin.schools', await _n(db, 'SELECT count(*) FROM schools'));
    add('admin.sections', await _n(db, 'SELECT count(*) FROM sections'));
    add('admin.advisers', await _n(db, "SELECT count(*) FROM sections WHERE coalesce(adviser_name, '') <> ''"));
    add('admin.assignments', await _n(db, 'SELECT count(*) FROM tutor_section_assignments'));
    add('admin.learners', await _n(db, 'SELECT count(*) FROM students'));
    add('admin.enrollments', await _n(db, 'SELECT count(*) FROM enrollments'));
    add('admin.sf1Warnings', await _n(db, "SELECT count(*) FROM students WHERE coalesce(birth_date, '') = ''"));
    final admin = dev.admin!;
    await admin.importVm.loadPendingConflicts();
    add('admin.importConflicts', admin.importVm.pendingConflicts.length);
    add('history.storiesBothYears', await _n(db, '''
        SELECT count(*) FROM (SELECT s.lrn FROM students s JOIN enrollments e ON e.student_id = s.id
         WHERE s.lrn IN (${List.filled(storyLrns.length, '?').join(',')})
         GROUP BY s.lrn HAVING count(DISTINCT e.school_year) >= 2)''', storyLrns));
    add('leavers.archived', await _n(db, "SELECT count(*) FROM enrollments WHERE status IN ('transferred_out', 'dropped_out')"));
    add('leavers.moves', await _n(db, 'SELECT count(*) FROM enrollment_moves'));
    add('crla.attempts2025', await _n(db, "SELECT count(*) FROM crla_assessments WHERE school_year = '2025-2026' AND reading_profile IS NOT NULL"));
    add('crla.attempts2026', await _n(db, "SELECT count(*) FROM crla_assessments WHERE school_year = '$y26' AND reading_profile IS NOT NULL"));
    add('crla.part1Only', await _n(db, '''
        SELECT count(*) FROM crla_assessments a
         WHERE (EXISTS (SELECT 1 FROM crla_part1_standard p WHERE p.assessment_id = a.id)
             OR EXISTS (SELECT 1 FROM crla_part1_english p WHERE p.assessment_id = a.id))
           AND NOT EXISTS (SELECT 1 FROM crla_part2_fluency f WHERE f.assessment_id = a.id)'''));
    add('philiri.gst', await _n(db, 'SELECT count(*) FROM phil_iri_gst_results'));
    add('philiri.sessions', await _n(db, "SELECT count(*) FROM phil_iri_assessments WHERE status <> 'in_progress'"));
    add('philiri.miscues', await _n(db, 'SELECT count(*) FROM phil_iri_miscues'));
    add('philiri.finalized', await _n(db, 'SELECT count(*) FROM phil_iri_assessments WHERE finalized_at IS NOT NULL'));
    add('philiri.timed', await _n(db, 'SELECT count(DISTINCT reading_id) FROM phil_iri_reading_timer_events'));
    add('philiri.inProgress', await _n(db, "SELECT count(*) FROM phil_iri_assessments WHERE status = 'in_progress'"));
    most('philiri.passages', await _n(db, 'SELECT count(*) FROM phil_iri_passages'));
    // Active 2026-2027 Phil-IRI learners (Grades 4-10) and their rounds.
    const phil = '''
        FROM enrollments e JOIN sections sec ON sec.id = e.section_id
        WHERE e.school_year = '2026-2027' AND e.status = 'active' AND CAST(sec.grade_level AS INTEGER) >= 4''';
    String has(String round) => "EXISTS (SELECT 1 FROM phil_iri_assessments a WHERE a.student_id = e.student_id "
        "AND a.school_year = '$y26' AND a.round = '$round' AND a.status <> 'in_progress')";
    add('philiri.carried', await _n(db, 'SELECT count(*) $phil AND ${has('bosy')} AND NOT ${has('mosy1')}'));
    add('dashboard.overdueBosy', await _n(db, 'SELECT count(*) $phil AND NOT ${has('bosy')}'));
    add('dashboard.mosyOpen', await _n(db, 'SELECT count(*) $phil AND NOT ${has('mosy1')}'));
    add('dashboard.noGst', await _n(db, "SELECT count(*) $phil AND NOT EXISTS (SELECT 1 FROM phil_iri_gst_results g "
        "WHERE g.student_id = e.student_id AND g.school_year = '$y26')"));
    most('dashboard.calendarRows', await _n(db, 'SELECT count(*) FROM assessment_calendar'));
    add('aral.enrolled', await _n(db, 'SELECT count(*) FROM aral_enrollments'));
    add('aral.waiting', await _n(db, "SELECT count(*) FROM aral_enrollments WHERE status = 'active' AND class_id IS NULL"));
    add('aral.exited', await _n(db, "SELECT count(*) FROM aral_enrollments WHERE status = 'exited'"));
    add('aral.referrals', await _n(db, "SELECT count(*) FROM aral_enrollments WHERE basis_source = 'referral'"));
    add('aral.classes', await _n(db, 'SELECT count(*) FROM aral_classes'));
    add('aral.sessions', await _n(db, 'SELECT count(*) FROM aral_sessions'));
    add('aral.attendance', await _n(db, 'SELECT count(*) FROM aral_attendance'));
    add('aral.idleClasses', await _n(db, '''
        SELECT count(*) FROM (SELECT class_id FROM aral_sessions WHERE school_year = '$y26'
         GROUP BY class_id HAVING max(held_on) < ?)''', [idleBefore]));
    add('aral.underMin', await _n(db, '''
        SELECT count(*) FROM (SELECT class_id FROM aral_enrollments WHERE school_year = '$y26' AND status = 'active'
         AND class_id IS NOT NULL GROUP BY class_id HAVING count(*) < 5)'''));
    add('aral.iripWeeks', await _n(db, 'SELECT count(*) FROM aral_irip_weeks WHERE status IS NOT NULL'));
    add('aral.checkins', await _n(db, 'SELECT count(*) FROM aral_checkins'));
    add('aral.settings', await _n(db, 'SELECT count(*) FROM aral_settings WHERE school_id IS NOT NULL'));
    add('aral.materials', await _n(db, 'SELECT count(*) FROM aral_materials WHERE school_id IS NOT NULL'));
    add('aral.readability', await _n(db, 'SELECT count(*) FROM aral_readability_logs'));
    add('aral.classesWithSessions', await _n(db, 'SELECT count(DISTINCT class_id) FROM aral_sessions'));
    if (school == 'NCHS-DEMO') {
      add('reports.hsFinalized', await _n(db, 'SELECT count(*) FROM phil_iri_assessments WHERE finalized_at IS NOT NULL'));
      add('reports.srpClasses', await _n(db, 'SELECT count(*) FROM srp_classes'));
    }
    add('settings.reportSettings', await _n(db, 'SELECT count(*) FROM report_settings WHERE school_id IS NOT NULL'));
    add('accounts.tutorTypes', 0);
    most('accounts.tutorTypes', await _n(db, "SELECT count(DISTINCT tutor_type) FROM users WHERE role = 'tutor'"));

    final review = admin.syncReviewVm;
    add('sync.pending', (await review.pending(schoolId: schoolIdOf(st, school))).pending.length);
  }
  final rejected = st.ids['leftover.rejectedUpload'];
  if (rejected != null) {
    final details = await (await s.as('coord.hs')).admin!.syncReviewVm.details(rejected);
    add('sync.rejected', details.item.upload.status == 'rejected' ? 1 : 0);
  }

  final superAdmin = (await s.as('demo.super')).admin!;
  for (final a in demoAccounts) {
    if (await superAdmin.userVm.findByEmail(a.email) != null) add('accounts.users', 1);
  }
  for (final a in demoAccounts) {
    add('accounts.loginLogs', await _n((await s.as(a.key)).ctx.localDb, 'SELECT count(*) FROM login_logs'));
  }
  return c;
}

/// Who entered each school's CRLA, Phil-IRI and GST records, per year and
/// round: a coordinator or admin, a tutor of the record's section, the
/// learner's ARAL class tutor that year from outside the section, a tutor who
/// is both, or someone else.
Future<List<AdministeredRow>> readAdministered(DemoSession s) async {
  final rows = <AdministeredRow>[];
  for (final school in _schools) {
    final db = (await s.as(_coord(school))).ctx.localDb;
    for (final (instrument, table, round) in [
      ('CRLA', 'crla_assessments', 'r.round'),
      ('Phil-IRI', 'phil_iri_assessments', 'r.round'),
      ('GST', 'phil_iri_gst_results', "'bosy'"),
    ]) {
      // The learner's ARAL class tutor that year entered it.
      const classTutor = '''EXISTS (SELECT 1 FROM aral_enrollments ae JOIN aral_classes c ON c.id = ae.class_id
          WHERE ae.student_id = r.student_id AND ae.school_year = r.school_year AND c.tutor_id = r.administered_by)''';
      final got = await db.rawQuery('''
          SELECT r.school_year AS year, $round AS round,
                 sum(CASE WHEN u.role IN ('coordinator', 'admin') THEN 1 ELSE 0 END) AS coord,
                 sum(CASE WHEN u.role = 'tutor' AND t.id IS NOT NULL AND NOT $classTutor THEN 1 ELSE 0 END) AS section_tutor,
                 sum(CASE WHEN u.role = 'tutor' AND t.id IS NULL AND $classTutor THEN 1 ELSE 0 END) AS class_tutor,
                 sum(CASE WHEN u.role = 'tutor' AND t.id IS NOT NULL AND $classTutor THEN 1 ELSE 0 END) AS both_tutor,
                 sum(CASE WHEN u.id IS NULL OR (u.role = 'tutor' AND t.id IS NULL AND NOT $classTutor) THEN 1 ELSE 0 END) AS other
            FROM $table r
            LEFT JOIN users u ON u.id = r.administered_by
            LEFT JOIN tutor_section_assignments t ON t.tutor_id = r.administered_by AND t.section_id = r.section_id
           GROUP BY 1, 2 ORDER BY 1, 2''');
      for (final g in got) {
        rows.add(AdministeredRow(school, g['year'] as String, instrument, g['round'] as String,
            sectionTutors: g['section_tutor'] as int? ?? 0,
            classTutors: g['class_tutor'] as int? ?? 0,
            both: g['both_tutor'] as int? ?? 0,
            coordinators: g['coord'] as int? ?? 0,
            other: g['other'] as int? ?? 0));
      }
    }
  }
  return rows;
}

/// Writes report.md and walkthrough.md into the builder folder.
Future<void> writeReport(DemoSession s, DemoState st, DemoWorld w, DateTime today, {required String server}) async {
  final counts = await readCounts(s, st, w, today);
  final administered = await readAdministered(s);
  // Student id -> name, one coordinator device at a time (only one is open).
  final names = <int, String>{};
  for (final school in _schools) {
    final repo = (await s.as(_coord(school))).shared.studentRepo;
    for (final l in w.learners) {
      final id = (await repo.findByLrn(l.lrn))?.id;
      if (id != null) names[id] = '${l.last}, ${l.first} (LRN ${l.lrn})';
    }
  }
  Future<String> nameOf(int? studentId) async =>
      studentId == null ? '(not made)' : names[studentId] ?? 'student $studentId';

  String learner(DemoLearner l) {
    final e = l.years[DemoYear.y2026];
    return '${l.last}, ${l.first} (LRN ${l.lrn}${e == null ? '' : ', ${e.sectionName}'})';
  }

  final gaps = <String>[
    for (final e in w.gapLearners.entries)
      '${switch (e.value) { DemoGap.missedMosy => 'Gap 1, missed MOSY #1 (carried over / not assessed)', DemoGap.noGst => 'Gap 2, no GST (tutor reminder)', DemoGap.missedBosy => 'Gap 3, never read in the closed BOSY (overdue)' }}: '
          '${learner(w.learners.singleWhere((l) => l.lrn == e.key))}',
    'Gap 4, Phil-IRI session in progress: ${await nameOf(st.ids['leftover.philiri-in-progress'])}',
    'Gap 4, CRLA Part 1 only: ${await nameOf(st.ids['leftover.crla-part1'])}',
    'Gap 5, blank birth date: Dela Cruz, Andrea (LRN $demoBlankBirthLrn, Grade 7 - Molave); an import conflict waits for coord.hs',
    'Gap 6, ARAL class under the minimum: the HS class of 4 (coordinator notice)',
  ];
  final oneMinute = [
    for (final e in st.ids.entries.where((e) => e.key.startsWith('one-minute.')))
      '${e.key.substring('one-minute.'.length)}: ${await nameOf(e.value)}',
  ];
  final stories = [
    for (final l in w.learners.where((l) => l.story != null)) '${l.story!.name}: ${learner(l)}',
  ];
  final accounts = (jsonDecode(File('${s.dir.path}${Platform.pathSeparator}accounts.json').readAsStringSync())
          as Map<String, dynamic>)
      .cast<String, Map<String, dynamic>>();
  final report = coverageReport(
    coverageLines(counts),
    server: server,
    today: today,
    accounts: accounts,
    mismatches: {for (final e in st.ids.entries) if (RegExp(r'^mismatch\.(crla|philiri)\.').hasMatch(e.key)) e.key: e.value},
    administered: administered,
    sections: {
      'Deliberate gaps (2026-2027)': gaps,
      'Ready for a live one-minute reading (MOSY #1, session in progress, no timer tap)': oneMinute,
      'Story learners': stories,
      'Sync story': [
        'Pending: upload ${st.ids['leftover.pendingUpload']} by tutor2.hs (IRIP ratings), waiting for coord.hs',
        'Rejected: upload ${st.ids['leftover.rejectedUpload']} by tutor3.hs ("$demoRejectReason"); its rows stay on '
            "tutor3.hs's builder device",
      ],
    },
  );
  File('${s.dir.path}${Platform.pathSeparator}report.md').writeAsStringSync(report);
  File('${s.dir.path}${Platform.pathSeparator}walkthrough.md').writeAsStringSync(demoWalkthrough(
      stories: stories, gaps: gaps, oneMinute: oneMinute, sectionIds: {
    for (final e in st.ids.entries) if (e.key.startsWith('section.2026-2027.')) e.key.substring('section.2026-2027.'.length): e.value,
  }, schoolIds: {for (final sc in _schools) sc: schoolIdOf(st, sc)}));
  final lines = coverageLines(counts);
  stdout.writeln('  report.md: ${lines.where((l) => l.ok).length} of ${lines.length} lines OK'
      '${lines.any((l) => !l.ok) ? '; GAP: ${[for (final l in lines) if (!l.ok) '${l.area} (${l.feature})'].join('; ')}' : ''}');
}

/// The owner's click-through (plan Task 13): per area, which account and
/// what to open; console commands work today, screens as the frontend team
/// builds them.
String demoWalkthrough({
  required List<String> stories,
  required List<String> gaps,
  required List<String> oneMinute,
  required Map<String, int> sectionIds,
  required Map<String, int> schoolIds,
}) {
  final es = schoolIds['NCES-DEMO'], hs = schoolIds['NCHS-DEMO'];
  final b = StringBuffer()
    ..writeln('# Night City demo: walkthrough')
    ..writeln()
    ..writeln(r'Passwords: D:\0_CAPSTONE\verify\demo\accounts.json. Admin app / admin console '
        '(`dart run lib/console/main.dart`) for demo.super, coord.es, coord.hs, admin.es; tutor app / tutor console '
        '(`dart run lib/console/main_tutor.dart`) for the tutors. Sign in, then download (pull-cloud yes). Tick each line.')
    ..writeln()
    ..writeln('School ids: NCES-DEMO $es, NCHS-DEMO $hs. 2026-2027 section ids: '
        '${[for (final e in sectionIds.entries) '${e.key} ${e.value}'].join(', ')}.')
    ..writeln()
    ..writeln('| # | Area | Account | Open (screen, or console) | Expect |')
    ..writeln('|---|---|---|---|---|');
  var i = 0;
  void row(String area, String account, String open, String expect) =>
      b.writeln('| ${++i} | $area | $account | $open | $expect |');
  row('Accounts', 'demo.super', 'Users (`user-list`), login logs (`login-recent`)', '10 Night City accounts, tutor types, sign-ins');
  row('Admin', 'coord.hs', 'Sections (`list-sections`), assignments', 'HS sections of both years with advisers and tutors');
  row('Admin', 'coord.hs', 'Import conflicts (`list-conflicts`)', 'one open conflict: LRN of a Grade 9 learner as Ramos, Kevin');
  row('Admin', 'coord.hs', 'Learner history (`learner-history-lrn <LRN>`)', 'story learners: both years');
  row('Leavers', 'coord.hs', 'SF1 leavers (`sf1-missing`, history of the four Grade 8 learners)', 'transferred out, dropped out, moved to Narra, restored');
  row('CRLA', 'tutor1.es', 'CRLA, Grade 2 (`crla-results ...`)', 'BOSY + MOSY profiles; one MOSY attempt with Part 1 only');
  row('Phil-IRI', 'tutor2.hs', 'Phil-IRI Grade 9 MOSY #1 (`phil-iri-sessions ${sectionIds['NCHS-DEMO.G9']} 2026-2027 mosy1`)', 'timed readings (`phil-iri-timer <readingId>`)');
  row('Phil-IRI', 'a one-minute learner\'s tutor', 'the session in progress', 'time it live: start, stops at 60 s, tap the word reached, complete');
  row('Phil-IRI', 'coord.hs', 'Value sources / ranking (`phil-iri-rank`)', 'carried vs actual for the MOSY gap learners');
  row('ARAL', 'coord.es', 'ARAL roster and classes (`aral-roster`, `aral-classes`)', 'enrolled, placed, 2 waiting, exits (2025)');
  row('ARAL', 'tutor2.hs', 'My classes, sessions (`reminders-tutor me 2026-2027`)', 'the idle class reminder');
  row('ARAL', 'coord.hs', 'Coordinator notices (`reminders-coordinator $hs 2026-2027`)', 'a class under the minimum; overdue BOSY; MOSY open');
  row('ARAL', 'tutor1.hs', 'IRIP, check-ins, readability', 'weekly ratings, check-ins 16/32, readability entries');
  row('ARAL', 'coord.hs', 'Forms 1, 2, 4, implementation report (`aral-form2 ...`)', 'both years');
  row('Reports', 'coord.hs', 'NLA Form 2b, progress, BOSY masterlist, SRP (`srp-classes $hs 2025-2026`)', '14 SRP classes with room, schedule, tutor');
  row('Dashboard', 'coord.hs / tutor2.hs', 'Dashboard (`dashboard 2026-2027`), trends', 'both years; reminders as above');
  row('Sync', 'coord.hs', 'Uploads to review (`sync-pending`)', "tutor2.hs's pending upload; the rejected one with its reason");
  row('Sync', 'tutor3.hs (builder device, console only)', '`sync-status`', 'rejected: "$demoRejectReason"');
  row('Settings', 'coord.es', 'Report settings (`report-settings-show`)', 'done threshold, offline days, FLT switch');
  b
    ..writeln()
    ..writeln('## Story learners')
    ..writeln();
  for (final l in stories) {
    b.writeln('- $l');
  }
  b
    ..writeln()
    ..writeln('## Deliberate gaps')
    ..writeln();
  for (final g in gaps) {
    b.writeln('- $g');
  }
  b
    ..writeln()
    ..writeln('## One-minute readings to time live')
    ..writeln();
  for (final o in oneMinute) {
    b.writeln('- $o');
  }
  return b.toString();
}
