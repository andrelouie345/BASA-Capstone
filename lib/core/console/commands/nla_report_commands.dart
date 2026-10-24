// lib/core/console/commands/nla_report_commands.dart

/// The NLA portal report (Phil-IRI for JHS Form 2b) and the Division's ARAL
/// Reading report. Filters choose what is shown:
///   sections=<id,id,...>   only these sections (default: every Grade 4-10 section)
///   sex=m,f,t              which counts (default m,f,t)
///   rounds=bosy,mosy1,...  which rounds (default all five)
///   blocks=enrolment,gst,profile,form2b,aral   which parts (default all)
///   rows=sections|total|both   section lines, the school total, or both (default both)
///   asof=YYYY-MM-DD        results assessed by that date (default today)
///
/// Also progress monitoring (progress-report, progress-report-csv): learners
/// assessed per round against a done threshold, done=<percent> (default: the saved
/// report setting, 85% when none),
/// with sections=, rows= and asof= as above.
///
/// And the BOSY masterlist (bosy-masterlist, bosy-masterlist-csv): learners
/// not grade level ready at BOSY, with sections= and asof=.
library;


import '../console_command.dart';
import '../console_registry.dart';
import '../date_args.dart';
import '../file_output.dart';
import '../../../viewmodels/nla_report_viewmodel.dart';
import '../../models/phil_iri_assessment.dart' show PhilIriRound;
import '../../services/nla_form2b.dart';
import '../../services/phil_iri_rules.dart' show PhilIriLevel;

class _Usage implements Exception {
  final String message;
  const _Usage(this.message);
}

int _int(String raw, String what) =>
    int.tryParse(raw) ?? (throw _Usage('Invalid $what: "$raw" (expected a number)'));

const _options = '[sections=<id,...>] [sex=m,f,t] [rounds=bosy,mosy1,mosy2,mosy3,eosy] '
    '[blocks=enrolment,gst,profile,form2b,aral] [rows=sections|total|both] [asof=YYYY-MM-DD]';

/// Parses the options after the fixed arguments.
(NlaReportFilter, Set<int>?, DateTime?) _filter(List<String> opts) {
  Set<NlaSex>? sexes;
  Set<PhilIriRound>? rounds;
  Set<NlaBlock>? blocks;
  Set<int>? sections;
  DateTime? asOf;
  var sectionRows = true, schoolTotal = true;
  for (final o in opts) {
    final eq = o.indexOf('=');
    if (eq < 0) throw _Usage('Options look like key=value (got "$o"). $_options');
    final key = o.substring(0, eq);
    final values = o.substring(eq + 1).split(',').map((v) => v.trim().toLowerCase()).where((v) => v.isNotEmpty);
    switch (key) {
      case 'sex':
        sexes = {
          for (final v in values)
            switch (v) {
              'm' || 'male' => NlaSex.male,
              'f' || 'female' => NlaSex.female,
              't' || 'total' => NlaSex.total,
              _ => throw _Usage('sex is m, f and/or t (got "$v")'),
            },
        };
      case 'rounds':
        rounds = {
          for (final v in values)
            PhilIriRound.values.firstWhere((r) => r.name == v,
                orElse: () => throw _Usage('rounds are bosy, mosy1, mosy2, mosy3, eosy (got "$v")')),
        };
      case 'blocks':
        blocks = {
          for (final v in values)
            NlaBlock.values.firstWhere((b) => b.key == v,
                orElse: () => throw _Usage('blocks are enrolment, gst, profile, form2b, aral (got "$v")')),
        };
      case 'sections':
        sections = {for (final v in values) _int(v, 'section id')};
      case 'rows':
        final v = values.join();
        if (!{'sections', 'total', 'both'}.contains(v)) throw _Usage('rows is sections, total or both (got "$v")');
        sectionRows = v != 'total';
        schoolTotal = v != 'sections';
      case 'asof':
        asOf = strictDateArg(o.substring(eq + 1)) ?? (throw _Usage(asofDateMessage(o.substring(eq + 1))));
      default:
        throw _Usage('Unknown option "$key". $_options');
    }
  }
  if (sexes != null && sexes.isEmpty || rounds != null && rounds.isEmpty || blocks != null && blocks.isEmpty) {
    throw const _Usage('An option needs at least one value.');
  }
  return (
    NlaReportFilter(
      sexes: sexes ?? const {NlaSex.male, NlaSex.female, NlaSex.total},
      rounds: rounds ?? const {...PhilIriRound.values},
      blocks: blocks ?? const {...NlaBlock.values},
      sectionRows: sectionRows,
      schoolTotal: schoolTotal,
    ),
    sections,
    asOf,
  );
}

