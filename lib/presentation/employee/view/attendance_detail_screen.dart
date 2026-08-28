import 'package:flutter/material.dart';
import 'employee_model.dart';

class AttendanceDetailScreen extends StatelessWidget {
  final Employee employee;

  const AttendanceDetailScreen({super.key, required this.employee});

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

  Widget _infoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Colors.grey.shade600, size: 22),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Attendance Details')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 44,
                    backgroundColor: Colors.green.shade50,
                    child: Icon(
                      employee.faceVerified
                          ? Icons.verified_user
                          : Icons.person,
                      size: 46,
                      color: Colors.green,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    employee.name,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        employee.faceVerified
                            ? Icons.check_circle
                            : Icons.cancel,
                        size: 16,
                        color: employee.faceVerified
                            ? Colors.green
                            : Colors.red,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        employee.faceVerified
                            ? 'Face Verified'
                            : 'Not Verified',
                        style: TextStyle(
                          color: employee.faceVerified
                              ? Colors.green
                              : Colors.red,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),
            Card(
              elevation: 1,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 6,
                ),
                child: Column(
                  children: [
                    _infoRow(Icons.badge, 'Employee ID', employee.employeeId),
                    const Divider(height: 1),
                    _infoRow(Icons.phone, 'Phone Number', employee.number),
                    const Divider(height: 1),
                    _infoRow(
                      Icons.access_time,
                      'Attendance Time',
                      _formatDateTime(employee.attendanceTime),
                    ),
                    if (employee.id != null) ...[
                      const Divider(height: 1),
                      _infoRow(Icons.tag, 'Record ID', employee.id.toString()),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 28),
            SizedBox(
              height: 50,
              child: ElevatedButton(
                onPressed: () =>
                    Navigator.of(context).popUntil((route) => route.isFirst),
                child: const Text(
                  'Back to Home',
                  style: TextStyle(fontSize: 16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
