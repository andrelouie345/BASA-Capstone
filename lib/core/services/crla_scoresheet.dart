// lib/core/services/crla_scoresheet.dart
//
// Reads a filled DepEd CRLA2 scoresheet workbook (CRLA2_Grade{1,2,3}
// Scoresheet_v1.xlsx) into rows BASA can import, and checks each row with the
// same rules CrlaViewModel applies, so an import fails before anything is
// written rather than halfway through a learner.
//
// Layout (owner-supplied templates, 2026-10-16):
//  * One sheet per variant: "G<n> MT Reading Scoresheet" (mt; every grade),
//    "G<n> FIL Reading Scoresheet" (fil; Grades 2-3), "G3 ENG Reading
//    Scoresheet" (eng). Header: C3 assessment type (BoSY/MoSY/EoSY), C4 school
//    ID, C5 school name, C6 teacher, C8 section, C9 language; M7/P7 the words
//    of story 1/2 (formulas: the template's story list, else D9/E9 typed).
//  * Learners in rows 11-110. MT/FIL: B LRN, C name, D sex, E date, F task 1,
//    G task 2 low (rhymes/words), H task 2 high (sentences), K story, L
//    miscues, M words read (formula: story words - miscues), N/O minutes and
//    seconds, R comprehension, S experience 1-5, T observation "Level 1-4",
//    V remarks. ENG: F task 1, G words (task 2), J story, K miscues, L words
//    read (formula: 100 - miscues), M/N minutes and seconds, Q comprehension,
//    R experience, S observation, U remarks.
//  * FIL/ENG sheets copy B-E from the MT sheet's same row by formula; when
//    their cached values are missing (file not saved by Excel) the MT row is
//    used.
//  * A row is read when it has a Part 1 task 1 score or a story number.
import '../models/crla_assessment.dart' show CrlaRound;
import 'crla_rules.dart';
import 'xlsx_cells.dart';

/// One learner row of one variant sheet.
class CrlaScoresheetRow {
  final String sheet;
  final int rowNo;
  final String variant;               // mt / fil / eng
  final String? lrn;
  final String? name;
  final String? sex;
  final String? assessedOn;           // YYYY-MM-DD
  final int? task1;
  final int? task2Low;                // mt/fil: rhymes/words (task 1 below 7)
  final int? task2High;               // mt/fil: sentences (task 1 7 or above)
  final int? task2;                   // eng: words (task 1 1-10)
  final int? storyNo;                 // null = no Part 2
  final int? miscues;
  final int? wordsRead;
  final int? minutes;
  final int? seconds;
  final int? comprehension;
  final int? experienceRating;
  final int? observationLevel;
  final String? remarks;
  final List<String> problems;        // empty = importable

  const CrlaScoresheetRow({
    required this.sheet,
    required this.rowNo,
    required this.variant,
    this.lrn,
    this.name,
    this.sex,
    this.assessedOn,
    this.task1,
    this.task2Low,
    this.task2High,
    this.task2,
    this.storyNo,
    this.miscues,
    this.wordsRead,
    this.minutes,
    this.seconds,
    this.comprehension,
    this.experienceRating,
    this.observationLevel,
    this.remarks,
    this.problems = const [],
  });

  bool get ok => problems.isEmpty;
  bool get hasPart1 => task1 != null;
  bool get hasPart2 => storyNo != null;
}

/// A whole workbook.
class CrlaScoresheetFile {
  final int grade;
  final String? assessmentType;       // C3 as written (BoSY/MoSY/EoSY)
  final String? schoolIdCode;         // C4
  final String? sectionName;          // C8
  final Map<String, String?> languages; // variant -> C9
  final List<CrlaScoresheetRow> rows;

  const CrlaScoresheetFile(this.grade, this.assessmentType, this.schoolIdCode, this.sectionName, this.languages, this.rows);
}

class CrlaScoresheetException implements Exception {
  final String message;
  const CrlaScoresheetException(this.message);
  @override
  String toString() => message;
}

const _firstRow = 11;
const _lastRow = 110;

