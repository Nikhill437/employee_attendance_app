import '../../../core/base/base_view_model.dart';
import '../../../core/utils/date_time_formatter.dart';
import '../../../data/models/attendance_log_model.dart';
import '../../../data/models/worker_model.dart';
import '../../../data/repositories/attendance_repository.dart';
import '../../../data/repositories/employee_repository.dart';

/// Builds today's worker list by pairing every enrolled employee with their
/// first attendance log of the day.
class WorkerListViewModel extends BaseViewModel {
  final EmployeeRepository _employees;
  final AttendanceRepository _attendance;

  WorkerListViewModel({
    EmployeeRepository? employees,
    AttendanceRepository? attendance,
  }) : _employees = employees ?? EmployeeRepository(),
       _attendance = attendance ?? AttendanceRepository();

  bool _isLoading = true;
  List<Worker> _workers = const [];
  String _query = '';
  AttendanceStatus? _attendanceFilter;

  bool get isLoading => _isLoading;
  AttendanceStatus? get attendanceFilter => _attendanceFilter;

  /// The list after the current search term and attendance filter.
  List<Worker> get workers {
    final term = _query.toLowerCase();
    return _workers.where((worker) {
      final matchesFilter =
          _attendanceFilter == null || worker.attendance == _attendanceFilter;
      final matchesTerm =
          term.isEmpty ||
          worker.name.toLowerCase().contains(term) ||
          worker.employeeId.toLowerCase().contains(term);
      return matchesFilter && matchesTerm;
    }).toList();
  }

  int get total => workers.length;
  int get presentCount => workers.where((w) => w.isPresent).length;
  int get absentCount => total - presentCount;

  void search(String query) {
    _query = query.trim();
    safeNotify();
  }

  /// Null shows everyone; otherwise only workers with that attendance.
  void filterByAttendance(AttendanceStatus? status) {
    _attendanceFilter = status;
    safeNotify();
  }

  /// Deletes [employeeId] and refreshes the roster. Callers are expected to
  /// confirm with the user first — this performs the deletion outright.
  Future<void> deleteWorker(String employeeId) async {
    await _employees.delete(employeeId);
    await load();
  }

  Future<void> load() async {
    _isLoading = true;
    safeNotify();

    final employees = await _employees.getUnique();
    final checkIns = await _firstCheckInsToday();

    _workers = [
      for (final employee in employees)
        Worker(
          name: employee.name,
          employeeId: employee.employeeId,
          payType: employee.payType,
          department: employee.department,
          checkInAt: checkIns[employee.employeeId],
          attendance: checkIns.containsKey(employee.employeeId)
              ? AttendanceStatus.present
              : AttendanceStatus.absent,
        ),
    ];

    _isLoading = false;
    safeNotify();
  }

  /// Earliest log per employee for today, keyed by employee ID.
  Future<Map<String, DateTime>> _firstCheckInsToday() async {
    final today = DateTime.now();
    final logs = await _attendance.getAllLogs();
    final earliest = <String, DateTime>{};

    for (final AttendanceLog log in logs) {
      final loggedAt = DateTime.tryParse(log.loginTime);
      if (loggedAt == null ||
          !DateTimeFormatter.isSameDay(loggedAt, today)) {
        continue;
      }
      final current = earliest[log.employeeId];
      if (current == null || loggedAt.isBefore(current)) {
        earliest[log.employeeId] = loggedAt;
      }
    }
    return earliest;
  }
}
