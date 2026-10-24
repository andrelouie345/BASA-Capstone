// lib/core/console/commands/aral_report_commands.dart

/// ARAL-Reading reports (read-only, generated on demand from the local copy).
library;

import '../console_command.dart';
import '../console_registry.dart';
import '../date_args.dart';
import '../../../viewmodels/aral_report_viewmodel.dart';

class _Usage implements Exception {
  final String message;
  const _Usage(this.message);
}

int _int(String raw, String what) =>
    int.tryParse(raw) ?? (throw _Usage('Invalid $what: "$raw" (expected a number)'));

String _counts(List<String> columns, Map<String, int> m) {
  final total = m.values.fold(0, (a, b) => a + b);
  return '${columns.map((c) => '$c ${m[c] ?? 0}').join(', ')} (total $total)';
}

/// One grade's sections added up.
String _subtotal(String label, AralReportTotals t) =>
    '$label | enrolment ${t.enrolment} | BOSY: ${_counts(t.columns, t.bosy)} | '
    'MOSY: ${_counts(t.columns, t.mosy)} | exited ${t.exited} (grade-level ready ${t.exitedGradeLevelReady}, '
    'other ${t.exitedOther}) | BOSY-MOSY ${t.bosyMinusMosy}';

void registerAralReportCommands(ConsoleRegistry registry, AralReportViewModel vm) {
  registry.register(ConsoleCommand(
    name: 'aral-report',
    description: 'aral-report <schoolId> <schoolYear> [sectionId] [asof=YYYY-MM-DD] — ARAL-Reading implementation '
        'report per section (BOSY / MOSY ARAL learners by levels down or CRLA profile, exits)',
    handler: (args) async {
      const usage = 'Usage: aral-report <schoolId> <schoolYear> [sectionId] [asof=YYYY-MM-DD]';
      try {
        if (args.length < 2) throw const _Usage(usage);
        int? section;
        DateTime? asOf;
        for (final a in args.skip(2)) {
          if (a.startsWith('asof=')) {
            asOf = strictDateArg(a.substring(5)) ?? (throw _Usage(asofDateMessage(a.substring(5))));
          } else {
            section = _int(a, 'sectionId');
          }
        }
        final report = await vm.implementationReport(
            schoolId: _int(args[0], 'schoolId'), schoolYear: args[1], sectionId: section, asOf: asOf);
        if (report.rows.isEmpty) return 'No Grade 1-10 sections in school ${report.schoolId} for ${report.schoolYear}.';
        final lines = <String>[
          'ARAL-Reading implementation report | school ${report.schoolId} | ${report.schoolYear} | as of ${report.asOf}',
          'Phil-IRI columns: levels down (3-LD = Frustration, 2-LD = Instructional in the division template); '
              'Grades 1-3: CRLA profiles.',
        ];
        final grades = report.gradeTotals;
        for (final g in grades.keys) {
          final rows = report.rows.where((r) => r.grade == g).toList();
          for (final r in rows) {
            lines.add('G$g ${r.section.sectionName} (#${r.section.id}) | enrolment ${r.enrolment} | '
                'BOSY: ${_counts(r.columns, r.bosy)} | MOSY: ${_counts(r.columns, r.mosy)} | '
                'exited ${r.exited} (grade-level ready ${r.exitedGradeLevelReady}, other ${r.exitedOther}) | '
                'BOSY-MOSY ${r.bosyMinusMosy}');
          }
          if (rows.length > 1) lines.add(_subtotal('  Grade $g total', grades[g]!));
        }
        if (grades.length > 1) {
          // Phil-IRI and CRLA columns differ, so the school line totals only.
          final t = report.schoolTotal;
          lines.add('SCHOOL TOTAL | enrolment ${t.enrolment} | BOSY ${t.bosyTotal} | MOSY ${t.mosyTotal} | '
              'exited ${t.exited} (grade-level ready ${t.exitedGradeLevelReady}, other ${t.exitedOther}) | '
              'BOSY-MOSY ${t.bosyMinusMosy}');
        }
        return lines.join('\n');
      } on _Usage catch (e) {
        return e.message;
      } catch (e) {
        return 'aral-report failed: $e';
      }
    },
  ));
}
