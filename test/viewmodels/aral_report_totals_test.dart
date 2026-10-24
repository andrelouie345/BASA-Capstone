// The ARAL implementation report's grade and school totals
// (spec docs/superpowers/specs/2026-10-24-vm-completeness-design.md, ARAL-G3).
import 'package:basa_capstone/core/models/section.dart';
import 'package:basa_capstone/viewmodels/aral_report_viewmodel.dart';
import 'package:flutter_test/flutter_test.dart';

AralSectionReportRow _row(int id, int grade, List<String> columns, Map<String, int> bosy, Map<String, int> mosy,
        {int enrolment = 30, int glr = 0, int other = 0}) =>
    AralSectionReportRow(
      section: Section(id: id, schoolId: 1, schoolYear: '2026-2027', gradeLevel: '$grade', sectionName: 'S$id'),
      grade: grade,
      usesCrla: grade <= 3,
      enrolment: enrolment,
      columns: columns,
      bosy: bosy,
      mosy: mosy,
      exitedGradeLevelReady: glr,
      exitedOther: other,
    );

void main() {
  final report = AralImplementationReport(1, '2026-2027', '2026-10-24', [
    _row(1, 2, ['High Emerging'], {'High Emerging': 4}, {'High Emerging': 3}, enrolment: 20, glr: 1),
    _row(2, 7, ['3-LD', '2-LD'], {'3-LD': 5, '2-LD': 2}, {'3-LD': 3, '2-LD': 2}, glr: 2),
    _row(3, 7, ['2-LD', aralReportNoResult], {'2-LD': 1, aralReportNoResult: 1}, {'2-LD': 1}, enrolment: 25, other: 1),
  ]);

  test("grade totals sum the grade's sections", () {
    final g7 = report.gradeTotals[7]!;
    expect(g7.columns, ['3-LD', '2-LD', aralReportNoResult]);
    expect(g7.enrolment, 55);
    expect(g7.bosy, {'3-LD': 5, '2-LD': 3, aralReportNoResult: 1});
    expect(g7.mosy, {'3-LD': 3, '2-LD': 3});
    expect(g7.bosyTotal, 9);
    expect(g7.mosyTotal, 6);
    expect(g7.exitedGradeLevelReady, 2);
    expect(g7.exitedOther, 1);
    expect(g7.exited, 3);
    expect(g7.bosyMinusMosy, 3);
    expect(report.gradeTotals.keys, [2, 7]);
    expect(report.gradeTotals[2]!.bosyTotal, 4);
  });

  test('school total sums all rows', () {
    final s = report.schoolTotal;
    expect(s.columns, isEmpty);
    expect(s.bosy, isEmpty);
    expect(s.mosy, isEmpty);
    expect(s.enrolment, 75);
    expect(s.bosyTotal, 13);
    expect(s.mosyTotal, 9);
    expect(s.exited, 4);
    expect(s.bosyMinusMosy, 4);
  });

  test('a report without rows has zero totals', () {
    const empty = AralImplementationReport(1, '2026-2027', '2026-10-24', []);
    expect(empty.gradeTotals, isEmpty);
    expect(empty.schoolTotal.bosyTotal, 0);
    expect(empty.schoolTotal.enrolment, 0);
  });
}
