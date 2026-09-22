import '../../../core/base/base_view_model.dart';
import '../../../core/utils/date_time_formatter.dart';
import '../../../data/models/attendance_log_model.dart';
import '../../../data/models/worker_model.dart';
import '../../../data/repositories/attendance_repository.dart';
import '../../../data/repositories/employee_repository.dart';
import '../../../data/repositories/worker_sync_repository.dart';

/// Builds today's worker list by pairing every enrolled employee with their
/// first attendance log of the day.
class WorkerListViewModel extends BaseViewModel {
  final EmployeeRepository _employees;
  final AttendanceRepository _attendance;
  final WorkerSyncRepository _sync;

  WorkerListViewModel({
    EmployeeRepository? employees,
    AttendanceRepository? attendance,
    WorkerSyncRepository? sync,
  }) : _employees = employees ?? EmployeeRepository(),
       _attendance = attendance ?? AttendanceRepository(),
       _sync = sync ?? WorkerSyncRepository();

  bool _isLoading = true;
  final Set<String> _syncingIds = {};
  List<Worker> _workers = const [];
  String _query = '';
  AttendanceStatus? _attendanceFilter;

  bool get isLoading => _isLoading;
  AttendanceStatus? get attendanceFilter => _attendanceFilter;

  /// Whether [employeeId]'s worker is mid-sync — drives that card's sync
  /// button.
  bool isSyncing(String employeeId) => _syncingIds.contains(employeeId);

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

  /// Pushes [employeeId]'s worker record to the backend. Returns null on
  /// success, or an error message on failure. Guards against a second tap
  /// on the same card while its sync is already running.
  Future<String?> syncWorker(String employeeId) async {
    if (_syncingIds.contains(employeeId)) return null;
    _syncingIds.add(employeeId);
    safeNotify();

    String? error;
    try {
      await _sync.syncWorker(employeeId);
    } catch (e) {
      error = e.toString();
    }

    _syncingIds.remove(employeeId);
    if (error == null) {
      // Reload so this worker's card picks up the new synced/pending state.
      await load();
    } else {
      safeNotify();
    }
    return error;
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
          isSynced: employee.isSynced,
          // The sync response doesn't include an approval status, only that
          // the push succeeded — a synced worker sits at "Pending" until a
          // real approval feature exists to move it to "Verified".
          verification: employee.isSynced
              ? VerificationStatus.pending
              : VerificationStatus.notVerified,
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
