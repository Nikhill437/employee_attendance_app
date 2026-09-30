import '../../../core/base/base_view_model.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/utils/app_time.dart';
import '../../../core/utils/date_time_formatter.dart';
import '../../../core/utils/network_status.dart';
import '../../../data/models/attendance_log_model.dart';
import '../../../data/models/employee_model.dart';
import '../../../data/models/worker_model.dart';
import '../../../data/repositories/attendance_repository.dart';
import '../../../data/repositories/attendance_submission_repository.dart';
import '../../../data/repositories/employee_repository.dart';
import '../../../data/repositories/supervisor_session_repository.dart';
import '../../../data/repositories/task_completion_sync_repository.dart';
import '../../../data/repositories/task_repository.dart';
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
  final AttendanceSubmissionRepository _attendanceSubmission;
  final TaskRepository _tasks;

  WorkerListViewModel({
    EmployeeRepository? employees,
    AttendanceRepository? attendance,
    WorkerSyncRepository? sync,
    WorkerImportRepository? import,
    TaskSyncRepository? taskSync,
    SupervisorSessionRepository? session,
    WorkerAttendanceRepository? workerAttendance,
    TaskCompletionSyncRepository? taskCompletionSync,
    AttendanceSubmissionRepository? attendanceSubmission,
    TaskRepository? tasks,
  }) : _employees = employees ?? EmployeeRepository(),
       _attendance = attendance ?? AttendanceRepository(),
       _sync = sync ?? WorkerSyncRepository(),
       _import = import ?? WorkerImportRepository(),
       _taskSync = taskSync ?? TaskSyncRepository(),
       _session = session ?? SupervisorSessionRepository(),
       _workerAttendance = workerAttendance ?? WorkerAttendanceRepository(),
       _taskCompletionSync = taskCompletionSync ?? TaskCompletionSyncRepository(),
       _attendanceSubmission =
           attendanceSubmission ?? AttendanceSubmissionRepository(),
       _tasks = tasks ?? TaskRepository();

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

  /// Whether [worker] should still show in the list once its department
  /// change has actually reached the backend. A worker still pending sync
  /// stays visible regardless of department — that's exactly the "Not
  /// synced" state a supervisor needs to see and act on. Only once
  /// [Worker.isSynced] is true does a department mismatch hide it (moved
  /// out of the supervisor's department, confirmed server-side) — this
  /// only affects what this list shows, never the local `workers` row
  /// itself. Fails open (never hides) if either department can't be
  /// determined, rather than guessing.
  bool _matchesSupervisorDepartment(Worker worker) {
    if (!worker.isSynced) return true;
    final supervisorDepartmentId = _supervisorDepartmentId;
    if (supervisorDepartmentId == null) return true;
    if (worker.departmentId == null) return true;
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

  /// The list after the current search term, attendance filter, and
  /// department filter, with not-yet-synced workers surfaced above synced
  /// ones (stable within each group) — a worker needing a push to the
  /// backend shouldn't get buried under ones that don't.
  List<Worker> get workers {
    final term = _query.toLowerCase();
    final filtered = _workers.where((worker) {
      final matchesFilter =
          _attendanceFilter == null || worker.attendance == _attendanceFilter;
      final matchesTerm =
          term.isEmpty ||
          worker.name.toLowerCase().contains(term) ||
          worker.employeeId.toLowerCase().contains(term);
      return matchesFilter && matchesTerm && _matchesSupervisorDepartment(worker);
    });

    final notSynced = <Worker>[];
    final synced = <Worker>[];
    for (final worker in filtered) {
      (worker.isSynced ? synced : notSynced).add(worker);
    }
    return [...notSynced, ...synced];
  }

  int get total => workers.length;
  int get presentCount => workers.where((w) => w.isPresent).length;
  int get absentCount => total - presentCount;
  int get syncedCount => workers.where((w) => w.isSynced).length;
  int get notSyncedCount => total - syncedCount;

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

  /// Pushes [employeeId]'s data to the backend and returns null on success,
  /// or an error message on failure. Guards against a second tap on the
  /// same card while its sync is already running.
  ///
  /// If [workerId] has attendance recorded today, this pushes that day's
  /// attendance plus any pending task completions together
  /// (`POST attendance/submit-attendance`), syncing the worker's own
  /// profile first if it doesn't have a real backend id yet. Otherwise it
  /// falls back to the plain worker-profile sync
  /// (`POST attendance/sync-worker`) — there's nothing attendance-related
  /// to push yet.
  Future<String?> syncWorker(String employeeId, int? workerId) async {
    if (_syncingIds.contains(employeeId)) return null;
    _syncingIds.add(employeeId);
    safeNotify();

    String? error;
    if (!await NetworkStatus.isOnline()) {
      error = 'No internet connection. Please check your network and try again.';
    } else {
      try {
        final hasAttendanceToday =
            workerId != null &&
            await _workerAttendance.getTodayAttendance(workerId) != null;
        if (hasAttendanceToday) {
          await _attendanceSubmission.submitAttendance(employeeId, workerId);
        } else {
          await _sync.syncWorker(employeeId);
        }
      } catch (e) {
        error = ApiException.messageFor(e);
      }
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
      if (!await NetworkStatus.isOnline()) {
        throw const ApiException(
          'No internet connection. Please check your network and try again.',
        );
      }
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
    final assignedTaskWorkerIds = await _tasks.getWorkerIdsWithAssignedTasks();
    final pendingReviewWorkerIds = await _tasks.getWorkerIdsWithPendingTaskReview();
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
          syncedAt: employee.syncedAt,
          workerId: employee.id,
          departmentId: employee.departmentId,
          status: employee.status,
          verification: _verificationFor(employee),
          hasCheckedInToday: todayAttendance[employee.id]?.hasCheckedIn ?? false,
          hasCheckedOutToday: todayAttendance[employee.id]?.hasCheckedOut ?? false,
          isAttendanceSynced: todayAttendance[employee.id]?.isSynced ?? false,
          hasRealAttendanceIdToday:
              todayAttendance[employee.id]?.realAttendanceId != null,
          todayAttendanceId: todayAttendance[employee.id]?.attendanceId,
          hasAssignedTasks: assignedTaskWorkerIds.contains(employee.id),
          remoteEmployeeId: employee.remoteEmployeeId,
          taskStatusReviewCompleted: !pendingReviewWorkerIds.contains(employee.id),
        ),
    ];

    _isLoading = false;
    safeNotify();
  }

  /// Purely a sync-state indicator, not the approval workflow
  /// ([Employee.status], untouched — still what task-action gating and the
  /// worker report's status pill check): a worker imported from the server
  /// (`upsertRemoteWorkers` always sets `is_synced = 1`) or successfully
  /// pushed there (`WorkerSyncRepository.syncWorker`) is "Verified"; a
  /// worker enrolled locally and not yet synced — or edited since its last
  /// sync — is "Not Verified". Backed by the same persisted
  /// `workers.is_synced` column [Worker.isSynced] reads, so this doesn't
  /// drift or revert on a plain list refresh — only an actual sync (or an
  /// edit that flips `is_synced` back to 0 — see
  /// DatabaseHelper.markWorkerUnsynced) changes it.
  VerificationStatus _verificationFor(Employee employee) {
    return employee.isSynced
        ? VerificationStatus.verified
        : VerificationStatus.notVerified;
  }

  /// Earliest log per employee for today, keyed by employee ID.
  Future<Map<String, DateTime>> _firstCheckInsToday() async {
    final today = AppTime.nowInUserZone();
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
