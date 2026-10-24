// lib/core/console/commands/dashboard_commands.dart

/// Dashboard summary (D6) of the signed-in user, from this device's copy.
/// `today=` lets a test look at any day.
library;

import '../console_command.dart';
import '../console_registry.dart';
import '../../../viewmodels/dashboard_viewmodel.dart';
import '../../../viewmodels/nla_report_viewmodel.dart' show progressPercent;
import '../../models/assessment_calendar.dart';
import '../../models/report_setting.dart';
import '../date_args.dart';
import 'reminder_commands.dart' show coordinatorRemindersText, tutorRemindersText;

class _Usage implements Exception {
  final String message;
  const _Usage(this.message);
}

const _usage = 'Usage: dashboard <year> [today=YYYY-MM-DD]';

DateTime? _today(List<String> opts) {
  DateTime? today;
  for (final o in opts) {
    final eq = o.indexOf('=');
    if (eq < 0 || o.substring(0, eq) != 'today') throw _Usage('Unknown option "$o". $_usage');
    final raw = o.substring(eq + 1).trim();
    final d = strictDateArg(raw);
    if (d == null) throw _Usage('today must be a real YYYY-MM-DD date (got "$raw")');
    today = d;
  }
  return today;
}

String _count(SectionLearnerCount c) =>
    '${c.sections} section${c.sections == 1 ? '' : 's'}, ${c.learners} learner${c.learners == 1 ? '' : 's'}';

String _aral(AralRosterCount a) {
  final reasons = [
    for (final e in a.exitedBy.entries)
      if (e.value > 0) '${e.key.value} ${e.value}',
  ];
  return 'ARAL roster: ${a.active} active, ${a.exited} exited${reasons.isEmpty ? '' : ' (${reasons.join(', ')})'}';
}

void _counts(StringBuffer out, String indent, Map<CalendarInstrument, SectionLearnerCount> counts,
    SectionLearnerCount other) {
  for (final i in CalendarInstrument.values) {
    out.write('\n$indent${i.label} (${i == CalendarInstrument.crla ? 'Grade 1-3' : 'Grade 4-10'}): ${_count(counts[i]!)}');
  }
  if (other.sections > 0) out.write('\n${indent}Other grades: ${_count(other)}');
}

void _reportsLines(StringBuffer out, String indent, int listed, int notAssessed, int candidates, int recommended,
    int classes, int classLearners) {
  out.write('\n${indent}BOSY masterlist: $listed learner${listed == 1 ? '' : 's'} not grade level ready '
      '($notAssessed not assessed)');
  out.write('\n${indent}SRP: $candidates candidate${candidates == 1 ? '' : 's'} ($recommended recommended), '
      '$classes class${classes == 1 ? '' : 'es'} with $classLearners learner${classLearners == 1 ? '' : 's'}');
}

String _round(RoundSnapshot r, double threshold, String tag) {
  final pct = r.share == null ? '' : ' (${progressPercent(r.share)}%)';
  return '[$tag] ${r.roundName} ${r.window.opensOn} .. ${r.window.closesOn}: ${r.assessed}/${r.enrolled}$pct, '
      '${r.sectionsDone}/${r.sectionCount} section${r.sectionCount == 1 ? '' : 's'} done at ${thresholdPercent(threshold)}';
}

void _school(StringBuffer out, SchoolSummary s, {required bool reminders}) {
  out.write('School ${s.school.schoolName} (#${s.school.id})');
  _counts(out, '  ', s.counts, s.otherGrades);
  out.write('\n  Rounds:');
  if (s.current.isEmpty && s.next.isEmpty) out.write('\n    No scheduled rounds this year.');
  for (final r in s.current) {
    out.write('\n    ${_round(r, s.doneThreshold, r.status.label)}');
  }
  for (final r in s.next) {
    out.write('\n    ${_round(r, s.doneThreshold, 'NEXT')}');
  }
  out.write('\n  ${_aral(s.aral)}');
  _reportsLines(out, '  ', s.masterlistLearners, s.masterlistNotAssessed, s.srpCandidates, s.srpRecommended,
      s.srpClasses, s.srpClassLearners);
  if (reminders) {
    out.write('\n  Reminders:\n');
    out.write(coordinatorRemindersText([s.reminders]).split('\n').map((l) => '    $l').join('\n'));
  } else {
    out.write('\n  Reminders: ${s.reminders.reminders.length}');
  }
}

String _text(DashboardSummary d) {
  final out = StringBuffer('Dashboard ${d.schoolYear} — ${d.today}\n');
  switch (d) {
    case TutorDashboard():
      out.write('Tutor ${d.tutorName ?? d.tutorId}');
      out.write('\n  My sections:');
      if (d.sections.isEmpty) out.write('\n    None this school year.');
      for (final (s, n) in d.sections) {
        out.write('\n    Grade ${s.gradeLevel} ${s.sectionName} (#${s.id}): $n learner${n == 1 ? '' : 's'}');
      }
      out.write('\n  ${_aral(d.aral)}');
      out.write('\n  Sessions held: ${d.reminders.sessionsHeld}, last ${d.reminders.lastSession ?? 'none'}');
      out.write('\n  Reminders:\n');
      out.write(tutorRemindersText(d.reminders).split('\n').map((l) => '    $l').join('\n'));
    case SchoolDashboard():
      _school(out, d.school, reminders: true);
    case RegionDashboard():
      if (d.schools.isEmpty) out.write('No schools on this device.\n');
      for (final s in d.schools) {
        _school(out, s, reminders: false);
        out.write('\n');
      }
      out.write('REGION TOTAL (${d.schools.length} school${d.schools.length == 1 ? '' : 's'})');
      _counts(out, '  ', d.counts, d.otherGrades);
      out.write('\n  ${_aral(d.aral)}');
      _reportsLines(out, '  ', d.masterlistLearners, d.masterlistNotAssessed, d.srpCandidates, d.srpRecommended,
          d.srpClasses, d.srpClassLearners);
      out.write('\n  Reminders: ${d.reminders.entries.map((e) => '${e.key.name} ${e.value}').join(', ')}');
  }
  return out.toString();
}

void registerDashboardCommands(ConsoleRegistry registry, DashboardViewModel vm) {
  void add(String name, String description, Future<String> Function(List<String> args) handler) {
    registry.register(ConsoleCommand(
      name: name,
      description: description,
      handler: (args) async {
        try {
          return await handler(args);
        } on _Usage catch (e) {
          return e.message;
        } catch (e) {
          return '$name failed: $e';
        }
      },
    ));
  }

  add('dashboard-years', 'dashboard-years — the school years on this device, latest first', (args) async {
    if (args.isNotEmpty) throw const _Usage('Usage: dashboard-years');
    final years = await vm.schoolYears();
    return years.isEmpty ? 'No school years on this device.' : years.join('\n');
  });

  add('dashboard', 'dashboard <year> [today=YYYY-MM-DD] — the signed-in user\'s home-screen numbers and reminders',
      (args) async {
    if (args.isEmpty) throw const _Usage(_usage);
    return _text(await vm.summary(args[0], today: _today(args.sublist(1))));
  });
}
