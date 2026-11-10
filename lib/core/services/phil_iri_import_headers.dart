// lib/core/services/phil_iri_import_headers.dart
//
// Header labels of the two Phil-IRI import readers (spec D14). The readers find
// every field by its header label, never by column letter, so a coordinator's
// renamed header is fixed by changing the label here: no app release. Only a
// restructured round block needs code.
//
// Built-in defaults = ma's current workbook layout (her spellings kept, e.g.
// "Mispronounciation") and the BASA scoresheet template. Device overrides live
// in <data dir>/phil_iri_import_headers.json; only changed labels are stored,
// so a later default change still reaches every label nobody touched.
// Modelled on Sf1ColumnMap.
//
// Labels compare with normalizeHeader (table_reader.dart): case, spaces,
// slashes, punctuation and line breaks don't matter.
import 'dart:convert';
import 'dart:io';

import '../models/phil_iri_miscue.dart';
import 'table_reader.dart' show normalizeHeader;

class PhilIriImportHeaders {
  static const fileName = 'phil_iri_import_headers.json';

  /// Every field and its default label, in reading order (the scoresheet
  /// template writes its columns in this order).
  static final Map<String, String> defaults = {
    // ma's workbook: learner columns
    'wb.name': 'NAME OF STUDENT',
    'wb.gst': 'GST Raw Score',
    // ma's workbook: one set per round block
    'wb.selection': 'SELECTION',
    'wb.wordsRead': '# of Words Read',
    'wb.mispronunciation': 'Mispronounciation',
    'wb.omission': 'Omission / Deletion',
    'wb.substitution': 'Substitution',
    'wb.insertion': 'Insertion',
    'wb.reversal': 'Reversal/Hesitation',
    'wb.repetition': 'Repetition / Self-orrection',
    'wb.time': 'Total Time Reading the Text',
    'wb.minutes': 'mm',
    'wb.seconds': 'ss',
    'wb.comprehension': 'Reading Comprehension (Percent Score)',
    'wb.method': 'Reading Method',
    'wb.adjProfile': 'Adj. Reading Profile',
    'wb.adjLevel': 'Adj. Grade Level',
    // ma's workbook: round block titles
    'wb.block.bosy': 'IRA FOR GST RESULTS VALIDATION/PRETEST',
    'wb.block.mosy1': 'MIDDLE OF SCHOOL YEAR ASSESSMENT (MOSY #1)',
    'wb.block.mosy2': 'MIDDLE OF SCHOOL YEAR ASSESSMENT (MOSY #2)',
    'wb.block.mosy3': 'MIDDLE OF SCHOOL YEAR ASSESSMENT (MOSY #3)',
    'wb.block.eosy': 'END OF SCHOOL YEAR ASSESSMENT (EOSY) / POSTTEST',
    // BASA scoresheet file
    'ss.lrn': 'LRN',
    'ss.round': 'Round',
    'ss.date': 'Date',
    'ss.passage': 'Passage',
    'ss.method': 'Method',
    'ss.time': 'Time',
    'ss.wordsRead': 'Words read',
    for (final t in PhilIriMiscueType.values) 'ss.${t.name}': t.label,
    'ss.selfCorrected': 'Self-corrected',
    'ss.gst': 'GST score',
    'ss.q': 'Q', // prefix of Q1 ... Q20
  };

  final String _path;
  final Map<String, String> _changed;

  PhilIriImportHeaders._(this._path, this._changed);

  /// Reads the device overrides from [directory]. A missing or unreadable
  /// file, an unknown field or an empty label is ignored (defaults apply).
  static Future<PhilIriImportHeaders> load(String directory) async {
    final path = '$directory/$fileName';
    final changed = <String, String>{};
    final file = File(path);
    if (await file.exists()) {
      try {
        final data = jsonDecode(await file.readAsString());
        if (data is Map) {
          for (final e in data.entries) {
            final key = e.key, value = e.value;
            if (key is String && defaults.containsKey(key) && value is String && normalizeHeader(value).isNotEmpty) {
              changed[key] = value;
            }
          }
        }
      } on FormatException {
        // broken file: defaults apply; the next set/reset rewrites it
      }
    }
    return PhilIriImportHeaders._(path, changed);
  }

  /// Every field with its current label (changed or default), in reading order.
  Map<String, String> get labels => {for (final f in defaults.keys) f: _changed[f] ?? defaults[f]!};

  /// Only the labels changed on this device.
  Map<String, String> get changed => Map.unmodifiable(_changed);

  /// The current label of [field]. Throws on an unknown field (a code error).
  String label(String field) {
    final d = defaults[field];
    if (d == null) throw ArgumentError('Unknown header field "$field"');
    return _changed[field] ?? d;
  }

  /// Does [header] (a cell as the file has it) carry [field]'s label? Exact
  /// (normalized) first; otherwise the header with a trailing note in
  /// brackets removed, e.g. ma's sheet 13 "NAME OF STUDENT\n(Last Name, First
  /// Name)" carries "NAME OF STUDENT" (Task 6, owner option A, 2026-11-11).
  /// The label itself is never shortened, so a label with brackets of its own
  /// ("Reading Comprehension (Percent Score)") still needs them.
  bool matches(String field, String header) {
    final want = normalizeHeader(label(field));
    if (want.isEmpty) return false;
    if (normalizeHeader(header) == want) return true;
    final stripped = header.replaceFirst(RegExp(r'\s*\([^()]*\)\s*$'), '');
    return stripped != header && normalizeHeader(stripped) == want;
  }

  /// Changes one label on this device and saves. Setting a label equal to the
  /// default (once normalized) removes the override. Returns an error message,
  /// or null on success.
  Future<String?> set(String field, String label) async {
    final d = defaults[field];
    if (d == null) {
      return 'Unknown header field "$field". Valid fields: ${defaults.keys.join(', ')}';
    }
    final trimmed = label.trim();
    if (normalizeHeader(trimmed).isEmpty) {
      return 'The label for "$field" needs at least one letter or digit';
    }
    if (normalizeHeader(trimmed) == normalizeHeader(d)) {
      _changed.remove(field);
    } else {
      _changed[field] = trimmed;
    }
    await _save();
    return null;
  }

  /// Restores every default and deletes the device file.
  Future<void> reset() async {
    _changed.clear();
    final file = File(_path);
    if (await file.exists()) await file.delete();
  }

  Future<void> _save() async {
    final file = File(_path);
    if (_changed.isEmpty) {
      if (await file.exists()) await file.delete();
      return;
    }
    await file.writeAsString(jsonEncode(_changed));
  }
}
