import 'package:flutter/material.dart';

import 'database_explorer_service.dart';
import 'widgets/sql_query_view.dart';
import 'widgets/table_list_view.dart';

/// Developer tool: inspect tables and run ad-hoc SQL against whatever
/// database was registered via `DatabaseExplorerConfig.configure(...)`.
///
/// This screen is not wired into any navigation flow by default — push it
/// from your own entry point, e.g.:
///
/// ```dart
/// Navigator.of(context).push(
///   MaterialPageRoute(builder: (_) => const DatabaseExplorerScreen()),
/// );
/// ```
class DatabaseExplorerScreen extends StatefulWidget {
  const DatabaseExplorerScreen({super.key});

  @override
  State<DatabaseExplorerScreen> createState() =>
      _DatabaseExplorerScreenState();
}

class _DatabaseExplorerScreenState extends State<DatabaseExplorerScreen> {
  late final DatabaseExplorerService _service = DatabaseExplorerService();

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Database Explorer'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Tables', icon: Icon(Icons.table_chart_outlined)),
              Tab(text: 'SQL Query', icon: Icon(Icons.terminal)),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            TableListView(service: _service),
            SqlQueryView(service: _service),
          ],
        ),
      ),
    );
  }
}
