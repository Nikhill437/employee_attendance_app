import 'package:flutter/material.dart';
import 'database_helper.dart';
import 'attendance_log_model.dart';

class AttendanceSummaryScreen extends StatefulWidget {
  const AttendanceSummaryScreen({super.key});

  @override
  State<AttendanceSummaryScreen> createState() =>
      _AttendanceSummaryScreenState();
}

class _AttendanceSummaryScreenState extends State<AttendanceSummaryScreen> {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  bool _isLoading = true;
  Map<String, List<AttendanceLog>> _grouped = {};

  @override
  void initState() {
    super.initState();
    _loadLogs();
  }

  Future<void> _loadLogs() async {
    final logs = await _dbHelper.getAllAttendanceLogs();
    final Map<String, List<AttendanceLog>> grouped = {};
    for (final log in logs) {
      grouped.putIfAbsent(log.employeeId, () => []).add(log);
    }
    setState(() {
      _grouped = grouped;
      _isLoading = false;
    });
  }

  String _formatDateTime(String isoString) {
    final dt = DateTime.parse(isoString);
    final date =
        '${dt.day.toString().padLeft(2, '0')}/'
        '${dt.month.toString().padLeft(2, '0')}/${dt.year}';
    final time =
        '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}';
    return '$date  •  $time';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Attendance Summary'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              setState(() => _isLoading = true);
              _loadLogs();
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _grouped.isEmpty
          ? const Center(child: Text('No attendance records yet'))
          : ListView(
              padding: const EdgeInsets.all(12),
              children: _grouped.entries.map((entry) {
                final logs = entry.value;
                final name = logs.first.employeeName;
                final employeeId = entry.key;

                return Card(
                  margin: const EdgeInsets.symmetric(vertical: 6),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
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
                    title: Text(
                      name,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      'ID: $employeeId  •  Total logins: ${logs.length}',
                    ),
                    children: logs.map((log) {
                      return ListTile(
                        dense: true,
                        leading: const Icon(Icons.access_time, size: 18),
                        title: Text(_formatDateTime(log.loginTime)),
                      );
                    }).toList(),
                  ),
                );
              }).toList(),
            ),
    );
  }
}