CrlaScoresheetFile readCrlaScoresheet(List<int> bytes) {
  final XlsxWorkbook wb;
  try {
    wb = XlsxWorkbook.decode(bytes);
  } on XlsxException catch (e) {
    throw CrlaScoresheetException('$e');
  }
  final sheetRe = RegExp(r'^G([123]) (MT|FIL|ENG) Reading Scoresheet$');
  final variants = <String, String>{}; // variant -> sheet name
  int? grade;
  for (final name in wb.sheetNames) {
    final m = sheetRe.firstMatch(name.trim());
    if (m == null) continue;
    final g = int.parse(m.group(1)!);
    if (grade != null && grade != g) {
      throw CrlaScoresheetException('The workbook mixes Grade $grade and Grade $g scoresheets.');
    }
    grade = g;
    variants[m.group(2)!.toLowerCase() == 'mt' ? 'mt' : m.group(2)!.toLowerCase()] = name;
  }
  if (grade == null || !variants.containsKey('mt')) {
    throw CrlaScoresheetException('Not a CRLA2 scoresheet: no "G1/G2/G3 MT Reading Scoresheet" sheet '
        '(sheets: ${wb.sheetNames.join(', ')}).');
  }

  final mtSheet = variants['mt']!;
  final mt = wb.readSheet(mtSheet);
  String? text(Map<String, Object> cells, String ref) {
    final v = cells[ref];
    if (v == null) return null;
    final s = (v is double && v == v.truncateToDouble() ? v.toInt() : v).toString().trim();
    return s.isEmpty ? null : s;
  }

  final rows = <CrlaScoresheetRow>[];
  final languages = <String, String?>{};
  for (final entry in variants.entries) {
    final variant = entry.key;
    final cells = variant == 'mt' ? mt : wb.readSheet(entry.value);
    languages[variant] = text(cells, 'C9') ?? (variant == 'fil' ? 'Filipino' : variant == 'eng' ? 'English' : null);
    final eng = variant == 'eng';
    // Column letters by variant.
    final c = eng
        ? (story: 'J', miscues: 'K', words: 'L', min: 'M', sec: 'N', comp: 'Q', exp: 'R', obs: 'S', remarks: 'U')
        : (story: 'K', miscues: 'L', words: 'M', min: 'N', sec: 'O', comp: 'R', exp: 'S', obs: 'T', remarks: 'V');
    // The header's story totals (formulas), else the typed counts they fall back on.
    final story1Words = _int(cells['M7']) ?? _int(cells['D9']);
    final story2Words = _int(cells['P7']) ?? _int(cells['E9']);

    for (var r = _firstRow; r <= _lastRow; r++) {
      final task1Raw = cells['F$r'];
      final storyRaw = cells['${c.story}$r'];
      if (task1Raw == null && storyRaw == null) continue;
      final problems = <String>[];

      int? num(String col, String what, int min, int max) {
        final v = cells['$col$r'];
        if (v == null) return null;
        final n = _int(v);
        if (n == null) {
          problems.add('$what "$v" is not a whole number');
          return null;
        }
        if (n < min || n > max) problems.add('$what $n is outside $min-$max');
        return n;
      }

      // B-E: this sheet's cached copy, else the MT sheet's same row.
      String? id(String col) => text(cells, '$col$r') ?? text(mt, '$col$r');
      final lrn = id('B');
      final name = id('C');
      if (lrn == null) problems.add('no LRN');
      final dateRaw = cells['E$r'] ?? mt['E$r'];
      final date = _date(dateRaw);
      if (date == null) problems.add(dateRaw == null ? 'no date of assessment' : 'date "$dateRaw" is not a date');

      final task1 = num('F', 'Task 1', 0, 10);
      int? task2Low, task2High, task2;
      if (eng) {
        task2 = num('G', 'Words (task 2)', 0, 10);
        if (task2 != null && (task1 ?? 0) < 1) problems.add('Words (task 2) only applies when Task 1 is 1 or above');
      } else {
        task2Low = num('G', 'Task 2 low', 0, 10);
        task2High = num('H', 'Task 2 high (sentences)', 0, 10);
        if (task2Low != null && task2High != null) problems.add('both Task 2 low and Task 2 high are filled');
        if (task2Low != null && (task1 ?? 0) >= 7) problems.add('Task 2 low only applies when Task 1 is below 7');
        if (task2High != null && task1 != null && task1 < 7) problems.add('Task 2 high only applies when Task 1 is 7 or above');
      }
      if (task1 == null && task1Raw == null) problems.add('Part 2 without a Part 1 Task 1 score');

      int? storyNo, miscues, wordsRead, minutes, seconds, comprehension, rating, observation;
      if (storyRaw != null) {
        storyNo = num(c.story, 'Story number', 1, 2);
        miscues = num(c.miscues, 'Miscues', 0, 1 << 30) ?? 0;
        wordsRead = _int(cells['${c.words}$r']);
        if (wordsRead == null) {
          final total = eng ? 100 : (storyNo == 1 ? story1Words : storyNo == 2 ? story2Words : null);
          wordsRead = total == null ? null : total - miscues;
        }
        if (wordsRead == null) {
          problems.add('words read is missing (open and save the file in Excel so its formulas are calculated)');
        } else if (wordsRead < 0) {
          problems.add('words read is negative (more miscues than words in the story)');
        }
        minutes = num(c.min, 'Minutes', 0, 1 << 30) ?? 0;
        seconds = num(c.sec, 'Seconds', 0, 59) ?? 0;
        final cap = crlaTimeCapSeconds(grade, variant);
        if (minutes * 60 + seconds > cap) {
          problems.add('reading time $minutes:${seconds.toString().padLeft(2, '0')} is over the '
              'Grade $grade $variant limit of ${cap ~/ 60}:${(cap % 60).toString().padLeft(2, '0')}');
        }
        if (minutes == 0 && seconds == 0) problems.add('no reading time');
        comprehension = num(c.comp, 'Comprehension', 0, crlaComprehensionMax(grade, variant));
        if (comprehension == null && cells['${c.comp}$r'] == null) problems.add('no comprehension score');
        rating = num(c.exp, 'Learner experience', 1, 5);
        final obsRaw = cells['${c.obs}$r'];
        if (obsRaw != null) {
          final m = RegExp(r'^(?:level\s*)?([1-4])$', caseSensitive: false).firstMatch('$obsRaw'.trim());
          if (m == null) {
            problems.add('observation level "$obsRaw" is not Level 1-4');
          } else {
            observation = int.parse(m.group(1)!);
          }
        }
      }

      rows.add(CrlaScoresheetRow(
        sheet: entry.value,
        rowNo: r,
        variant: variant,
        lrn: lrn,
        name: name,
        sex: id('D'),
        assessedOn: date,
        task1: task1,
        task2Low: task2Low,
        task2High: task2High,
        task2: task2,
        storyNo: storyNo,
        miscues: miscues,
        wordsRead: wordsRead,
        minutes: minutes,
        seconds: seconds,
        comprehension: comprehension,
        experienceRating: rating,
        observationLevel: observation,
        remarks: text(cells, '${c.remarks}$r'),
        problems: problems,
      ));
    }
  }
  return CrlaScoresheetFile(grade, text(mt, 'C3'), text(mt, 'C4'), text(mt, 'C8'), languages, rows);
}

