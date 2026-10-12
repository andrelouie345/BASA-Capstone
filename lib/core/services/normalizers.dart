// lib/core/services/normalizers.dart
//
// Canonical forms for values that take part in unique keys. Every writer
// (SF1 importer, console commands, ViewModels) must go through these, or the
// same section/enrollment can exist twice under different spellings.

/// "Grade 7", "7", "G7" -> "7". Throws on input with no number (no
/// Kindergarten in BASA).
String normalizeGradeLevel(String raw) {
  final match = RegExp(r'\d+').firstMatch(raw);
  if (match == null) {
    throw FormatException('No numeric grade level found in "$raw"');
  }
  return int.parse(match.group(0)!).toString();
}

/// "2025-2026", "2025 - 2026", "SY 2025–2026", "2025/26" -> "2025-2026".
/// Throws on a bare year ("2026" is ambiguous) or a span that isn't exactly
/// one year. Postgres enforces the same shape with a CHECK constraint.
String normalizeSchoolYear(String raw) {
  final match = RegExp(r'(?<!\d)(\d{4})\s*[-‐-―/]\s*(\d{4}|\d{2})(?!\d)').firstMatch(raw);
  if (match == null) {
    throw FormatException('School year must look like 2025-2026 (got "$raw")');
  }
  final start = int.parse(match.group(1)!);
  var end = int.parse(match.group(2)!);
  if (match.group(2)!.length == 2) {
    end += start - start % 100;
    if (end < start) end += 100;
  }
  if (end != start + 1) {
    throw FormatException('School year must span exactly one year, e.g. $start-${start + 1} (got "$raw")');
  }
  return '$start-$end';
}
