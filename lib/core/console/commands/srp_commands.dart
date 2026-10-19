// lib/core/console/commands/srp_commands.dart

/// Summer Remediation Program (SRP), part 1: learners not grade level ready by
/// the end of the year, ranked weakest first, the weakest per section
/// recommended. Options:
///   per=N                  recommended learners per section (default 15)
///   show=all|recommended   every candidate, or only the recommended (default all)
///   sections=ID,...        only these sections (default: every Grade 4-10 section)
///   asof=YYYY-MM-DD        results assessed by that date (default today)
library;

import 'dart:io';

import '../console_command.dart';
import '../console_registry.dart';
import '../../../viewmodels/nla_report_viewmodel.dart' show progressPercent;
import '../../../viewmodels/srp_viewmodel.dart';
import '../../services/srp_rules.dart';

class _Usage implements Exception {
  final String message;
  const _Usage(this.message);
}

int _int(String raw, String what) =>
    int.tryParse(raw) ?? (throw _Usage('Invalid $what: "$raw" (expected a number)'));

const _options = '[per=<n, default $srpDefaultPerSection>] [show=all|recommended] [sections=<id,...>] '
    '[asof=YYYY-MM-DD]';

({int per, bool recommendedOnly, Set<int>? sections, DateTime? asOf}) _filter(List<String> opts) {
  var per = srpDefaultPerSection;
  var recommendedOnly = false;
  Set<int>? sections;
  DateTime? asOf;
  for (final o in opts) {
    final eq = o.indexOf('=');
    if (eq < 0) throw _Usage('Options look like key=value (got "$o"). $_options');
    final key = o.substring(0, eq);
    final raw = o.substring(eq + 1).trim();
    switch (key) {
      case 'per':
        per = _int(raw, 'per');
        if (per < 1) throw _Usage('per is at least 1 (got "$raw")');
      case 'show':
        final v = raw.toLowerCase();
        if (v != 'all' && v != 'recommended') throw _Usage('show is all or recommended (got "$raw")');
        recommendedOnly = v == 'recommended';
      case 'sections':
        sections = {
          for (final v in raw.split(',').map((v) => v.trim()).where((v) => v.isNotEmpty)) _int(v, 'section id'),
        };
        if (sections.isEmpty) throw const _Usage('An option needs at least one value.');
      case 'asof':
        asOf = DateTime.tryParse(raw) ?? (throw _Usage('asof is YYYY-MM-DD'));
      default:
        throw _Usage('Unknown option "$key". $_options');
    }
  }
  return (per: per, recommendedOnly: recommendedOnly, sections: sections, asOf: asOf);
}

String _text(SrpList list, bool recommendedOnly) {
  final out = StringBuffer('SRP candidates (not grade level ready by EOSY) | school ${list.schoolId} '
      '| ${list.schoolYear} | as of ${list.asOf} | ${list.perSection} recommended per section');
  for (final s in list.sections) {
    out.write('\nG${s.grade} ${s.section.sectionName} (#${s.section.id}): ${s.candidates.length} of ${s.enrolled} '
        'not grade level ready, ${s.recommendedCount} recommended');
    for (final c in s.candidates) {
      if (recommendedOnly && !c.recommended) continue;
      final result = c.notAssessed
          ? 'NOT ASSESSED (assumed)'
          : 'comprehension ${progressPercent(c.key.comprehension)}%, words ${progressPercent(c.key.wordRecognition)}%, '
              '${c.key.speed.toStringAsFixed(0)} wpm (${c.basisRound!.label})';
      final down = c.levelsDown == null ? '' : ', ${c.levelsDown} down';
      out.write('\n  #${c.rank}${c.recommended ? ' *' : '  '} ${c.name} (${c.student.lrn}, ${c.student.sex ?? '?'})'
          ' · adjusted grade ${c.adjustedLevel}$down · ${c.profile.label} · $result');
    }
  }
  out.write('\n(* = recommended)');
  return out.toString();
}

void registerSrpCommands(ConsoleRegistry registry, SrpViewModel vm) {
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

  add('srp-list', 'srp-list <schoolId> <schoolYear> $_options — Summer Remediation Program candidates, '
      'weakest first', (args) async {
    if (args.length < 2) throw const _Usage('Usage: srp-list <schoolId> <schoolYear> $_options');
    final o = _filter(args.sublist(2));
    final list = await vm.candidates(
        schoolId: _int(args[0], 'schoolId'), schoolYear: args[1], sectionIds: o.sections, perSection: o.per,
        asOf: o.asOf);
    if (list.sections.isEmpty) return 'No Grade 4-10 sections for school ${args[0]} in ${args[1]}.';
    return _text(list, o.recommendedOnly);
  });

  add('srp-list-csv', 'srp-list-csv <schoolId> <schoolYear> <out.csv> $_options — the same as CSV', (args) async {
    if (args.length < 3) throw const _Usage('Usage: srp-list-csv <schoolId> <schoolYear> <out.csv> $_options');
    final o = _filter(args.sublist(3));
    final list = await vm.candidates(
        schoolId: _int(args[0], 'schoolId'), schoolYear: args[1], sectionIds: o.sections, perSection: o.per,
        asOf: o.asOf);
    await File(args[2]).writeAsString(srpListCsv(list, recommendedOnly: o.recommendedOnly));
    final n = list.sections.fold<int>(
        0, (n, s) => n + (o.recommendedOnly ? s.recommendedCount : s.candidates.length));
    return 'Wrote ${args[2]} ($n learner(s)).';
  });
}