/// BoSY / MoSY / EoSY (any case, with or without "SY") -> round.
CrlaRound? crlaRoundOf(String? raw) {
  if (raw == null) return null;
  final s = raw.toLowerCase().replaceAll(RegExp(r'[^a-z]'), '');
  return switch (s) {
    'bosy' || 'bo' || 'beginning' => CrlaRound.bosy,
    'mosy' || 'mo' || 'middle' => CrlaRound.mosy,
    'eosy' || 'eo' || 'end' => CrlaRound.eosy,
    _ => null,
  };
}

int? _int(Object? v) {
  if (v is int) return v;
  if (v is double) return v == v.truncateToDouble() ? v.toInt() : null;
  if (v is String) return int.tryParse(v.trim());
  return null;
}

/// An Excel date serial, or text as YYYY-MM-DD, M/D/YY or M/D/YYYY.
String? _date(Object? v) {
  DateTime? d;
  if (v is num) {
    if (v > 20000 && v < 80000) d = excelSerialDate(v);
  } else if (v is String) {
    final s = v.trim();
    final iso = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})').firstMatch(s);
    final us = RegExp(r'^(\d{1,2})/(\d{1,2})/(\d{2}|\d{4})$').firstMatch(s);
    if (iso != null) {
      d = DateTime.utc(int.parse(iso.group(1)!), int.parse(iso.group(2)!), int.parse(iso.group(3)!));
    } else if (us != null) {
      var y = int.parse(us.group(3)!);
      if (y < 100) y += 2000;
      d = DateTime.utc(y, int.parse(us.group(1)!), int.parse(us.group(2)!));
    }
  }
  if (d == null) return null;
  return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

// ---- Writing (IE3) ----

/// One variant's latest attempt, as the scoresheet's input columns.
class CrlaScoresheetEntry {
  final String assessedOn;      // YYYY-MM-DD
  final int? task1;
  final int? task2Low;
  final int? task2High;
  final int? task2;             // eng
  final int? storyNo;
  final int? miscues;
  final int? minutes;
  final int? seconds;
  final int? comprehension;
  final int? experienceRating;
  final int? observationLevel;
  final String? remarks;

  const CrlaScoresheetEntry({
    required this.assessedOn,
    this.task1,
    this.task2Low,
    this.task2High,
    this.task2,
    this.storyNo,
    this.miscues,
    this.minutes,
    this.seconds,
    this.comprehension,
    this.experienceRating,
    this.observationLevel,
    this.remarks,
  });
}

class CrlaScoresheetLearner {
  final String lrn;
  final String name;
  final String? sex;                                // 'Male' / 'Female'
  final Map<String, CrlaScoresheetEntry> entries;   // variant -> latest attempt
  const CrlaScoresheetLearner(this.lrn, this.name, this.sex, this.entries);
}

