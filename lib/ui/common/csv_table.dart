// lib/ui/common/csv_table.dart
// Shows a report's CSV text (the ViewModels' *Csv functions) as a table that
// scrolls sideways, with a button that saves the same text as a file. The
// screen keeps no second copy of the report's layout.
import 'package:flutter/material.dart';

import 'screen_kit.dart';

/// Rows of cells from CSV text (quoted cells, doubled quotes, CRLF or LF).
List<List<String>> parseCsv(String text) {
  final rows = <List<String>>[];
  var row = <String>[];
  final cell = StringBuffer();
  var quoted = false;
  for (var i = 0; i < text.length; i++) {
    final ch = text[i];
    if (quoted) {
      if (ch == '"') {
        if (i + 1 < text.length && text[i + 1] == '"') {
          cell.write('"');
          i++;
        } else {
          quoted = false;
        }
      } else {
        cell.write(ch);
      }
    } else if (ch == '"') {
      quoted = true;
    } else if (ch == ',') {
      row.add(cell.toString());
      cell.clear();
    } else if (ch == '\n' || ch == '\r') {
      if (ch == '\r' && i + 1 < text.length && text[i + 1] == '\n') i++;
      row.add(cell.toString());
      cell.clear();
      rows.add(row);
      row = <String>[];
    } else {
      cell.write(ch);
    }
  }
  if (cell.isNotEmpty || row.isNotEmpty) {
    row.add(cell.toString());
    rows.add(row);
  }
  return rows;
}

class CsvTableView extends StatelessWidget {
  final String csv;

  /// The file name used by "Save as CSV".
  final String fileName;
  final String? title;
  const CsvTableView({super.key, required this.csv, required this.fileName, this.title});

  @override
  Widget build(BuildContext context) {
    final rows = parseCsv(csv);
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final width = rows.fold(0, (n, r) => r.length > n ? r.length : n);
    final dataRows = rows.length > 1 ? rows.length - 1 : 0;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
            child: Row(children: [
              const IconBadge(Icons.table_chart_outlined, size: 34),
              const SizedBox(width: 12),
              Expanded(child: Text(title ?? '$dataRows row(s)', style: theme.textTheme.titleMedium)),
              if (title != null) ...[StatusChip('$dataRows', icon: Icons.table_rows_outlined), const SizedBox(width: 8)],
              FilledButton.tonalIcon(
                icon: const Icon(Icons.download),
                label: const Text('Save as CSV'),
                onPressed: () async {
                  final path = await runAction(context, () => saveTextExport(fileName, csv), where: 'CsvTableView');
                  if (path != null && context.mounted) await showSaved(context, path);
                },
              ),
            ]),
          ),
          if (rows.isEmpty)
            const EmptyNote('Nothing to show.', icon: Icons.table_rows_outlined)
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingRowColor: WidgetStatePropertyAll(colors.surfaceContainerHigh),
                dataRowMinHeight: 36,
                dataRowMaxHeight: 52,
                columnSpacing: 20,
                columns: [
                  for (var i = 0; i < width; i++) DataColumn(label: Text(i < rows.first.length ? rows.first[i] : '')),
                ],
                rows: [
                  for (var n = 1; n < rows.length; n++)
                    DataRow(
                      // Zebra rows.
                      color: WidgetStatePropertyAll(n.isOdd ? colors.surfaceContainerLowest : colors.surfaceContainerLow),
                      cells: [for (var i = 0; i < width; i++) DataCell(Text(i < rows[n].length ? rows[n][i] : ''))],
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
