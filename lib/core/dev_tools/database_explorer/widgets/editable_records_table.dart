import 'package:flutter/material.dart';

/// Renders table rows with an inline "Edit" action per row, backed by the
/// row's stable identifier (typically its SQLite `rowid`, under [rowIdKey]).
///
/// Only one row can be in edit mode at a time — the edit action on every
/// other row is disabled while [editingRowId] is set, so there's never a
/// risk of two simultaneous, overlapping edits.
class EditableRecordsTable extends StatelessWidget {
  const EditableRecordsTable({
    super.key,
    required this.columns,
    required this.rows,
    required this.rowIdKey,
    required this.editingRowId,
    required this.editControllers,
    required this.saving,
    required this.onEditStart,
    required this.onSave,
    required this.onCancel,
  });

  /// Display columns, in order. Excludes [rowIdKey].
  final List<String> columns;

  /// Row data; each row also carries its identifier under [rowIdKey].
  final List<Map<String, Object?>> rows;

  final String rowIdKey;

  /// The identifier of the row currently being edited, or null.
  final Object? editingRowId;

  /// Controllers for the row currently being edited, keyed by column name.
  final Map<String, TextEditingController> editControllers;

  final bool saving;
  final void Function(Map<String, Object?> row) onEditStart;
  final VoidCallback onSave;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return const Center(child: Text('No rows returned.'));
    }
    final theme = Theme.of(context);

    return Scrollbar(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SingleChildScrollView(
          child: DataTable(
            columnSpacing: 20,
            headingRowHeight: 40,
            dataRowMinHeight: 44,
            dataRowMaxHeight: 56,
            columns: [
              ...columns.map((c) => DataColumn(label: Text(c))),
              const DataColumn(label: Text('')),
            ],
            rows: rows.map((row) {
              final rowId = row[rowIdKey];
              final isEditing = editingRowId != null && rowId == editingRowId;
              return DataRow(
                color: isEditing
                    ? WidgetStateProperty.all(
                        theme.colorScheme.primaryContainer.withValues(
                          alpha: 0.35,
                        ),
                      )
                    : null,
                cells: [
                  ...columns.map((c) {
                    if (isEditing) {
                      return DataCell(
                        SizedBox(
                          width: 150,
                          child: TextField(
                            controller: editControllers[c],
                            style: theme.textTheme.bodyMedium,
                            decoration: const InputDecoration(
                              isDense: true,
                              isCollapsed: true,
                              contentPadding: EdgeInsets.symmetric(
                                vertical: 8,
                                horizontal: 8,
                              ),
                              border: OutlineInputBorder(),
                              hintText: 'NULL',
                            ),
                          ),
                        ),
                      );
                    }
                    final value = row[c];
                    return DataCell(
                      value == null
                          ? Text(
                              'NULL',
                              style: TextStyle(
                                fontStyle: FontStyle.italic,
                                color: theme.disabledColor,
                              ),
                            )
                          : Text(value.toString()),
                    );
                  }),
                  DataCell(
                    isEditing
                        ? Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (saving)
                                const Padding(
                                  padding: EdgeInsets.all(8),
                                  child: SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                                )
                              else
                                IconButton(
                                  icon: const Icon(Icons.check, size: 18),
                                  tooltip: 'Save',
                                  onPressed: onSave,
                                ),
                              IconButton(
                                icon: const Icon(Icons.close, size: 18),
                                tooltip: 'Cancel',
                                onPressed: saving ? null : onCancel,
                              ),
                            ],
                          )
                        : IconButton(
                            icon: const Icon(Icons.edit_outlined, size: 18),
                            tooltip: 'Edit row',
                            onPressed: editingRowId == null
                                ? () => onEditStart(row)
                                : null,
                          ),
                  ),
                ],
              );
            }).toList(growable: false),
          ),
        ),
      ),
    );
  }
}
