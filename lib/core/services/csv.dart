// lib/core/services/csv.dart
//
// CSV for the exports (IE4). Starts with a UTF-8 byte-order mark so Excel
// shows accented names (e.g. GARCÍA) correctly; fields with commas, quotes or
// line breaks are quoted.

String csvTable(List<List<Object?>> rows) =>
    '﻿${rows.map((r) => r.map(_field).join(',')).join('\r\n')}\r\n';

String _field(Object? v) {
  final s = v?.toString() ?? '';
  return s.contains(RegExp(r'[",\r\n]')) ? '"${s.replaceAll('"', '""')}"' : s;
}
