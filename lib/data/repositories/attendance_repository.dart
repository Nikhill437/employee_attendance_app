import '../../core/utils/date_time_formatter.dart';
import '../datasources/database_helper.dart';
import '../models/attendance_log_model.dart';

/// Attendance login events.
class AttendanceRepository {
  final DatabaseHelper _dbHelper;

  AttendanceRepository({DatabaseHelper? dbHelper})
    : _dbHelper = dbHelper ?? DatabaseHelper();

  Future<int> log(AttendanceLog log) => _dbHelper.insertAttendanceLog(log);

  Future<List<AttendanceLog>> getAllLogs() => _dbHelper.getAllAttendanceLogs();

  /// All logs keyed by employeeId, newest-first within each employee — the
  /// shape the summary screen lists.
  Future<Map<String, List<AttendanceLog>>> getLogsGroupedByEmployee() async {
    final logs = await getAllLogs();
    final grouped = <String, List<AttendanceLog>>{};
    for (final log in logs) {
      grouped.putIfAbsent(log.employeeId, () => []).add(log);
    }
    return grouped;
  }

  /// Distinct employees with at least one attendance log on [day].
  Future<int> countPresentOn(DateTime day) async {
    final logs = await getAllLogs();
    final present = <String>{};
    for (final log in logs) {
      final loggedAt = DateTime.tryParse(log.loginTime);
      if (loggedAt != null && DateTimeFormatter.isSameDay(loggedAt, day)) {
        present.add(log.employeeId);
      }
    }
    return present.length;
  }
}
