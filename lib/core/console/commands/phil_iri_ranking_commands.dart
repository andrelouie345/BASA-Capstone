// lib/core/console/commands/phil_iri_ranking_commands.dart
// Admin build only (listed in tool/check_tutor_imports.dart): the Phil-IRI
// ranking list (spec 2026-11-14-phil-iri-value-sources-design, D9-D12).

import '../console_command.dart';
import '../console_registry.dart';
import '../date_args.dart';
import '../file_output.dart';
import '../../../viewmodels/phil_iri_ranking_viewmodel.dart';
import '../../models/report_setting.dart' show philIriValuesLabel;
import 'phil_iri_command_helpers.dart';

const _options = '[n=<N, default 10>] [section=<id>|grade=<4-10>] [asof=YYYY-MM-DD]';
const _measures = 'accuracy|wpm|comprehension';

void registerPhilIriRankingCommands(ConsoleRegistry registry, PhilIriRankingViewModel vm) {
  void add(String name, String description, Future<String> Function(List<String> args) handler) {
    registry.register(ConsoleCommand(
      name: name,
      description: description,
      handler: (args) async {
        try {
          return await handler(args);
        } on PhilIriUsage catch (e) {
          return e.message;
        } catch (e) {
          return '$name failed: $e';
        }
      },
    ));
  }

  Future<PhilIriRanking> run(List<String> args, List<String> opts) {
    final o = _parse(opts);
    return vm.rank(
      schoolId: philIriInt(args[0], 'schoolId'),
      schoolYear: args[1],
      round: philIriRound(args[2]),
      measure: _measure(args[3]),
      n: o.n,
      sectionId: o.section,
      grade: o.grade,
      asOf: o.asOf,
    );
  }

  add('phil-iri-rank',
      'phil-iri-rank <schoolId> <schoolYear> <round> <$_measures> $_options — the lowest N learners by one measure '
          "(values: the school's ranking switch)", (args) async {
    const usage = 'Usage: phil-iri-rank <schoolId> <schoolYear> <round> <$_measures> $_options';
    if (args.length < 4) throw const PhilIriUsage(usage);
    return _text(await run(args, args.sublist(4)));
  });

  add('phil-iri-rank-export',
      'phil-iri-rank-export <schoolId> <schoolYear> <round> <$_measures> <out.csv> $_options — the same as CSV',
      (args) async {
    const usage = 'Usage: phil-iri-rank-export <schoolId> <schoolYear> <round> <$_measures> <out.csv> $_options';
    if (args.length < 5) throw const PhilIriUsage(usage);
    final r = await run(args, args.sublist(5));
    final error = await writeOutputFile(args[4], text: philIriRankingCsv(r));
    if (error != null) return error;
    return 'Wrote ${outputPath(args[4])} (${r.ranked.length} ranked, ${r.unranked.length} not ranked).';
  });
}

PhilIriRankMeasure _measure(String raw) => switch (raw.toLowerCase()) {
      'accuracy' => PhilIriRankMeasure.accuracy,
      'wpm' => PhilIriRankMeasure.wpm,
      'comprehension' => PhilIriRankMeasure.comprehension,
      _ => throw PhilIriUsage('The measure is $_measures (got "$raw").'),
    };

({int n, int? section, int? grade, DateTime? asOf}) _parse(List<String> opts) {
  var n = 10;
  int? section, grade;
  DateTime? asOf;
  for (final o in opts) {
    final eq = o.indexOf('=');
    final raw = eq < 0 ? '' : o.substring(eq + 1).trim();
    switch (eq < 0 ? o : o.substring(0, eq)) {
      case 'n':
        n = philIriInt(raw, 'n');
      case 'section':
        section = philIriInt(raw, 'section');
      case 'grade':
        grade = philIriInt(raw, 'grade');
      case 'asof':
        asOf = strictDateArg(raw) ?? (throw PhilIriUsage(asofDateMessage(raw)));
      default:
        throw PhilIriUsage('Unknown option "$o". Options: $_options');
    }
  }
  return (n: n, section: section, grade: grade, asOf: asOf);
}

String _text(PhilIriRanking r) {
  final scope = r.sectionId != null
      ? 'section ${r.sectionId}'
      : r.grade != null
          ? 'Grade ${r.grade}'
          : 'whole school (Grades 4-10 together)';
  final out = StringBuffer('Phil-IRI ranking | school ${r.schoolId} | ${r.schoolYear} | ${r.round.label} | '
      '${r.measure.label}, lowest first | $scope | n ${r.n} | as of ${r.asOf}');
  out.write('\n${philIriValuesLabel(r.values)}');
  if (r.ranked.isEmpty) out.write('\nNobody has a value for this measure.');
  for (final x in r.ranked) {
    out.write('\n#${x.rank} ${x.name} (${x.student.lrn}) G${x.grade} ${x.section.sectionName}: '
        '${philIriRankValueText(r.measure, x.value)}${r.measure == PhilIriRankMeasure.wpm ? ' wpm' : '%'}'
        '${x.profile == null ? '' : ' · ${x.profile!.label}'}');
  }
  if (r.tiedPastN) {
    final last = r.ranked.last.rank;
    out.write('\n${r.ranked.length} shown: ${r.ranked.where((x) => x.rank == last).length} tied at rank $last');
  }
  if (r.unranked.isNotEmpty) {
    out.write('\nNot ranked (${r.unranked.length}):');
    for (final x in r.unranked) {
      out.write('\n  ${x.name} (${x.student.lrn}) G${x.grade} ${x.section.sectionName}: ${x.reason.label}');
    }
  }
  return out.toString();
}
