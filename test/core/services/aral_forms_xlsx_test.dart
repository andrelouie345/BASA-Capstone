// aral_forms_xlsx.dart: ARAL Forms 1, 2 and 4 written as .xlsx (ARAL memo
// Plan B Task 6). Pure: the forms are built by hand here (AralFormsViewModel
// is tested in test/viewmodels/aral_forms_test.dart). Read back with BASA's
// reader for cell values and types, and opened with excel_plus as a second
// reader.
import 'package:basa_capstone/core/models/aral_forms.dart';
import 'package:basa_capstone/core/services/aral_forms_xlsx.dart';
import 'package:basa_capstone/core/services/xlsx_cells.dart';
import 'package:excel_plus/excel_plus.dart';
import 'package:flutter_test/flutter_test.dart';

AralForm1 _form1(String code, List<AralForm1Row> rows, {String tutor = 'Cruz, Ana'}) => AralForm1(
      schoolName: 'ZZ Forms School',
      schoolCode: 'ZZF1',
      classCode: code,
      grade: 2,
      tutorName: tutor,
      tutorType: tutor.isEmpty ? '' : 'Internal',
      sessionType: 'Pull-out',
      schedule: 'MWF 7:30-8:15',
      venue: 'Room 3',
      rows: rows,
      blanks: const ['district', 'workbook issued', 'remarks', 'signatures'],
    );

AralForm1Row _row(String lrn, String name, String sex) => AralForm1Row(
    lrn: lrn, name: name, sex: sex, homeGrade: 2, section: 'Two', adviser: 'Ms. Two',
    mosyTool: 'CRLA', mosyResult: 'Developing Reader');

