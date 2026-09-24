import '../../../core/base/base_view_model.dart';
import '../../../core/utils/date_time_formatter.dart';
import '../../../data/models/attendance_log_model.dart';
import '../../../data/models/employee_model.dart';
import '../../../data/models/worker_model.dart';
import '../../../data/repositories/attendance_repository.dart';
import '../../../data/repositories/employee_repository.dart';
import '../../../data/repositories/supervisor_session_repository.dart';
import '../../../data/repositories/task_completion_sync_repository.dart';
import '../../../data/repositories/task_sync_repository.dart';
import '../../../data/repositories/worker_attendance_repository.dart';
import '../../../data/repositories/worker_import_repository.dart';
import '../../../data/repositories/worker_sync_repository.dart';

/// Builds today's worker list by pairing every enrolled employee with their
/// first attendance log of the day.
class WorkerListViewModel extends BaseViewModel {
  final EmployeeRepository _employees;
  final AttendanceRepository _attendance;
  final WorkerSyncRepository _sync;
  final WorkerImportRepository _import;
  final TaskSyncRepository _taskSync;
  final SupervisorSessionRepository _session;
  final WorkerAttendanceRepository _workerAttendance;
  final TaskCompletionSyncRepository _taskCompletionSync;

  WorkerListViewModel({
    EmployeeRepository? employees,
    AttendanceRepository? attendance,
    WorkerSyncRepository? sync,
    WorkerImportRepository? import,
    TaskSyncRepository? taskSync,
    SupervisorSessionRepository? session,
    WorkerAttendanceRepository? workerAttendance,
    TaskCompletionSyncRepository? taskCompletionSync,
  }) : _employees = employees ?? EmployeeRepository(),
       _attendance = attendance ?? AttendanceRepository(),
       _sync = sync ?? WorkerSyncRepository(),
       _import = import ?? WorkerImportRepository(),
       _taskSync = taskSync ?? TaskSyncRepository(),
       _session = session ?? SupervisorSessionRepository(),
       _workerAttendance = workerAttendance ?? WorkerAttendanceRepository(),
       _taskCompletionSync = taskCompletionSync ?? TaskCompletionSyncRepository();

  bool _isLoading = true;
  bool _isFetchingFromServer = false;
  final Set<String> _syncingIds = {};
  final Set<String> _syncingTaskIds = {};
  final Set<String> _syncingAttendanceIds = {};
  final Set<String> _syncingTaskCompletionIds = {};
  List<Worker> _workers = const [];
  String _query = '';
  AttendanceStatus? _attendanceFilter;
  int? _supervisorDepartmentId;

  bool get isLoading => _isLoading;
  bool get isFetchingFromServer => _isFetchingFromServer;
  AttendanceStatus? get attendanceFilter => _attendanceFilter;

  /// A worker's task actions (Assign/View/Sync Task) only show when
  /// they're approved *and* in the supervisor's own department — both
  /// conditions, not just status, per the gating rule this drives.
  /// Fails closed: if the supervisor's own department couldn't be
  /// determined (see SupervisorSessionRepository.getSupervisorDepartmentId),
  /// no worker's task actions show rather than guessing.
  bool canManageTasks(Worker worker) {
    if (worker.status != 'approved') return false;
    final supervisorDepartmentId = _supervisorDepartmentId;
    if (supervisorDepartmentId == null) return false;
    return worker.departmentId == supervisorDepartmentId;
  }

  /// Whether [employeeId]'s worker is mid-sync — drives that card's sync
  /// button.
  bool isSyncing(String employeeId) => _syncingIds.contains(employeeId);

  /// Whether [employeeId]'s tasks are mid-sync — drives that card's sync
  /// tasks button.
  bool isSyncingTasks(String employeeId) => _syncingTaskIds.contains(employeeId);

  /// Whether [employeeId]'s attendance is mid-sync — drives that card's
  /// attendance sync button.
  bool isSyncingAttendance(String employeeId) =>
      _syncingAttendanceIds.contains(employeeId);

  /// Whether [employeeId]'s task completions are mid-sync — drives that
  /// card's Sync Task Completion button.
  bool isSyncingTaskCompletion(String employeeId) =>
      _syncingTaskCompletionIds.contains(employeeId);

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

  /// The full record for [employeeId] — the worker list only keeps the
  /// lighter [Worker] display DTO, so editing needs this to pre-fill the
  /// enrollment form's fields.
  Future<Employee?> getEmployee(String employeeId) =>
      _employees.findByEmployeeId(employeeId);

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

