// lib/core/services/aral_report_xlsx.dart
//
// Writes the ARAL-Reading implementation report into the layout of "ARAL
// Reading Implementation Report.xlsx" (piece IE4). That file is a school's
// working copy, not a fixed DepEd form: its "GRADES 7-10 ENGLISH" sheet lists
// one school's own Grade 7 sections. Owner decision (2026-10-16): keep its
// header rows (titles, column groups, styles), clear everything below and
// write BASA's sections grouped by grade, with a TOTAL row per grade and for
// the school.
//
// Columns (as the template): B grade, C section, D enrolment, E/F/G BOSY
// Frustration (3 levels down) / Instructional (2 levels down) / total, H/I/J
// the same at MOSY, K exited = BOSY total - MOSY total (the template's
// formula). L (added): exits recorded on the ARAL roster, "grade-level ready
// / other". The level legend (M-V) is dropped. Totals are written as values.
// Owner decision (2026-10-16): G and J count EVERY ARAL learner, also those
// without a Phil-IRI result yet (the template sums E+F), so a total above
// E+F shows learners still missing a result.
// The district sheet (GRADES 7-10 FILIPINO) is removed, and so is who made
// the file and where it was stored.
import 'xlsx_cells.dart';

class AralReportXlsxRow {
  final int grade;
  final String section;
  final int enrolment;
  final int bosyFrustration;
  final int bosyInstructional;
  final int mosyFrustration;
  final int mosyInstructional;
  final int bosyTotal;            // every ARAL learner at BOSY, with or without a result
  final int mosyTotal;            // every ARAL learner still in ARAL at MOSY
  final int exitedGradeLevelReady;
  final int exitedOther;

  const AralReportXlsxRow({
    required this.grade,
    required this.section,
    required this.enrolment,
    required this.bosyFrustration,
    required this.bosyInstructional,
    required this.mosyFrustration,
    required this.mosyInstructional,
    required this.bosyTotal,
    required this.mosyTotal,
    required this.exitedGradeLevelReady,
    required this.exitedOther,
  });

}

const aralReportSheet = 'GRADES 7-10 ENGLISH';
const _districtSheet = 'GRADES 7-10 FILIPINO';
const _firstDataRow = 3;

/// Fills [template] with [rows] (sorted by grade, then section, by the caller).
List<int> fillAralImplementationReport(List<int> template, {required String asOf, required List<AralReportXlsxRow> rows}) {
  final wb = XlsxWorkbook.decode(template);
  if (!wb.hasSheet(aralReportSheet)) {
    throw XlsxException('Not the ARAL Reading Implementation Report template: no "$aralReportSheet" sheet '
        '(sheets: ${wb.sheetNames.join(', ')}).');
  }
  const s = aralReportSheet;
  // Styles of the template's first section row and its TOTAL row, before clearing.
  final cols = ['B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K'];
  final rowStyle = {for (final c in cols) c: wb.styleOf(s, '${c}4')};
  final totalStyle = {for (final c in cols) c: wb.styleOf(s, '${c}33') ?? rowStyle[c]};
  rowStyle['L'] = rowStyle['K'];
  totalStyle['L'] = totalStyle['K'];
  final headStyle = wb.styleOf(s, 'K1');

  if (wb.hasSheet(_districtSheet)) wb.removeSheet(_districtSheet);
  wb.clearRowsFrom(s, _firstDataRow);
  wb.stripAuthorship();

  // Header: the exit column's date, the added roster-exits column, no legend.
  wb.write(s, {
    'K1': 'NUMBER OF ARAL LEARNERS EXITED as of $asOf (BOSY - MOSY)',
    'L1': 'EXITED (ROSTER) GLR / other',
    for (final c in const ['M', 'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V']) ...{'${c}1': null, '${c}2': null},
  });
  wb.setStyles(s, {
    'L1': headStyle,
    'L2': headStyle,
    for (final c in const ['M', 'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V']) ...{'${c}1': null, '${c}2': null},
  });
  wb.merge(s, 'L1:L2');

  var r = _firstDataRow;
  void line(Map<String, Object?> values, Map<String, int?> styles) {
    wb.write(s, {for (final e in values.entries) '${e.key}$r': e.value});
    wb.setStyles(s, {for (final e in styles.entries) '${e.key}$r': e.value});
    r++;
  }

  Map<String, Object?> numbers(Iterable<AralReportXlsxRow> list) {
    int sum(int Function(AralReportXlsxRow) f) => list.fold(0, (a, x) => a + f(x));
    final glr = sum((x) => x.exitedGradeLevelReady), other = sum((x) => x.exitedOther);
    return {
      'D': sum((x) => x.enrolment),
      'E': sum((x) => x.bosyFrustration),
      'F': sum((x) => x.bosyInstructional),
      'G': sum((x) => x.bosyTotal),
      'H': sum((x) => x.mosyFrustration),
      'I': sum((x) => x.mosyInstructional),
      'J': sum((x) => x.mosyTotal),
      'K': sum((x) => x.bosyTotal - x.mosyTotal),
      'L': '$glr / $other',
    };
  }

  final grades = rows.map((x) => x.grade).toSet().toList()..sort();
  for (final g in grades) {
    final mine = rows.where((x) => x.grade == g).toList();
    final first = r;
    for (final x in mine) {
      line({'B': r == first ? 'Grade $g' : null, 'C': x.section, ...numbers([x])}, rowStyle);
    }
    if (r - 1 > first) wb.merge(s, 'B$first:B${r - 1}');
    line({'C': 'TOTAL', ...numbers(mine)}, totalStyle);
  }
  if (grades.length > 1) line({'B': 'ALL GRADES', 'C': 'TOTAL', ...numbers(rows)}, totalStyle);
  return wb.encode();
}
