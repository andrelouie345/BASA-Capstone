// Setup phase (demo-data plan Task 6): the demo superadmin, both schools, the
// coordinators, school admin and tutors, the round calendar of both years and
// the schools' settings. Every write goes through a ViewModel; a second run
// finds what the first made (schools by code, accounts by email; settings and
// windows are set to the same values again).
import 'dart:io';

import 'package:basa_capstone/core/models/assessment_calendar.dart';
import 'package:basa_capstone/core/models/report_setting.dart';
import 'package:basa_capstone/core/services/aral_rule_settings.dart';

import '../dates.dart';
import '../session.dart';
import '../state.dart';
import '../world.dart';

const _es = 'NCES-DEMO', _hs = 'NCHS-DEMO';

/// The setup steps, in order.
final setupSteps = <({String name, Future<void> Function(DemoSession s, DemoState st) run})>[
  (name: 'setup.super', run: (s, st) => _ensureAccount(s, demoBootstrapKey, demoAccount('demo.super'), null)),
  (name: 'setup.schools', run: _schools),
  (name: 'setup.staff', run: _staff),
  (name: 'setup.calendar', run: _calendar),
  (name: 'setup.settings', run: _settings),
];

int schoolIdOf(DemoState st, String code) {
  final id = st.ids['school.$code'];
  if (id == null) throw StateError('school $code has no id yet (run setup.schools first)');
  return id;
}

Future<void> _schools(DemoSession s, DemoState st) async {
  final vm = (await s.as('demo.super')).shared.schoolVm;
  for (final school in demoSchools) {
    final r = await vm.create(
        schoolCode: school.code, schoolName: school.name, regionId: demoRegionId, division: demoDivision);
    stdout.writeln('  ${school.code}: ${r.created ? 'created' : 'already there'} (id ${r.school.id})');
    await st.putId('school.${school.code}', r.school.id!);
  }
}

Future<void> _staff(DemoSession s, DemoState st) async {
  for (final key in ['coord.es', 'coord.hs', 'admin.es']) {
    final a = demoAccount(key);
    await _ensureAccount(s, 'demo.super', a, schoolIdOf(st, a.schoolCode!));
  }
  for (final a in demoAccounts.where((a) => a.tutorType != null)) {
    final coordinator = a.schoolCode == _es ? 'coord.es' : 'coord.hs';
    await _ensureAccount(s, coordinator, a, schoolIdOf(st, a.schoolCode!));
    final users = (await s.as(coordinator)).admin!.userVm;
    final user = (await users.findByEmail(a.email))!;
    if (user.tutorType != a.tutorType) await users.setTutorType(user.id, a.tutorType);
  }
  // Each account signs in once (replacing its temporary password).
  for (final a in demoAccounts) {
    await s.as(a.key);
  }
}

/// Creates [a] as [creator] unless the server has it; its temporary password
/// is kept until its first sign-in replaces it.
Future<void> _ensureAccount(DemoSession s, String creator, DemoAccount a, int? schoolId) async {
  final users = (await s.as(creator)).admin!.userVm;
  final existing = await users.findByEmail(a.email);
  if (existing != null) {
    if (!s.hasPassword(a.key)) {
      throw StateError('${a.email} exists on the server but its password is not in ${s.dir.path}\\accounts.json; '
          'reset it there by hand, or delete the account');
    }
    stdout.writeln('  ${a.email}: already there');
  } else {
    final temp = await users.create(email: a.email, fullName: a.fullName, role: a.role, schoolId: schoolId);
    if (temp == null) throw StateError('creating ${a.email} returned no temporary password');
    await s.rememberTemporary(a.key, a.email, temp);
    stdout.writeln('  ${a.email}: created');
  }
  await s.as(a.key); // first sign-in replaces the temporary password
}

/// The windows of both years as school overrides: CRLA at the ES only
/// (Grades 1-3), Phil-IRI at both; Phil-IRI MOSY #2 and #3 not held.
Future<void> _calendar(DemoSession s, DemoState st) async {
  final vm = (await s.as('demo.super')).tutor.calendarVm;
  for (final school in demoSchools) {
    final id = schoolIdOf(st, school.code);
    for (final y in DemoYear.values) {
      for (final w in demoWindows(y)) {
        final instrument = CalendarInstrument.parse(w.instrument);
        if (instrument == CalendarInstrument.crla && school.code != _es) continue;
        await vm.setWindow(id, y.label, instrument, w.round, w.opens, w.closes);
      }
      for (final round in ['mosy2', 'mosy3']) {
        await vm.skipRound(id, y.label, CalendarInstrument.philIri, round);
      }
    }
    stdout.writeln('  ${school.code}: calendar set for ${DemoYear.values.map((y) => y.label).join(', ')}');
  }
}

/// ES: auto-approve on, the ARAL memo keys + KS1 extended, the ARAL list on
/// carried values. HS: auto-approve off (uploads wait for the coordinator),
/// the FLT switch and SHARP on. Both: offline days, ARAL classes of 5 to 10,
/// check-in cut-off, idle days.
Future<void> _settings(DemoSession s, DemoState st) async {
  for (final (coordinator, code) in [('coord.es', _es), ('coord.hs', _hs)]) {
    final vms = (await s.as(coordinator)).tutor;
    final id = schoolIdOf(st, code);
    final report = vms.reportSettingsVm, aral = vms.aralCheckinVm;
    final es = code == _es;
    await report.setDoneThreshold(id, es ? 0.85 : 0.8);
    await report.setAutoApprove(id, es);
    await report.setOfflineDays(id, 14);
    if (es) {
      await report.setValueSource(id, PhilIriValueList.aral, PhilIriValues.carried);
      await aral.setRuleSetting(id, AralRuleSettings.sessionMaxMinutesKey, 60);
      await aral.setRuleSetting(id, AralRuleSettings.sessionsWeekdaysOnlyKey, true);
      await aral.setRuleSetting(id, AralRuleSettings.basisRoundKey, 'bosy');
      await aral.setKs1Extended(id, true);
    } else {
      await report.setFltCounts(id, true);
      await aral.setFoundationalProgram(id, true);
    }
    // ARAL classes of 5 to 10 learners (Division Memorandum 180 s. 2026;
    // owner 2026-11-26: both demo schools). The minimum is a coordinator
    // notice only, never a refusal. Maximum first: a minimum above the
    // maximum is refused.
    await aral.setRuleSetting(id, AralRuleSettings.classMaxLearnersKey, 10);
    await aral.setRuleSetting(id, AralRuleSettings.classMinLearnersKey, 5);
    await aral.setPassPct(id, 75);
    await aral.setIdleSessionDays(id, 14);
    stdout.writeln('  $code: settings set');
  }
}