  /// Pushes [workerId]'s task assignments to the backend, one request per
  /// assignment (`POST attendance/assigntask`). Returns null (and throws)
  /// only if fetching the local assignments itself fails; otherwise
  /// returns a [TaskSyncResult] — per-assignment failures are captured
  /// there rather than thrown. Guards against a second tap on the same
  /// card while its sync is already running.
  Future<TaskSyncResult?> syncTasks(String employeeId, int workerId) async {
    if (_syncingTaskIds.contains(employeeId)) return null;
    _syncingTaskIds.add(employeeId);
    safeNotify();

    try {
      return await _taskSync.syncWorkerTasks(workerId);
    } finally {
      _syncingTaskIds.remove(employeeId);
      safeNotify();
    }
  }

  /// Pushes [employeeId]'s today's check-in/check-out record to the backend
  /// (`POST attendance/check-in`). Returns null on success, or an error
  /// message on failure. Guards against a second tap while already
  /// syncing.
  Future<String?> syncAttendance(String employeeId, int workerId) async {
    if (_syncingAttendanceIds.contains(employeeId)) return null;
    _syncingAttendanceIds.add(employeeId);
    safeNotify();

    String? error;
    try {
      await _workerAttendance.syncToday(workerId);
    } catch (e) {
      error = e.toString();
    }

    _syncingAttendanceIds.remove(employeeId);
    if (error == null) {
      await load();
    } else {
      safeNotify();
    }
    return error;
  }

  /// Pushes [employeeId]'s pending (Yes or No) task completions to the backend
  /// (`POST attendance/worker-task-completion`). Returns null (and throws)
  /// only if reading the local pending rows fails; otherwise returns a
  /// [TaskCompletionSyncResult] — per-completion failures are captured
  /// there rather than thrown. Guards against a second tap while already
  /// syncing.
  Future<TaskCompletionSyncResult?> syncTaskCompletion(
    String employeeId,
    int workerId,
  ) async {
    if (_syncingTaskCompletionIds.contains(employeeId)) return null;
    _syncingTaskCompletionIds.add(employeeId);
    safeNotify();

    try {
      return await _taskCompletionSync.syncWorkerTaskCompletions(workerId);
    } finally {
      _syncingTaskCompletionIds.remove(employeeId);
      safeNotify();
    }
  }

  /// Fetches the full worker roster from the backend and upserts it
  /// locally — existing workers matched by National ID are updated, new
  /// ones are inserted (see DatabaseHelper.upsertRemoteWorkers) — then
  /// reloads so the list reflects it. Returns how many were fetched; lets
  /// any failure propagate for the caller to surface.
  Future<int> fetchFromServer() async {
    if (_isFetchingFromServer) return 0;
    _isFetchingFromServer = true;
    safeNotify();
    try {
      final count = await _import.importFromRemote();
      await load();
      return count;
    } finally {
      _isFetchingFromServer = false;
      safeNotify();
    }
  }

  Future<void> load() async {
    _isLoading = true;
    safeNotify();

    final employees = await _employees.getUnique();
    final checkIns = await _firstCheckInsToday();
    final todayAttendance = await _workerAttendance.getTodayAttendanceByWorker();
    _supervisorDepartmentId = await _session.getSupervisorDepartmentId();

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
          workerId: employee.id,
          departmentId: employee.departmentId,
          status: employee.status,
          verification: _verificationFor(employee),
          hasCheckedInToday: todayAttendance[employee.id]?.hasCheckedIn ?? false,
          hasCheckedOutToday: todayAttendance[employee.id]?.hasCheckedOut ?? false,
          isAttendanceSynced: todayAttendance[employee.id]?.isSynced ?? false,
          hasRealAttendanceIdToday:
              todayAttendance[employee.id]?.realAttendanceId != null,
        ),
    ];

    _isLoading = false;
    safeNotify();
  }

  /// A worker with no confirmed server contact yet (never synced or
  /// imported) has nothing real to show, so stays "Not Verified" —
  /// otherwise this reflects the backend's actual approval status
  /// (Employee.status), which `upsertRemoteWorkers` (a full import) sets
  /// authoritatively; a worker only ever pushed via sync-worker (which
  /// returns no status) just keeps whatever it already had.
  VerificationStatus _verificationFor(Employee employee) {
    if (!employee.isSynced) return VerificationStatus.notVerified;
    return switch (employee.status) {
      'approved' => VerificationStatus.verified,
      'rejected' => VerificationStatus.rejected,
      _ => VerificationStatus.pending,
    };
  }

  /// Earliest log per employee for today, keyed by employee ID.
  Future<Map<String, DateTime>> _firstCheckInsToday() async {
    final today = DateTime.now();
    final logs = await _attendance.getAllLogs();
    final earliest = <String, DateTime>{};

    for (final AttendanceLog log in logs) {
      final loggedAt = DateTime.tryParse(log.loginTime);
      if (loggedAt == null || !DateTimeFormatter.isSameDay(loggedAt, today)) {
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
