import 'package:flutter/material.dart';

import '../database_explorer_service.dart';
import 'confirm_destructive_dialog.dart';
import 'editable_records_table.dart';
import 'query_result_table.dart';

/// Full-screen view of a single table: a compact SQL editor for running
/// ad-hoc queries against this database, and a paginated, inline-editable
/// view of the table's own rows below it.
class TableDataView extends StatefulWidget {
  const TableDataView({
    super.key,
    required this.service,
    required this.tableName,
  });

  final DatabaseExplorerService service;
  final String tableName;

  @override
  State<TableDataView> createState() => _TableDataViewState();
}

class _TableDataViewState extends State<TableDataView> {
  static const _pageSizeOptions = [25, 50, 100, 200];

  int _pageSize = 50;
  int _offset = 0;
  int _totalRows = 0;
  List<ColumnInfo> _columnInfos = const [];

  bool _loading = true;
  String? _loadError;

  // Whether this table supports rowid-based inline editing. Null until the
  // first load determines it (false for WITHOUT ROWID tables).
  bool? _rowIdSupported;

  List<String> _displayColumns = const [];
  List<Map<String, Object?>> _rows = const [];

  // Set when the inline SQL editor's last run was a SELECT — its results
  // replace the normal table view until the next refresh or table query.
  bool _showingCustomQuery = false;

  // Inline SQL editor state.
  final _sqlController = TextEditingController();
  bool _sqlRunning = false;
  String? _sqlError;
  String? _sqlStatus;

