import 'package:flutter/material.dart';

/// Renders an arbitrary set of SQL result rows as a scrollable data table.
///
/// Handles any column shape (dynamic SELECT/PRAGMA output) and scrolls both
/// horizontally (many columns) and vertically (many rows).
class QueryResultTable extends StatelessWidget {
  const QueryResultTable({
    super.key,
    required this.columns,
    required this.rows,
  });

  final List<String> columns;
  final List<Map<String, Object?>> rows;

  @override
  Widget build(BuildContext context) {
    if (columns.isEmpty || rows.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('No rows returned.'),
        ),
      );
    }

    return Scrollbar(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SingleChildScrollView(
          child: DataTable(
            columns: columns
                .map((c) => DataColumn(label: Text(c)))
                .toList(growable: false),
            rows: rows
                .map(
                  (row) => DataRow(
                    cells: columns
                        .map((c) => DataCell(_CellValue(value: row[c])))
                        .toList(growable: false),
                  ),
                )
                .toList(growable: false),
          ),
        ),
      ),
    );
  }
}

class _CellValue extends StatelessWidget {
  const _CellValue({required this.value});

  final Object? value;

  @override
  Widget build(BuildContext context) {
    if (value == null) {
      return Text(
        'NULL',
        style: TextStyle(
          fontStyle: FontStyle.italic,
          color: Theme.of(context).disabledColor,
        ),
      );
    }
    return Text(value.toString());
  }
}
