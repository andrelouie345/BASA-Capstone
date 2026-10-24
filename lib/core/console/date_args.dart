// lib/core/console/date_args.dart
// Strict YYYY-MM-DD console arguments (finding F17, 2026-10-24).

import '../services/calendar_rules.dart';

/// [raw] as a date when it is a real YYYY-MM-DD date, else null.
/// DateTime.tryParse alone rolls 2026-02-30 over to March and also takes
/// 20261024 or 2026-10-24T08:00; this refuses them.
DateTime? strictDateArg(String raw) {
  final s = raw.trim();
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(s)) return null;
  final d = DateTime.tryParse(s);
  return d == null || calendarDate(d) != s ? null : d;
}

/// The refusal for a bad asof= value (same wording as the trend commands).
String asofDateMessage(String raw) => 'asof must be a real YYYY-MM-DD date (got "${raw.trim()}")';

/// True when [raw] is written as YYYY-MM-DD (real date or not). Commands with
/// an optional date use it to tell a date from the next argument (F22): a
/// token that looks like a date but isn't one is refused, not read as notes.
bool looksLikeDateArg(String raw) => RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(raw.trim());

/// The refusal for a YYYY-MM-DD token that is not a real date (F22).
String notARealDateMessage(String raw) => '"${raw.trim()}" is not a real date (YYYY-MM-DD)';
