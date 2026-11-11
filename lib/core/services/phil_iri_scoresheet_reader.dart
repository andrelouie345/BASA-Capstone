// lib/core/services/phil_iri_scoresheet_reader.dart
//
// Reads a filled BASA Phil-IRI scoresheet file (phil_iri_scoresheet_template
// .dart) into a PhilIriImportPlan (spec 2026-11-09-phil-iri-import; plan
// Task 7). Raw values only; learners by LRN, passages by "<code> <title>"
// (matching both is the importer's job, Task 9).
//
// Rules:
//  * The table is the first sheet (readTable); every field is found by its
//    header label (PhilIriImportHeaders.matches); Q1..Qn by the ss.q prefix.
//    A missing header is a PhilIriHeaderIssue and nothing is read.
//  * A row with nothing beyond LRN / Learner / Sex is an unused learner row,
//    ignored.
//  * Every row needs an LRN, a round and a date (D6). A GST row needs the GST
//    score. A reading row needs a passage (R2 D3: no Untitled here) and a
//    method; then a time (whole text, silent) or words read (one minute) for
//    a word reading. Answers without timing = a comprehension-only reading
//    (R2 D6), its miscues dropped with a problem; nothing usable = skipped as
//    incomplete. Miscues on a silent reading are dropped with a problem.
//  * Any unreadable value refuses the whole row: each one is a problem with
//    its row and column letter.
//  * Excel-mangled values (Review Focus 4): an LRN stored as a number gets
//    its 12 digits back (leading zeros); a date may be an Excel serial; a
//    time may be text (m:ss, h:mm:ss), whole seconds, or a day fraction. A
//    fraction of an hour or more in whole minutes is Excel's h:mm reading of
//    a typed m:ss (2:35 -> 155 s; Task 7 ruling, owner 2026-11-11), anything
//    else is a real time (0:02:35 -> 155 s).
import '../models/phil_iri_assessment.dart' show PhilIriRound;
import '../models/phil_iri_import.dart';
import '../models/phil_iri_miscue.dart';
import '../models/phil_iri_reading.dart' show PhilIriReadingMethod;
import 'phil_iri_import_headers.dart';
import 'phil_iri_scoresheet_template.dart';
import 'table_reader.dart';
import 'xlsx_cells.dart';

const _learnerColumns = ['Learner', 'Sex'];

/// Fields the table must have, in template order.
final _fields = [
  'ss.lrn', 'ss.round', 'ss.date', 'ss.passage', 'ss.method', 'ss.time', 'ss.wordsRead',
  for (final t in PhilIriMiscueType.values) 'ss.${t.name}',
  'ss.selfCorrected', 'ss.gst',
];

PhilIriImportPlan readPhilIriScoresheet(List<int> bytes, String fileName, PhilIriImportHeaders headers) {
  final (fileHeaders, rows) = readTable(bytes, fileName);
  final sheet = fileName.toLowerCase().endsWith('.xlsx') ? XlsxWorkbook.decode(bytes).sheetNames.first : fileName;

  // field -> index in fileHeaders
  final at = <String, int>{};
  final issues = <PhilIriHeaderIssue>[];
  for (final f in _fields) {
    final i = fileHeaders.indexWhere((h) => h.isNotEmpty && headers.matches(f, h));
    if (i < 0) {
      issues.add(PhilIriHeaderIssue(field: f, block: sheet, found: [for (final h in fileHeaders) if (h.isNotEmpty) h]));
    } else {
      at[f] = i;
    }
  }
  // question number -> index
  final qPrefix = normalizeHeader(headers.label('ss.q'));
  final qRe = RegExp('^${RegExp.escape(qPrefix)}(\\d+)\$');
  final questions = <int, int>{};
  for (var i = 0; i < fileHeaders.length; i++) {
    final m = qRe.firstMatch(normalizeHeader(fileHeaders[i]));
    final n = m == null ? null : int.parse(m.group(1)!);
    if (n != null && n >= 1 && !questions.containsKey(n)) questions[n] = i;
  }
  if (questions.isEmpty) {
    issues.add(PhilIriHeaderIssue(
        field: 'ss.q', block: sheet, found: [for (final h in fileHeaders) if (h.isNotEmpty) h]));
  }
  if (issues.isNotEmpty) {
    return PhilIriImportPlan(source: PhilIriImportSource.scoresheet, headerIssues: issues);
  }

  final reader = _RowReader(sheet, fileHeaders, at, questions);
  for (final row in rows) {
    reader.read(row);
  }
  return PhilIriImportPlan(
    source: PhilIriImportSource.scoresheet,
    gst: reader.gst,
    readings: reader.readings,
    skipped: reader.skipped,
    problems: reader.problems,
  );
}

