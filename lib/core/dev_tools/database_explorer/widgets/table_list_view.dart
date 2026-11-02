import 'package:flutter/material.dart';

import '../database_explorer_service.dart';
import 'table_data_view.dart';

enum _SortMode { name, rowCount }

/// Overview tab: database summary, quick stats, search, and a sortable list
/// of tables with row counts.
class TableListView extends StatefulWidget {
  const TableListView({super.key, required this.service});

  final DatabaseExplorerService service;

  @override
  State<TableListView> createState() => _TableListViewState();
}

class _TableListViewState extends State<TableListView> {
  bool _loading = true;
  String? _error;
  List<DatabaseTableInfo> _tables = const [];

  final _searchController = TextEditingController();
  String _query = '';
  _SortMode _sortMode = _SortMode.name;
  bool _descending = false;

  static const _avatarPalette = [
    Color(0xFF6366F1),
    Color(0xFF0EA5E9),
    Color(0xFF14B8A6),
    Color(0xFFF59E0B),
    Color(0xFFEC4899),
  ];

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() => _query = _searchController.text.trim().toLowerCase());
    });
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final tables = await widget.service.getTableOverview();
      if (!mounted) return;
      setState(() {
        _tables = tables;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  List<DatabaseTableInfo> get _visibleTables {
    final filtered = _query.isEmpty
        ? _tables
        : _tables.where((t) => t.name.toLowerCase().contains(_query)).toList();
    final sorted = [...filtered]..sort((a, b) {
      final cmp = switch (_sortMode) {
        _SortMode.name => a.name.compareTo(b.name),
        _SortMode.rowCount => a.rowCount.compareTo(b.rowCount),
      };
      return _descending ? -cmp : cmp;
    });
    return sorted;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Failed to load schema: $_error',
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
      );
    }

    final theme = Theme.of(context);
    final totalRecords = _tables.fold<int>(0, (sum, t) => sum + t.rowCount);
    final largest = _tables.isEmpty
        ? null
        : _tables.reduce((a, b) => a.rowCount >= b.rowCount ? a : b);
    final visible = _visibleTables;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildHeader(theme),
          const SizedBox(height: 12),
          _buildStatRow(theme, totalRecords, largest),
          const SizedBox(height: 16),
          _buildSearchAndSort(theme),
          const SizedBox(height: 8),
          if (_tables.isEmpty)
            _buildEmptyState(theme, 'No tables found in this database.')
          else if (visible.isEmpty)
            _buildEmptyState(theme, 'No tables match "$_query".')
          else
            _buildTableList(theme, visible),
        ],
      ),
    );
  }

  Widget _buildHeader(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.4,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.storage_rounded, color: theme.colorScheme.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.service.databaseLabel,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  'SQLite database',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh schema',
            onPressed: _load,
          ),
        ],
      ),
    );
  }

  Widget _buildStatRow(
    ThemeData theme,
    int totalRecords,
    DatabaseTableInfo? largest,
  ) {
    return Row(
      children: [
        Expanded(
          child: _StatTile(
            icon: Icons.table_chart_outlined,
            label: 'Tables',
            value: '${_tables.length}',
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _StatTile(
            icon: Icons.view_list_rounded,
            label: 'Records',
            value: '$totalRecords',
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _StatTile(
            icon: Icons.leaderboard_rounded,
            label: 'Largest',
            value: largest == null ? '—' : largest.name,
            valueMaxLines: 1,
          ),
        ),
      ],
    );
  }

  Widget _buildSearchAndSort(ThemeData theme) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              isDense: true,
              prefixIcon: const Icon(Icons.search, size: 20),
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: _searchController.clear,
                    ),
              hintText: 'Search tables…',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        PopupMenuButton<_SortMode>(
          tooltip: 'Sort by',
          initialValue: _sortMode,
          onSelected: (mode) => setState(() => _sortMode = mode),
          itemBuilder: (context) => const [
            PopupMenuItem(value: _SortMode.name, child: Text('Sort by name')),
            PopupMenuItem(
              value: _SortMode.rowCount,
              child: Text('Sort by row count'),
            ),
          ],
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            decoration: BoxDecoration(
              border: Border.all(color: theme.colorScheme.outlineVariant),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.sort, size: 20),
          ),
        ),
        const SizedBox(width: 8),
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: theme.colorScheme.outlineVariant),
            borderRadius: BorderRadius.circular(10),
          ),
          child: IconButton(
            icon: Icon(
              _descending ? Icons.arrow_downward : Icons.arrow_upward,
              size: 20,
            ),
            tooltip: _descending ? 'Descending' : 'Ascending',
            onPressed: () => setState(() => _descending = !_descending),
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState(ThemeData theme, String message) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Column(
        children: [
          Icon(
            Icons.inbox_outlined,
            size: 40,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 12),
          Text(
            message,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildTableList(ThemeData theme, List<DatabaseTableInfo> tables) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (final (index, table) in tables.indexed) ...[
            if (index > 0) const Divider(height: 1),
            _TableRow(
              table: table,
              color: _avatarPalette[index % _avatarPalette.length],
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => TableDataView(
                    service: widget.service,
                    tableName: table.name,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.icon,
    required this.label,
    required this.value,
    this.valueMaxLines = 1,
  });

  final IconData icon;
  final String label;
  final String value;
  final int valueMaxLines;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: theme.colorScheme.primary),
          const SizedBox(height: 8),
          Text(
            value,
            maxLines: valueMaxLines,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _TableRow extends StatelessWidget {
  const _TableRow({
    required this.table,
    required this.color,
    required this.onTap,
  });

  final DatabaseTableInfo table;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(Icons.table_rows_outlined, size: 18, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                table.name,
                style: theme.textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '${table.rowCount} rows',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Icon(
              Icons.chevron_right,
              size: 20,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}
