import 'package:flutter/material.dart';

import '../database_explorer_service.dart';
import 'confirm_destructive_dialog.dart';
import 'query_result_table.dart';

/// SQL editor tab: free-form statement execution, results, and a
/// per-session history of recently run queries.
class SqlQueryView extends StatefulWidget {
  const SqlQueryView({super.key, required this.service});

  final DatabaseExplorerService service;

  @override
  State<SqlQueryView> createState() => _SqlQueryViewState();
}

class _SqlQueryViewState extends State<SqlQueryView> {
  final _controller = TextEditingController();
  final _history = <String>[];

  bool _running = false;
  QueryExecutionResult? _result;

  List<String> get _exampleQueries => [
    "SELECT name FROM sqlite_master WHERE type = 'table';",
    'SELECT * FROM sqlite_master LIMIT 20;',
    if (_tables.isNotEmpty) 'SELECT * FROM "${_tables.first}" LIMIT 50;',
  ];

  List<String> _tables = const [];

  @override
  void initState() {
    super.initState();
    widget.service.getTableNames().then((names) {
      if (mounted) setState(() => _tables = names);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    final sql = _controller.text.trim();
    if (sql.isEmpty || _running) return;

    if (widget.service.isDestructive(sql)) {
      final confirmed = await confirmDestructiveQuery(context, sql);
      if (!confirmed) return;
    }

    setState(() => _running = true);
    final result = await widget.service.executeQuery(sql);
    if (!mounted) return;
    setState(() {
      _result = result;
      _running = false;
      _history.remove(sql);
      _history.insert(0, sql);
      if (_history.length > 20) _history.removeLast();
    });
  }

  void _clear() {
    setState(() {
      _controller.clear();
      _result = null;
    });
  }

  void _useQuery(String sql) {
    setState(() => _controller.text = sql);
  }

  @override
  Widget build(BuildContext context) {
    final kind = widget.service.classify(_controller.text);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _KindBadge(kind: kind),
              const Spacer(),
              TextButton(onPressed: _clear, child: const Text('Clear')),
              const SizedBox(width: 8),
              FilledButton.icon(
                icon: _running
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.play_arrow),
                label: const Text('Execute'),
                onPressed: _running ? null : _run,
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _controller,
            maxLines: 6,
            minLines: 4,
            style: const TextStyle(fontFamily: 'monospace'),
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: 'SELECT * FROM my_table LIMIT 50;',
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: _exampleQueries
                .map(
                  (q) => ActionChip(
                    label: Text(
                      q.length > 40 ? '${q.substring(0, 40)}…' : q,
                    ),
                    onPressed: () => _useQuery(q),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 16),
          Expanded(child: _buildResult()),
          if (_history.isNotEmpty) _buildHistory(),
        ],
      ),
    );
  }

  Widget _buildResult() {
    if (_running) {
      return const Center(child: CircularProgressIndicator());
    }
    final result = _result;
    if (result == null) {
      return const Center(child: Text('Run a query to see results here.'));
    }
    if (!result.success) {
      return SingleChildScrollView(
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.errorContainer,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            result.errorMessage ?? 'Unknown error',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onErrorContainer,
            ),
          ),
        ),
      );
    }

    final meta = result.isSelect
        ? '${result.rows.length} row(s) · ${result.duration.inMilliseconds} ms'
        : '${result.affectedRows ?? 0} row(s) affected · '
              '${result.duration.inMilliseconds} ms';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.check_circle,
              size: 16,
              color: Colors.green.shade600,
            ),
            const SizedBox(width: 6),
            Text(meta, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
        const SizedBox(height: 8),
        if (result.isSelect)
          Expanded(
            child: QueryResultTable(
              columns: result.columns,
              rows: result.rows,
            ),
          ),
      ],
    );
  }

  Widget _buildHistory() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(),
        Text('Recent queries', style: Theme.of(context).textTheme.labelLarge),
        SizedBox(
          height: 120,
          child: ListView.builder(
            itemCount: _history.length,
            itemBuilder: (context, index) {
              final sql = _history[index];
              return ListTile(
                dense: true,
                title: Text(
                  sql,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontFamily: 'monospace'),
                ),
                onTap: () => _useQuery(sql),
                trailing: IconButton(
                  icon: const Icon(Icons.replay, size: 18),
                  tooltip: 'Load and run again',
                  onPressed: () {
                    _useQuery(sql);
                    _run();
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _KindBadge extends StatelessWidget {
  const _KindBadge({required this.kind});

  final QueryKind kind;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (kind) {
      QueryKind.select => ('READ-ONLY', Colors.green),
      QueryKind.write => ('MODIFIES DATA', Colors.orange),
      QueryKind.ddl => ('CHANGES SCHEMA', Colors.red),
      QueryKind.other => ('UNKNOWN', Colors.grey),
    };
    return Chip(
      label: Text(label, style: const TextStyle(fontSize: 11)),
      backgroundColor: color.withValues(alpha: 0.15),
      side: BorderSide(color: color),
      visualDensity: VisualDensity.compact,
    );
  }
}