void main() {
  group('Form 1', () {
    test('one sheet per class named by class code; header cells; the LRN as text', () {
      final bytes = aralForm1Xlsx([
        _form1('ARAL-R-G2-01', [_row('001234567890', 'Abad, Hugo', 'M'), _row('009999990701', 'Garcia, Gina M.', 'F')]),
        _form1('ARAL-R-G7-01', const [], tutor: ''),
      ]);
      final wb = XlsxWorkbook.decode(bytes);
      expect(wb.sheetNames, ['ARAL-R-G2-01', 'ARAL-R-G7-01']);
      const s = 'ARAL-R-G2-01';
      expect(wb.read(s, 'A1'), 'ARAL Form 1: Class list (Reading)');
      expect([for (var r = 3; r <= 16; r++) wb.read(s, 'A$r')], [
        'School', 'School ID', 'District', 'Class code', 'Grade', 'Learning area', 'Tutor', 'Tutor type',
        'Session type', 'Days and time', 'Venue', 'Male', 'Female', 'Total',
      ]);
      expect([for (var r = 3; r <= 16; r++) wb.read(s, 'B$r')], [
        'ZZ Forms School', 'ZZF1', null, 'ARAL-R-G2-01', 2, 'Reading', 'Cruz, Ana', 'Internal',
        'Pull-out', 'MWF 7:30-8:15', 'Room 3', 1, 1, 2,
      ]);
      expect(wb.read(s, 'B18'), 'LRN');
      expect([for (final c in 'ABCDEFGHI'.split('')) wb.read(s, '${c}19')],
          [1, '001234567890', 'Abad, Hugo', 'M', 2, 'Two', 'Ms. Two', 'CRLA', 'Developing Reader']);
      expect(wb.read(s, 'B20'), '009999990701'); // text: leading zeros kept
      expect(wb.read(s, 'A22'), 'Left blank for hand entry: district, workbook issued, remarks, signatures.');
      // The empty class: headers, no rows, blanks instead of "null".
      expect(wb.read('ARAL-R-G7-01', 'B9'), isNull);
      expect(wb.read('ARAL-R-G7-01', 'B16'), 0);
      expect(wb.read('ARAL-R-G7-01', 'A19'), isNull);
      expect(Excel.decodeBytes(bytes).tables.keys, ['ARAL-R-G2-01', 'ARAL-R-G7-01']);
    });

    test('sheet names: forbidden characters, 31 characters, repeats ignoring case', () {
      final wb = XlsxWorkbook.decode(aralForm1Xlsx([
        _form1('G2/A: [reading]', const []),
        _form1('g2/a: [Reading]', const []),
        _form1('A class name that is far too long for Excel', const []),
      ]));
      expect(wb.sheetNames, ['G2-A- -reading-', 'g2-a- -Reading- (2)', 'A class name that is far too lo']);
      expect(wb.read('g2-a- -Reading- (2)', 'B6'), 'g2/a: [Reading]'); // the class code itself is kept
    });

    test('no classes: refused', () {
      expect(() => aralForm1Xlsx(const []), throwsA(isA<XlsxException>()));
    });
  });

  test('Form 2: one row per class, the counts block, notes', () {
    final f = AralForm2(
      schoolName: 'ZZ Forms School',
      schoolCode: 'ZZF1',
      rows: [
        AralForm2Row(classCode: 'ARAL-R-G2-01', grade: 2, male: 1, female: 1, total: 2, mosyResult: 'Developing Reader',
            tutorName: 'Cruz, Ana', tutorType: 'I', advisoryClass: 'Grade 7 Seven', schedule: 'MWF 7:30-8:15',
            sessionType: 'Pull-out', venue: 'Room 3'),
        AralForm2Row(classCode: 'ARAL-R-G7-01', grade: 7, male: 1, female: 1, total: 2, mosyResult: 'mixed',
            tutorName: '', tutorType: '', advisoryClass: '', schedule: '', sessionType: '', venue: ''),
      ],
      readingClasses: 2,
      readingLearners: 4,
      internalTutors: 1,
      externalTutors: 0,
      blanks: const ['district', 'Mathematics columns', 'signatures'],
      notes: const ['Tutor type not set (counted as neither internal nor external): Reyes, Ben.'],
    );
    final bytes = aralForm2Xlsx(f);
    final wb = XlsxWorkbook.decode(bytes);
    expect(wb.sheetNames, ['Form 2']);
    const s = 'Form 2';
    expect(wb.read(s, 'A1'), 'ARAL Form 2: Classes (Reading)');
    expect((wb.read(s, 'B3'), wb.read(s, 'B4'), wb.read(s, 'B5')), ('ZZ Forms School', 'ZZF1', null));
    expect([for (final c in 'ABCDEFGHIJKLMNO'.split('')) wb.read(s, '${c}7')], [
      'No.', 'Class code', 'Grade', 'Area', 'Male', 'Female', 'Total', 'MoSY result', 'Tutor', 'Type (I/E)',
      'Advisory class', 'Days and time', 'Session type', 'Venue', 'Mathematics',
    ]);
    expect([for (final c in 'ABCDEFGHIJKLMN'.split('')) wb.read(s, '${c}8')], [
      1, 'ARAL-R-G2-01', 2, 'R', 1, 1, 2, 'Developing Reader', 'Cruz, Ana', 'I', 'Grade 7 Seven',
      'MWF 7:30-8:15', 'Pull-out', 'Room 3',
    ]);
    expect(wb.read(s, 'I9'), isNull); // no tutor: blank, never "null"
    expect([for (var r = 11; r <= 15; r++) (wb.read(s, 'A$r'), wb.read(s, 'B$r'))], [
      ('Reading classes', 2), ('Reading learners', 4), ('Internal tutors', 1), ('External tutors', 0),
      ('Mathematics classes', null),
    ]);
    expect(wb.read(s, 'A17'), 'Left blank for hand entry: district, Mathematics columns, signatures.');
    expect(wb.read(s, 'A18'), 'Tutor type not set (counted as neither internal nor external): Reyes, Ben.');
    expect(Excel.decodeBytes(bytes).tables.keys, ['Form 2']);
  });

  test('Form 4: Grade 1-10 rows, TOTAL = column sums, Part II, hours, notes', () {
    final grades = [for (var g = 1; g <= 10; g++) AralForm4Grade(g)];
    grades[1]
      ..identified = 2
      ..served = 1
      ..improved = 2
      ..atMosy = 2;
    grades[6]
      ..identified = 2
      ..reachedGradeLevel = 1
      ..improved = 1
      ..noImprovement = 1
      ..atMosy = 2;
    final f = AralForm4(
      schoolName: 'ZZ Forms School',
      schoolCode: 'ZZF1',
      asOf: '2026-11-14',
      grades: grades,
      classes: 3,
      internalTutors: 1,
      externalTutors: 1,
      sessions: 3,
      hours: 150 / 60,
      notes: const [
        '1 learner without a MoSY result by 2026-11-14 is counted under No improvement: Quino, Quin (Grade 7).',
        'Left blank for hand entry: Mathematics columns, narrative rows, signatures.',
      ],
    );
    final bytes = aralForm4Xlsx(f);
    final wb = XlsxWorkbook.decode(bytes);
    expect(wb.sheetNames, ['Form 4']);
    const s = 'Form 4';
    expect(wb.read(s, 'A1'), 'ARAL Form 4: Progress report (Reading)');
    expect((wb.read(s, 'B3'), wb.read(s, 'B4'), wb.read(s, 'B5')), ('ZZ Forms School', 'ZZF1', '2026-11-14'));
    expect(wb.read(s, 'A7'), 'Part I. Learners (Reading)');
    expect([for (final c in 'ABCDEFGH'.split('')) wb.read(s, '${c}8')], [
      'Grade', 'Identified at BoSY', 'Served in ARAL classes', 'Reached grade level (exited)',
      'Improved, still below (continue)', 'No improvement (referred)', 'ARAL learners at MoSY', 'Mathematics',
    ]);
    expect([for (var r = 9; r <= 18; r++) wb.read(s, 'A$r')], [for (var g = 1; g <= 10; g++) 'Grade $g']);
    expect([for (final c in 'BCDEFG'.split('')) wb.read(s, '${c}10')], [2, 1, 0, 2, 0, 2]);
    expect([for (final c in 'BCDEFG'.split('')) wb.read(s, '${c}15')], [2, 0, 1, 1, 1, 2]);
    expect(wb.read(s, 'A19'), 'TOTAL');
    expect([for (final c in 'BCDEFG'.split('')) wb.read(s, '${c}19')], [4, 1, 1, 3, 1, 4]);
    expect(wb.read(s, 'H19'), isNull);
    expect(wb.read(s, 'A21'), 'Part II. Implementation');
    expect([for (var r = 22; r <= 26; r++) (wb.read(s, 'A$r'), wb.read(s, 'B$r'))], [
      ('Organized ARAL classes', 3), ('Internal tutors', 1), ('External tutors', 1), ('Sessions conducted', 3),
      ('Hours rendered', 2.5),
    ]);
    expect(wb.read(s, 'A28'), f.notes[0]);
    expect(wb.read(s, 'A29'), f.notes[1]);
    expect(Excel.decodeBytes(bytes).tables.keys, ['Form 4']);
  });

  test('hours are rounded to 2 decimals', () {
    final f = AralForm4(
        schoolName: '', schoolCode: '', asOf: '2026-11-14', grades: [for (var g = 1; g <= 10; g++) AralForm4Grade(g)],
        classes: 0, internalTutors: 0, externalTutors: 0, sessions: 1, hours: 50 / 60, notes: const []);
    expect(XlsxWorkbook.decode(aralForm4Xlsx(f)).read('Form 4', 'B26'), 0.83);
  });
}