  // Row editing state — only one row editable at a time.
  Object? _editingRowId;
  Map<String, Object?>? _editingOriginalRow;
  final Map<String, TextEditingController> _editControllers = {};
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    widget.service.getTableColumns(widget.tableName).then((columns) {
      if (mounted) setState(() => _columnInfos = columns);
    });
    _loadPage();
  }

  @override
  void dispose() {
    _sqlController.dispose();
    for (final controller in _editControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  bool _looksLikeMissingRowId(String? error) {
    return error != null && error.toLowerCase().contains('rowid');
  }

  Future<void> _loadPage() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final total = await widget.service.getRowCount(widget.tableName);
      final maxOffset = total == 0 ? 0 : ((total - 1) ~/ _pageSize) * _pageSize;
      if (_offset > maxOffset) _offset = maxOffset;

      QueryExecutionResult page;
      if (_rowIdSupported == false) {
        page = await widget.service.getTableRows(
          widget.tableName,
          limit: _pageSize,
          offset: _offset,
        );
      } else {
        page = await widget.service.getTableRowsEditable(
          widget.tableName,
          limit: _pageSize,
          offset: _offset,
        );
        if (page.success) {
          _rowIdSupported = true;
        } else if (_looksLikeMissingRowId(page.errorMessage)) {
          _rowIdSupported = false;
          page = await widget.service.getTableRows(
            widget.tableName,
            limit: _pageSize,
            offset: _offset,
          );
        }
      }

      if (!mounted) return;
      setState(() {
        _totalRows = total;
        _showingCustomQuery = false;
        _displayColumns = page.columns
            .where((c) => c != DatabaseExplorerService.rowIdAlias)
            .toList();
        _rows = page.rows;
        _loadError = page.success ? null : page.errorMessage;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = e.toString();
        _loading = false;
      });
    }
  }

  void _goToOffset(int offset) {
    final maxOffset = _totalRows == 0
        ? 0
        : ((_totalRows - 1) ~/ _pageSize) * _pageSize;
    setState(() => _offset = offset.clamp(0, maxOffset));
    _loadPage();
  }

  Future<void> _runInlineQuery() async {
    final sql = _sqlController.text.trim();
    if (sql.isEmpty || _sqlRunning) return;

    if (widget.service.isDestructive(sql)) {
      final confirmed = await confirmDestructiveQuery(context, sql);
      if (!confirmed) return;
    }

    setState(() {
      _sqlRunning = true;
      _sqlError = null;
      _sqlStatus = null;
    });
    final result = await widget.service.executeQuery(sql);
    if (!mounted) return;

    if (!result.success) {
      setState(() {
        _sqlRunning = false;
        _sqlError = result.errorMessage;
      });
      return;
    }

    if (result.isSelect) {
      setState(() {
        _sqlRunning = false;
        _showingCustomQuery = true;
        _displayColumns = result.columns;
        _rows = result.rows;
        _sqlStatus =
            '${result.rows.length} row(s) · ${result.duration.inMilliseconds} ms';
      });
    } else {
      setState(() {
        _sqlRunning = false;
        _sqlStatus =
            '${result.affectedRows ?? 0} row(s) affected · '
            '${result.duration.inMilliseconds} ms';
      });
      await _loadPage();
    }
  }

  void _clearInlineEditor() {
    setState(() {
      _sqlController.clear();
      _sqlError = null;
      _sqlStatus = null;
    });
    if (_showingCustomQuery) _loadPage();
  }

  void _startEdit(Map<String, Object?> row) {
    for (final controller in _editControllers.values) {
      controller.dispose();
    }
    _editControllers.clear();
    for (final column in _displayColumns) {
      final value = row[column];
      _editControllers[column] = TextEditingController(
        text: value == null ? '' : value.toString(),
      );
    }
    setState(() {
      _editingRowId = row[DatabaseExplorerService.rowIdAlias];
      _editingOriginalRow = row;
    });
  }

  void _cancelEdit() {
    for (final controller in _editControllers.values) {
      controller.dispose();
    }
    setState(() {
      _editControllers.clear();
      _editingRowId = null;
      _editingOriginalRow = null;
    });
  }

  Future<void> _saveEdit() async {
    final originalRow = _editingOriginalRow;
    final rowId = _editingRowId;
    if (originalRow == null || rowId == null) return;

    final changes = <String, Object?>{};
    try {
      for (final column in _columnInfos) {
        final controller = _editControllers[column.name];
        if (controller == null) continue;
        final newValue = coerceEditedValue(controller.text, column);
        final originalValue = originalRow[column.name];
        if (newValue != originalValue) {
          changes[column.name] = newValue;
        }
      }
    } on FormatException catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
      return;
    }

    if (changes.isEmpty) {
      _cancelEdit();
      return;
    }

    setState(() => _saving = true);
    final result = await widget.service.updateRowByRowId(
      table: widget.tableName,
      rowId: rowId,
      changes: changes,
    );
    if (!mounted) return;

    if (!result.success) {
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Update failed: ${result.errorMessage}')),
      );
      return;
    }

    setState(() {
      _saving = false;
      _editingRowId = null;
      _editingOriginalRow = null;
      _editControllers.clear();
    });
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Row updated.')));
    await _loadPage();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.tableName),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _loading ? null : _loadPage,
          ),
        ],
      ),
      body: Column(
        children: [
          _buildToolbar(context),
          const Divider(height: 1),
          _buildInlineEditor(context),
          const Divider(height: 1),
          Expanded(child: _buildTableArea(context)),
        ],
      ),
    );
  }

  Widget _buildToolbar(BuildContext context) {
    final canGoBack = _offset > 0;
    final canGoForward = _offset + _pageSize < _totalRows;
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '${_columnInfos.length} columns · $_totalRows rows'
              '${_rowIdSupported == false ? ' · read-only (no rowid)' : ''}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          DropdownButtonHideUnderline(
            child: DropdownButton<int>(
              value: _pageSize,
              items: _pageSizeOptions
                  .map(
                    (size) => DropdownMenuItem(
                      value: size,
                      child: Text('$size / page'),
                    ),
                  )
                  .toList(),
              onChanged: (size) {
                if (size == null) return;
                setState(() {
                  _pageSize = size;
                  _offset = 0;
                });
                _loadPage();
              },
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_left),
            tooltip: 'Previous page',
            onPressed: canGoBack
                ? () => _goToOffset(_offset - _pageSize)
                : null,
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            tooltip: 'Next page',
            onPressed: canGoForward
                ? () => _goToOffset(_offset + _pageSize)
                : null,
          ),
        ],
      ),
    );
  }

  Widget _buildInlineEditor(BuildContext context) {
    final theme = Theme.of(context);
    final kind = widget.service.classify(_sqlController.text);
    final isDestructive = kind == QueryKind.write || kind == QueryKind.ddl;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.terminal,
                size: 16,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Text('SQL Query', style: theme.textTheme.labelLarge),
              const Spacer(),
              TextButton(
                onPressed: _clearInlineEditor,
                child: const Text('Clear'),
              ),
              const SizedBox(width: 4),
              FilledButton.icon(
                icon: _sqlRunning
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.play_arrow, size: 18),
                label: const Text('Execute'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: _sqlRunning ? null : _runInlineQuery,
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _sqlController,
            minLines: 2,
            maxLines: 4,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
            decoration: InputDecoration(
              isDense: true,
              border: const OutlineInputBorder(),
              hintText: 'SELECT * FROM "${widget.tableName}" LIMIT 50;',
            ),
            onChanged: (_) => setState(() {}),
          ),
          if (_sqlController.text.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(
                  isDestructive ? Icons.warning_amber : Icons.visibility,
                  size: 14,
                  color: isDestructive ? Colors.orange : Colors.green,
                ),
                const SizedBox(width: 4),
                Text(
                  isDestructive ? 'Modifies data' : 'Read-only',
                  style: theme.textTheme.labelSmall,
                ),
              ],
            ),
          ],
          if (_sqlError != null) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: theme.colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                _sqlError!,
                style: TextStyle(color: theme.colorScheme.onErrorContainer),
              ),
            ),
          ] else if (_sqlStatus != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.check_circle, size: 14, color: Colors.green.shade600),
                const SizedBox(width: 6),
                Text(_sqlStatus!, style: theme.textTheme.bodySmall),
                if (_showingCustomQuery) ...[
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: _loadPage,
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                    ),
                    child: const Text('Back to table view'),
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTableArea(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_loadError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Failed to load table: $_loadError',
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
      );
    }
    if (_rows.isEmpty) {
      return const Center(child: Text('No rows to display.'));
    }

    if (_showingCustomQuery || _rowIdSupported == false) {
      return QueryResultTable(columns: _displayColumns, rows: _rows);
    }

    return EditableRecordsTable(
      columns: _displayColumns,
      rows: _rows,
      rowIdKey: DatabaseExplorerService.rowIdAlias,
      editingRowId: _editingRowId,
      editControllers: _editControllers,
      saving: _saving,
      onEditStart: _startEdit,
      onSave: _saveEdit,
      onCancel: _cancelEdit,
    );
  }
}