/// "M 3 F 5 T 8" with the chosen sexes (just "8" when only the total is shown).
String _v(NlaCounts c, NlaReportFilter f) {
  final sexes = f.sexList;
  if (sexes.length == 1 && sexes.single == NlaSex.total) return '${c.total}';
  return sexes.map((s) => '${switch (s) { NlaSex.male => 'M', NlaSex.female => 'F', NlaSex.total => 'T' }} ${nlaValue(c, s)}').join(' ');
}

String _text(NlaReport report, NlaReportFilter f) {
  final out = StringBuffer('NLA report (Phil-IRI for JHS Form 2b) | school ${report.schoolId} | ${report.schoolYear} '
      '| as of ${report.asOf}');
  void block(NlaSectionReport r, String name) {
    out.write('\n$name');
    if (f.blocks.contains(NlaBlock.enrolment)) out.write('\n  Enrolment: ${_v(r.enrolment, f)}');
    if (f.blocks.contains(NlaBlock.gst)) {
      out.write('\n  GST scores: ${NlaGstBand.values.map((b) => '${b.label}: ${_v(r.gst[b]!, f)}').join(' | ')}');
    }
    if (f.blocks.contains(NlaBlock.profile)) {
      out.write('\n  GST profile: ${[PhilIriLevel.frustration, PhilIriLevel.instructional, PhilIriLevel.independent]
          .map((l) => '${l.label}: ${_v(r.gstProfile[l]!, f)}').join(' | ')}');
    }
    for (final round in f.roundList) {
      final taken = r.conducted.contains(round);
      if (f.blocks.contains(NlaBlock.form2b)) {
        out.write('\n  ${round.label}${taken ? '' : ' (not taken yet)'}: assessed ${_v(r.assessed(round), f)}'
            ' | GLR ${_v(r.band(round, NlaBand.glr), f)}'
            ' | 2-LD Ind ${_v(r.band(round, NlaBand.ld2Independent), f)}, Ins ${_v(r.band(round, NlaBand.ld2Instructional), f)}, '
            'Frus ${_v(r.band(round, NlaBand.ld2Frustration), f)} = ${_v(r.ld2(round), f)}'
            ' | 3-LD Ind ${_v(r.band(round, NlaBand.ld3Independent), f)}, Ins ${_v(r.band(round, NlaBand.ld3Instructional), f)}, '
            'Frus ${_v(r.band(round, NlaBand.ld3Frustration), f)} = ${_v(r.ld3(round), f)}');
      }
      if (f.blocks.contains(NlaBlock.aral)) {
        out.write('\n  ${round.label} ARAL (Division): 3-LD ${_v(r.ld3(round), f)} | 2-LD ${_v(r.ld2(round), f)} '
            '| total ${_v(NlaCounts.sum([r.ld3(round), r.ld2(round)]), f)}'
            '${round == PhilIriRound.bosy ? '' : ' | exited ${_v(r.band(round, NlaBand.glr), f)}'}');
      }
    }
  }

  if (f.sectionRows) {
    for (final r in report.sections) {
      block(r, 'G${r.grade} ${r.section!.sectionName} (#${r.section!.id})');
    }
  }
  if (f.schoolTotal) block(report.total, 'SCHOOL TOTAL (${report.sections.length} section(s))');
  return out.toString();
}

// ---- progress monitoring ----

const _progressOptions = '[done=<percent, default: saved setting>] [sections=<id,...>] [rows=sections|total|both] [asof=YYYY-MM-DD]';