class _RowReader {
  final String sheet;
  final List<String> fileHeaders;
  final Map<String, int> at;
  final Map<int, int> questions;

  final gst = <PhilIriImportGst>[];
  final readings = <PhilIriImportReading>[];
  final skipped = <PhilIriImportSkip>[];
  final problems = <PhilIriImportProblem>[];

  _RowReader(this.sheet, this.fileHeaders, this.at, this.questions);

  late TableRow _row;
  late List<PhilIriImportProblem> _rowProblems;

  String? _byIndex(int i) => _row.get([fileHeaders[i]]);
  String? _v(String field) => _byIndex(at[field]!);
  PhilIriImportRef _ref(int? index) => PhilIriImportRef(
        sheet: sheet,
        row: _row.rowNo,
        column: index == null ? null : columnLetters(index + 1),
      );
  void _bad(String field, String message) => _rowProblems.add(PhilIriImportProblem(ref: _ref(at[field]), message: message));

  void read(TableRow row) {
    _row = row;
    _rowProblems = [];

    // An unused learner row: nothing beyond LRN / Learner / Sex.
    final learnerIdx = {at['ss.lrn']!, for (final h in _learnerColumns) ...[
      for (var i = 0; i < fileHeaders.length; i++) if (normalizeHeader(fileHeaders[i]) == normalizeHeader(h)) i,
    ]};
    var used = false;
    for (var i = 0; i < fileHeaders.length; i++) {
      if (!learnerIdx.contains(i) && fileHeaders[i].isNotEmpty && _byIndex(i) != null) used = true;
    }
    if (!used) return;

    final learner = PhilIriLearnerKey(
      lrn: _lrn(),
      name: row.get([_learnerColumns[0]]),
      sex: switch ((row.get([_learnerColumns[1]]) ?? '').trim().toUpperCase()) {
        'M' || 'MALE' => 'M',
        'F' || 'FEMALE' => 'F',
        _ => null,
      },
    );
    final roundText = _v('ss.round');
    final isGst = roundText != null && normalizeHeader(roundText) == normalizeHeader(philIriScoresheetGst);
    final round = roundText == null || isGst ? null : _round(roundText);
    if (roundText == null) _bad('ss.round', 'Round is required');
    final date = _date();

    if (isGst) {
      _readGst(learner, date);
    } else {
      _readReading(learner, round, date);
    }
  }

  // ---- values ----

  String? _lrn() {
    final v = _v('ss.lrn');
    if (v == null) {
      _bad('ss.lrn', 'LRN is required');
      return null;
    }
    final s = v.replaceAll(' ', '');
    if (RegExp(r'^\d+$').hasMatch(s)) return s.length < 12 ? s.padLeft(12, '0') : s;
    final n = num.tryParse(s);
    if (n != null) {
      if (n == n.truncateToDouble() && n > 0 && n < 1e15) {
        final d = n.toInt().toString();
        return d.length < 12 ? d.padLeft(12, '0') : d;
      }
      _bad('ss.lrn', 'Unreadable LRN "$v"');
      return null;
    }
    return v; // kept as typed; the importer matches it
  }

  PhilIriRound? _round(String v) {
    final n = normalizeHeader(v);
    for (final r in PhilIriRound.values) {
      if (n == normalizeHeader(r.label) || n == r.name) return r;
    }
    _bad('ss.round', 'Unknown round "$v" (use GST, BOSY, MOSY1, MOSY2, MOSY3 or EOSY)');
    return null;
  }

  String? _date() {
    final v = _v('ss.date');
    if (v == null) {
      _bad('ss.date', 'Date is required');
      return null;
    }
    final d = parseSheetDate(v);
    if (d == null || !_sameDay(v, d)) {
      _bad('ss.date', 'Unreadable date "$v" (use YYYY-MM-DD)');
      return null;
    }
    return d;
  }

