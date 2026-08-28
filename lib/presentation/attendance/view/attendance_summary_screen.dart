import 'package:flutter/material.dart';

import '../../../core/utils/date_time_formatter.dart';
import '../../../data/models/attendance_log_model.dart';
import '../viewmodel/attendance_summary_viewmodel.dart';

class AttendanceSummaryScreen extends StatefulWidget {
  const AttendanceSummaryScreen({super.key});

  @override
  State<AttendanceSummaryScreen> createState() =>
      _AttendanceSummaryScreenState();
}

class _AttendanceSummaryScreenState extends State<AttendanceSummaryScreen> {
  final AttendanceSummaryViewModel _viewModel = AttendanceSummaryViewModel();

  @override
  void initState() {
    super.initState();
    _viewModel.loadLogs();
  }

  @override
  void dispose() {
    _viewModel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Attendance Summary'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _viewModel.loadLogs,
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: _viewModel,
        builder: (context, _) {
          if (_viewModel.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (_viewModel.isEmpty) {
            return const Center(child: Text('No attendance records yet'));
          }
          return ListView(
            padding: const EdgeInsets.all(12),
            children: _viewModel.groupedLogs.entries
                .map((entry) => _buildEmployeeCard(entry.key, entry.value))
                .toList(),
          );
        },
      ),
    );
  }

  Widget _buildEmployeeCard(String employeeId, List<AttendanceLog> logs) {
    final name = logs.first.employeeName;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: ExpansionTile(
        leading: CircleAvatar(
          backgroundColor: Colors.green.shade50,
          child: Text(
            name.isNotEmpty ? name[0].toUpperCase() : '?',
            style: const TextStyle(
              color: Colors.green,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(
          'ID: $employeeId  •  Total logins: ${logs.length}',
        ),
        children: logs.map((log) {
          return ListTile(
            dense: true,
            leading: const Icon(Icons.access_time, size: 18),
            title: Text(DateTimeFormatter.format(log.loginTime)),
          );
        }).toList(),
      ),
    );
  }
}