({double? done, Set<int>? sections, bool sectionRows, bool schoolTotal, DateTime? asOf}) _progressFilter(
    List<String> opts) {
  double? done;
  Set<int>? sections;
  DateTime? asOf;
  var sectionRows = true, schoolTotal = true;
  for (final o in opts) {
    final eq = o.indexOf('=');
    if (eq < 0) throw _Usage('Options look like key=value (got "$o"). $_progressOptions');
    final key = o.substring(0, eq);
    final raw = o.substring(eq + 1).trim();
    switch (key) {
      case 'done':
        final p = double.tryParse(raw.endsWith('%') ? raw.substring(0, raw.length - 1) : raw);
        if (p == null || p <= 0 || p > 100) throw _Usage('done is a percent above 0 and up to 100 (got "$raw")');
        done = p / 100;
      case 'sections':
        sections = {
          for (final v in raw.split(',').map((v) => v.trim()).where((v) => v.isNotEmpty)) _int(v, 'section id'),
        };
        if (sections.isEmpty) throw const _Usage('An option needs at least one value.');
      case 'rows':
        final v = raw.toLowerCase();
        if (!{'sections', 'total', 'both'}.contains(v)) throw _Usage('rows is sections, total or both (got "$v")');
        sectionRows = v != 'total';
        schoolTotal = v != 'sections';
      case 'asof':
        asOf = strictDateArg(raw) ?? (throw _Usage(asofDateMessage(raw)));
      default:
        throw _Usage('Unknown option "$key". $_progressOptions');
    }
  }
  return (done: done, sections: sections, sectionRows: sectionRows, schoolTotal: schoolTotal, asOf: asOf);
}

String _progressText(ProgressReport report, bool sectionRows, bool schoolTotal) {
  String pct(double? s) => s == null ? '-' : '${progressPercent(s)}%';
  final out = StringBuffer('Progress monitoring | school ${report.schoolId} | ${report.schoolYear} '
      '| as of ${report.asOf} | done at ${progressPercent(report.doneThreshold)}%');
  void block(ProgressSectionReport r, String name) {
    final e = r.enrolment, g = r.gstTakers;
    out.write('\n$name');
    out.write('\n  Enrolment: M ${e.male} F ${e.female} T ${e.total} | GST takers: M ${g.male} F ${g.female} '
        'T ${g.total} (${pct(r.gstShare())})');
    out.write('\n  ${PhilIriRound.values.map((round) => '${round.label} ${r.assessed[round]!.total} '
        '(${pct(r.share(round))}) ${report.status(r, round) ?? '-'}').join(' | ')}');
  }

  if (sectionRows) {
    for (final r in report.sections) {
      block(r, 'G${r.grade} ${r.section!.sectionName} (#${r.section!.id})');
    }
  }
  if (schoolTotal) block(report.total, 'SCHOOL TOTAL (${report.sections.length} section(s))');
  return out.toString();
}

// ---- BOSY masterlist ----

const _masterlistOptions = '[sections=<id,...>] [asof=YYYY-MM-DD]';

({Set<int>? sections, DateTime? asOf}) _masterlistFilter(List<String> opts) {
  Set<int>? sections;
  DateTime? asOf;
  for (final o in opts) {
    final eq = o.indexOf('=');
    if (eq < 0) throw _Usage('Options look like key=value (got "$o"). $_masterlistOptions');
    final raw = o.substring(eq + 1).trim();
    switch (o.substring(0, eq)) {
      case 'sections':
        sections = {
          for (final v in raw.split(',').map((v) => v.trim()).where((v) => v.isNotEmpty)) _int(v, 'section id'),
        };
        if (sections.isEmpty) throw const _Usage('An option needs at least one value.');
      case 'asof':
        asOf = strictDateArg(raw) ?? (throw _Usage(asofDateMessage(raw)));
      default:
        throw _Usage('Unknown option "${o.substring(0, eq)}". $_masterlistOptions');
    }
  }
  return (sections: sections, asOf: asOf);
}

String _masterlistText(BosyMasterlist list) {
  final out = StringBuffer('Masterlist of learners not grade level ready at BOSY | school ${list.schoolId} '
      '| ${list.schoolYear} | as of ${list.asOf}');
  for (final s in list.sections) {
    out.write('\nG${s.grade} ${s.section.sectionName} (#${s.section.id}): ${s.learners.length} of ${s.enrolled} listed');
    for (final (i, e) in s.learners.indexed) {
      final comp = e.comprehension == null ? '' : ' · comprehension ${progressPercent(e.comprehension)}%';
      final down = e.levelsDown == null ? '' : ', ${e.levelsDown} down';
      out.write('\n  ${i + 1}. ${e.name} (${e.student.lrn}, ${e.student.sex ?? '?'}) · adjusted grade ${e.adjustedLevel}'
          ' · ${e.group}$down · ${e.profile.label}$comp${e.notAssessed ? ' · NOT ASSESSED (assumed)' : ''}');
    }
  }
  return out.toString();
}