  /// parseSheetDate rolls 2027-02-30 over to March: refuse a typed date whose
  /// day, month or year changed.
  bool _sameDay(String typed, String iso) {
    final s = typed.trim();
    if (num.tryParse(s) != null) return true;
    final p = iso.split('-').map(int.parse).toList();
    final isoIn = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})').firstMatch(s);
    if (isoIn != null) {
      return int.parse(isoIn.group(2)!) == p[1] && int.parse(isoIn.group(3)!) == p[2];
    }
    final us = RegExp(r'^(\d{1,2})/(\d{1,2})/').firstMatch(s);
    return us != null && int.parse(us.group(1)!) == p[1] && int.parse(us.group(2)!) == p[2];
  }

  /// A whole number >= [min], blank = null.
  int? _int(String field, String what, {int min = 0}) {
    final v = _v(field);
    if (v == null) return null;
    final n = num.tryParse(v.trim());
    if (n == null || n != n.truncateToDouble() || n < min) {
      _bad(field, 'Unreadable $what "$v" (a whole number${min > 0 ? ' above 0' : ''})');
      return null;
    }
    return n.toInt();
  }

  /// Seconds from m:ss, h:mm:ss, whole seconds or an Excel day fraction.
  int? _seconds() {
    final v = _v('ss.time');
    if (v == null) return null;
    final s = v.trim();
    int? secs;
    final clock = RegExp(r'^(\d+):(\d{1,2})(?::(\d{1,2}))?$').firstMatch(s);
    if (clock != null) {
      final a = int.parse(clock.group(1)!), b = int.parse(clock.group(2)!);
      final c = clock.group(3) == null ? null : int.parse(clock.group(3)!);
      if (b < 60 && (c == null || c < 60)) secs = c == null ? a * 60 + b : a * 3600 + b * 60 + c;
    } else {
      final n = num.tryParse(s);
      if (n != null && n > 0) {
        if (n < 1) {
          final raw = (n * 86400).round();
          // Excel read a typed m:ss as h:mm (2:35 -> 2 h 35 min): an hour or
          // more in whole minutes is that misreading, not a real time.
          secs = raw >= 3600 && raw % 60 == 0 ? raw ~/ 60 : raw;
        } else if (n == n.truncateToDouble()) {
          secs = n.toInt();
        }
      }
    }
    if (secs == null || secs <= 0) {
      _bad('ss.time', 'Unreadable time "$v" (use m:ss, e.g. 2:35)');
      return null;
    }
    return secs;
  }

  PhilIriReadingMethod? _method() {
    final v = _v('ss.method');
    if (v == null) {
      _bad('ss.method', 'Method is required');
      return null;
    }
    final n = normalizeHeader(v);
    for (final m in PhilIriReadingMethod.values) {
      if (n == normalizeHeader(philIriScoresheetMethod(m)) || n == normalizeHeader(m.value)) return m;
    }
    _bad('ss.method', 'Unknown method "$v" (use whole text, one minute or silent)');
    return null;
  }

  /// "G7C1 Dust" -> level 7, code G7C1, title Dust; "G7Pre" -> code only;
  /// anything else -> raw only (the importer may still match the title).
  PhilIriImportPassageRef? _passage() {
    final v = _v('ss.passage');
    if (v == null) {
      _bad('ss.passage', 'Passage is required');
      return null;
    }
    final raw = v.trim().replaceAll(RegExp(r'\s+'), ' ');
    final m = RegExp(r'^[Gg](\d{1,2})([A-Za-z]*\d*)(?: (.+))?$').firstMatch(raw);
    if (m == null) return PhilIriImportPassageRef(raw: raw, title: raw);
    return PhilIriImportPassageRef(
      raw: raw,
      level: int.parse(m.group(1)!),
      code: 'G${m.group(1)}${m.group(2)}',
      title: m.group(3),
    );
  }

  /// Answer letters by question, trimmed after the last answer; null = none.
  List<String?>? _answers() {
    final byQ = <int, String?>{};
    for (final e in questions.entries) {
      final v = _byIndex(e.value)?.trim();
      if (v == null || v.isEmpty) continue;
      if (!RegExp(r'^[A-Za-z]$').hasMatch(v)) {
        _rowProblems.add(PhilIriImportProblem(
          ref: _ref(e.value),
          message: 'Unreadable answer "$v" in ${fileHeaders[e.value]} (one letter, a to z)',
        ));
        continue;
      }
      byQ[e.key] = v.toLowerCase();
    }
    if (byQ.isEmpty) return null;
    final last = byQ.keys.reduce((a, b) => a > b ? a : b);
    return [for (var q = 1; q <= last; q++) byQ[q]];
  }

  // ---- rows ----

  void _readGst(PhilIriLearnerKey learner, String? date) {
    final score = _int('ss.gst', 'GST score');
    if (_v('ss.gst') == null) _bad('ss.gst', 'GST score is required on a GST row');
    final extras = [
      'ss.passage', 'ss.method', 'ss.time', 'ss.wordsRead', 'ss.selfCorrected',
      for (final t in PhilIriMiscueType.values) 'ss.${t.name}',
    ].any((f) => _v(f) != null) || questions.values.any((i) => _byIndex(i) != null);
    if (_flush() || score == null) return;
    gst.add(PhilIriImportGst(ref: _ref(null), learner: learner, score: score, date: date));
    if (extras) {
      problems.add(PhilIriImportProblem(
        ref: _ref(null),
        message: 'A GST row holds only the GST score and the date; its other cells were not imported',
      ));
    }
  }

  void _readReading(PhilIriLearnerKey learner, PhilIriRound? round, String? date) {
    final passage = _passage();
    final method = _method();
    final seconds = _seconds();
    final wordsRead = _int('ss.wordsRead', 'words read', min: 1);
    final miscues = <PhilIriMiscueType, int>{};
    for (final t in PhilIriMiscueType.values) {
      final n = _int('ss.${t.name}', '${t.label.toLowerCase()} count');
      if (n != null && n > 0) miscues[t] = n;
    }
    final selfCorrected = _int('ss.selfCorrected', 'self-corrected count') ?? 0;
    final answers = _answers();
    final gstOnReading = _v('ss.gst') != null;
    if (_flush() || round == null || method == null || passage == null) return;

    final timed = switch (method) {
      PhilIriReadingMethod.oneMinute => wordsRead != null,
      _ => seconds != null,
    };
    if (!timed && answers == null) {
      skipped.add(PhilIriImportSkip(
        ref: _ref(null),
        learner: learner,
        round: round,
        reason: 'incomplete: ${method == PhilIriReadingMethod.oneMinute ? 'no words read' : 'no time'}, no answers',
      ));
      return;
    }
    var keptMiscues = miscues;
    var keptSelf = selfCorrected;
    final hasMiscues = miscues.isNotEmpty || selfCorrected > 0;
    if (hasMiscues && !timed) {
      problems.add(PhilIriImportProblem(ref: _ref(null), message: 'miscues without a time, not imported'));
      keptMiscues = const {};
      keptSelf = 0;
    } else if (hasMiscues && method == PhilIriReadingMethod.silent) {
      problems.add(PhilIriImportProblem(ref: _ref(null), message: 'miscues on a silent reading, not imported'));
      keptMiscues = const {};
      keptSelf = 0;
    }
    if (gstOnReading) {
      problems.add(PhilIriImportProblem(
        ref: _ref(at['ss.gst']),
        message: 'GST score on a ${round.label} row was not imported (put it on its own GST row)',
      ));
    }
    readings.add(PhilIriImportReading(
      ref: _ref(null),
      learner: learner,
      round: round,
      date: date,
      passage: passage,
      method: method,
      seconds: timed && method != PhilIriReadingMethod.oneMinute ? seconds : null,
      wordsRead: timed ? wordsRead : null,
      miscues: keptMiscues,
      selfCorrected: keptSelf,
      answers: answers,
    ));
  }

  /// Moves the row's problems to the plan; true when there were any (the row
  /// is refused).
  bool _flush() {
    if (_rowProblems.isEmpty) return false;
    problems.addAll(_rowProblems);
    return true;
  }
}
