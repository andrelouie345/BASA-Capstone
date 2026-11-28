// lib/core/models/export_table.dart
//
// A table a screen exports as it shows it (after its own search, filters and
// sort): spec docs/superpowers/specs/2026-11-28-table-export-design.md. The
// export prints what it's given and computes nothing.

enum ExportColumnKind { text, number }

class ExportColumn {
  final String label;

  /// Text cells stay text in Excel (an LRN keeps its digits); number cells
  /// are numbers.
  final ExportColumnKind kind;

  const ExportColumn(this.label, {this.kind = ExportColumnKind.text});
}

class ExportTable {
  final String title;
  final String? school;
  final String? schoolYear;

  /// Plain lines saying what the list is filtered by ("Grade 7, Rizal",
  /// "Search: cruz").
  final List<String> filters;
  final List<ExportColumn> columns;

  /// String / num / null (empty cell). A row shorter than [columns] is padded
  /// with empty cells; a longer one is refused.
  final List<List<Object?>> rows;

  const ExportTable(this.title,
      {this.school, this.schoolYear, this.filters = const [], required this.columns, this.rows = const []});
}

/// A table the export can't write (the message is shown as it is).
class ExportTableException implements Exception {
  final String message;
  const ExportTableException(this.message);
  @override
  String toString() => message;
}