void registerNlaReportCommands(ConsoleRegistry registry, NlaReportViewModel vm) {
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

  add('nla-report', 'nla-report <schoolId> <schoolYear> $_options — the NLA portal report (Form 2b) and the '
      'Division ARAL report, on screen', (args) async {
    if (args.length < 2) throw const _Usage('Usage: nla-report <schoolId> <schoolYear> $_options');
    final (filter, sections, asOf) = _filter(args.sublist(2));
    final report = await vm.report(
        schoolId: _int(args[0], 'schoolId'), schoolYear: args[1], sectionIds: sections, asOf: asOf);
    if (report.sections.isEmpty) return 'No Grade 4-10 sections for school ${args[0]} in ${args[1]}.';
    return _text(report, filter);
  });

  add('progress-report', 'progress-report <schoolId> <schoolYear> $_progressOptions — progress monitoring: '
      'learners assessed per round vs the done threshold', (args) async {
    if (args.length < 2) throw const _Usage('Usage: progress-report <schoolId> <schoolYear> $_progressOptions');
    final o = _progressFilter(args.sublist(2));
    final report = await vm.progress(
        schoolId: _int(args[0], 'schoolId'), schoolYear: args[1], sectionIds: o.sections,
        doneThreshold: o.done, asOf: o.asOf);
    if (report.sections.isEmpty) return 'No Grade 4-10 sections for school ${args[0]} in ${args[1]}.';
    return _progressText(report, o.sectionRows, o.schoolTotal);
  });

  add('progress-report-csv', 'progress-report-csv <schoolId> <schoolYear> <out.csv> $_progressOptions — the same as CSV',
      (args) async {
    if (args.length < 3) {
      throw const _Usage('Usage: progress-report-csv <schoolId> <schoolYear> <out.csv> $_progressOptions');
    }
    final o = _progressFilter(args.sublist(3));
    final report = await vm.progress(
        schoolId: _int(args[0], 'schoolId'), schoolYear: args[1], sectionIds: o.sections,
        doneThreshold: o.done, asOf: o.asOf);
    final error = await writeOutputFile(args[2],
        text: progressReportCsv(report, sectionRows: o.sectionRows, schoolTotal: o.schoolTotal));
    if (error != null) return error;
    return 'Wrote ${outputPath(args[2])} (${report.sections.length} section(s)).';
  });

  add('bosy-masterlist', 'bosy-masterlist <schoolId> <schoolYear> $_masterlistOptions — learners not grade level '
      'ready at BOSY, by section', (args) async {
    if (args.length < 2) throw const _Usage('Usage: bosy-masterlist <schoolId> <schoolYear> $_masterlistOptions');
    final o = _masterlistFilter(args.sublist(2));
    final list = await vm.bosyMasterlist(
        schoolId: _int(args[0], 'schoolId'), schoolYear: args[1], sectionIds: o.sections, asOf: o.asOf);
    if (list.sections.isEmpty) return 'No Grade 4-10 sections for school ${args[0]} in ${args[1]}.';
    return _masterlistText(list);
  });

  add('bosy-masterlist-csv', 'bosy-masterlist-csv <schoolId> <schoolYear> <out.csv> $_masterlistOptions — the same '
      'as CSV', (args) async {
    if (args.length < 3) {
      throw const _Usage('Usage: bosy-masterlist-csv <schoolId> <schoolYear> <out.csv> $_masterlistOptions');
    }
    final o = _masterlistFilter(args.sublist(3));
    final list = await vm.bosyMasterlist(
        schoolId: _int(args[0], 'schoolId'), schoolYear: args[1], sectionIds: o.sections, asOf: o.asOf);
    final error = await writeOutputFile(args[2], text: bosyMasterlistCsv(list));
    if (error != null) return error;
    return 'Wrote ${outputPath(args[2])} (${list.sections.fold<int>(0, (n, s) => n + s.learners.length)} learner(s)).';
  });

  add('nla-report-csv','nla-report-csv <schoolId> <schoolYear> <out.csv> $_options — the same as CSV', (args) async {
    if (args.length < 3) throw const _Usage('Usage: nla-report-csv <schoolId> <schoolYear> <out.csv> $_options');
    final (filter, sections, asOf) = _filter(args.sublist(3));
    final report = await vm.report(
        schoolId: _int(args[0], 'schoolId'), schoolYear: args[1], sectionIds: sections, asOf: asOf);
    final error = await writeOutputFile(args[2], text: nlaReportCsv(report, filter));
    if (error != null) return error;
    return 'Wrote ${outputPath(args[2])} (${report.sections.length} section(s)).';
  });
}