/// Fills a blank CRLA2 scoresheet template of grade [grade]: the MT sheet's
/// header and one row per learner (rows 11-110, the same row on every
/// variant sheet, as the template's FIL/ENG sheets copy the learner columns
/// from the MT row). Only input cells are written; Excel recalculates the
/// totals, levels, profiles, Class Record and Class Summary on open (with
/// DepEd's own bands). Returns the workbook and notes about what was left out.
(List<int>, List<String>) fillCrlaScoresheet(
  List<int> template, {
  required int grade,
  required String assessmentType,  // BoSY / MoSY / EoSY
  String? schoolCode,
  String? schoolName,
  String? teacher,
  String? sectionName,
  String? mtLanguage,
  int? male,
  int? female,
  int? story1Words,
  int? story2Words,
  int? filStory1Words,
  int? filStory2Words,
  required List<CrlaScoresheetLearner> learners,
}) {
  final XlsxWorkbook wb;
  try {
    wb = XlsxWorkbook.decode(template);
  } on XlsxException catch (e) {
    throw CrlaScoresheetException('$e');
  }
  final sheets = {
    for (final v in const ['mt', 'fil', 'eng'])
      if (wb.hasSheet('G$grade ${v.toUpperCase()} Reading Scoresheet')) v: 'G$grade ${v.toUpperCase()} Reading Scoresheet',
  };
  if (!sheets.containsKey('mt')) {
    throw CrlaScoresheetException('Not a blank Grade $grade CRLA2 scoresheet template: no "G$grade MT Reading Scoresheet" '
        'sheet (sheets: ${wb.sheetNames.join(', ')}).');
  }
  final notes = <String>[];
  final max = _lastRow - _firstRow + 1;
  if (learners.length > max) {
    notes.add('The scoresheet holds $max learners; ${learners.length - max} were left out.');
  }

  // Writes only cells that aren't formulas (a template may differ slightly).
  void put(String sheet, Map<String, Object?> cells) {
    final ok = <String, Object?>{};
    for (final e in cells.entries) {
      if (e.value == null) continue;
      if (wb.isFormula(sheet, e.key)) {
        notes.add('$sheet!${e.key} is a formula in this template; not written.');
      } else {
        ok[e.key] = e.value;
      }
    }
    if (ok.isNotEmpty) wb.write(sheet, ok);
  }

  final mt = sheets['mt']!;
  put(mt, {
    'C3': assessmentType, 'C4': schoolCode, 'C5': schoolName, 'C6': teacher, 'C8': sectionName, 'C9': mtLanguage,
    'D6': male, 'E6': female, 'D9': story1Words, 'E9': story2Words,
  });
  final fil = sheets['fil'];
  if (fil != null) put(fil, {'D9': filStory1Words, 'E9': filStory2Words});

  var r = _firstRow;
  for (final l in learners.take(max)) {
    final first = l.entries.values.isEmpty ? null : l.entries.values.first.assessedOn;
    put(mt, {
      'B$r': l.lrn,
      'C$r': l.name,
      'D$r': l.sex,
      'E$r': (l.entries['mt']?.assessedOn ?? first) == null ? null : _serial(l.entries['mt']?.assessedOn ?? first!),
    });
    for (final e in l.entries.entries) {
      final sheet = sheets[e.key];
      if (sheet == null) {
        notes.add('${l.name}: the template has no ${e.key.toUpperCase()} sheet; that result was left out.');
        continue;
      }
      final x = e.value;
      final obs = x.observationLevel == null ? null : 'Level ${x.observationLevel}';
      if (e.key == 'eng') {
        put(sheet, {
          'F$r': x.task1, 'G$r': x.task2, 'J$r': x.storyNo, 'K$r': x.miscues, 'M$r': x.minutes, 'N$r': x.seconds,
          'Q$r': x.comprehension, 'R$r': x.experienceRating, 'S$r': obs, 'U$r': x.remarks,
        });
      } else {
        put(sheet, {
          'F$r': x.task1, 'G$r': x.task2Low, 'H$r': x.task2High, 'K$r': x.storyNo, 'L$r': x.miscues,
          'N$r': x.minutes, 'O$r': x.seconds, 'R$r': x.comprehension, 'S$r': x.experienceRating, 'T$r': obs,
          'V$r': x.remarks,
        });
      }
    }
    r++;
  }
  return (wb.encode(), notes);
}

/// YYYY-MM-DD -> Excel date serial (1900 date system).
int _serial(String isoDate) {
  final d = DateTime.parse(isoDate.substring(0, 10));
  return DateTime.utc(d.year, d.month, d.day).difference(DateTime.utc(1899, 12, 30)).inDays;
}
