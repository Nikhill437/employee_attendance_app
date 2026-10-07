import '../../../core/base/base_view_model.dart';
import '../../../core/utils/app_time.dart';
import '../../../data/models/dashboard_summary_model.dart';
import '../../../data/models/employee_model.dart';
import '../../../data/models/updated_counts_model.dart';
import '../../../data/repositories/attendance_repository.dart';
import '../../../data/repositories/employee_repository.dart';
import '../../../data/repositories/lookup_repository.dart';
import '../../../data/repositories/updated_counts_repository.dart';
import '../../../data/repositories/dashboard_setup_store.dart';
import '../../../data/repositories/worker_attendance_repository.dart';
import '../../../data/repositories/worker_import_repository.dart';
import '../../../data/repositories/worker_task_import_repository.dart';

/// Loads the supervisor dashboard figures.
class DashboardViewModel extends BaseViewModel {
  final EmployeeRepository _employees;
  final AttendanceRepository _attendance;
  final WorkerImportRepository _workerImport;
  final WorkerTaskImportRepository _workerTaskImport;
  final WorkerAttendanceRepository _workerAttendance;
  final LookupRepository _lookup;
  final UpdatedCountsRepository _updatedCountsRepository;

  DashboardViewModel({
    EmployeeRepository? employees,
    AttendanceRepository? attendance,
    WorkerImportRepository? workerImport,
    WorkerTaskImportRepository? workerTaskImport,
    WorkerAttendanceRepository? workerAttendance,
    LookupRepository? lookup,
    UpdatedCountsRepository? updatedCountsRepository,
  }) : _employees = employees ?? EmployeeRepository(),
       _attendance = attendance ?? AttendanceRepository(),
       _workerImport = workerImport ?? WorkerImportRepository(),
       _workerTaskImport = workerTaskImport ?? WorkerTaskImportRepository(),
       _workerAttendance = workerAttendance ?? WorkerAttendanceRepository(),
       _lookup = lookup ?? LookupRepository(),
       _updatedCountsRepository =
           updatedCountsRepository ?? UpdatedCountsRepository();

  final DashboardSetupStore _setupStore = DashboardSetupStore();
  int _setupCompleted = 0;

  /// Whether the first-time setup button for [step] (1 Worker List, 2 Worker
  /// Tasks, 3 Employee Attendance) can be pressed. Until all three have
  /// succeeded, a step unlocks only once the one before it is done. After
  /// that, every button stays enabled.
  bool canRunSetupStep(int step) {
    if (_setupCompleted >= DashboardSetupStore.stepCount) return true;
    return _setupCompleted >= step - 1;
  }

  Future<void> _completeSetupStep(int step) async {
    await _setupStore.markCompleted(step);
    _setupCompleted = await _setupStore.completedSteps();
  }

  bool _isLoading = true;
  bool _isImportingWorkers = false;
  bool _isFetchingDepartments = false;
  bool _isFetchingTasks = false;
  bool _isFetchingWorkerTasks = false;
  bool _isFetchingAttendance = false;
  DashboardSummary _summary = const DashboardSummary();
  List<Employee> _roster = const [];
  UpdatedCounts _updatedCounts = UpdatedCounts.zero;

  bool get isLoading => _isLoading;
  bool get isImportingWorkers => _isImportingWorkers;
  bool get isFetchingDepartments => _isFetchingDepartments;
  bool get isFetchingTasks => _isFetchingTasks;
  bool get isFetchingWorkerTasks => _isFetchingWorkerTasks;
  bool get isFetchingAttendance => _isFetchingAttendance;
  DashboardSummary get summary => _summary;

  /// How many worker/department/task records the server reports as changed
  /// — the badges next to the dashboard's Fetch Workers/Departments/Tasks
  /// actions.
  UpdatedCounts get updatedCounts => _updatedCounts;

  /// Every enrolled employee, for the dashboard's employee list section.
  List<Employee> get roster => _roster;

  /// Whether the "pending sync" notice has been checked yet in this session
  /// (static, so it survives the dashboard being rebuilt on navigation).
  static bool _pendingSyncChecked = false;

  /// Set by the first [load] of a session when local data is waiting to
  /// sync. [takePendingSyncNotice] hands it out once.
  bool _pendingNoticeDue = false;

  /// Clears the once-per-session notice. Call on logout, so the next login
  /// gets the notice again.
  static void resetSessionNotices() => _pendingSyncChecked = false;

  /// True once, if the first load of this session found unsynced local data.
  bool takePendingSyncNotice() {
    final due = _pendingNoticeDue;
    _pendingNoticeDue = false;
    return due;
  }

  Future<void> load() async {
    _isLoading = true;
    safeNotify();
    _setupCompleted = await _setupStore.completedSteps();

    final enrolled = await _employees.getUnique();
    final presentToday = await _attendance.countPresentOn(
      AppTime.nowInUserZone(),
    );
    // Today's check-ins and check-outs, from the local worker_attendance rows.
    final todayAttendance = await _workerAttendance
        .getTodayAttendanceByWorker();
    _updatedCounts = await _updatedCountsRepository.fetchUpdatedCounts();

    if (!_pendingSyncChecked) {
      _pendingSyncChecked = true;
      _pendingNoticeDue = await _workerAttendance.hasUnsyncedData();
    }

    _roster = enrolled;
    _summary = DashboardSummary(
      totalEmployees: enrolled.length,
      presentToday: presentToday,
      checkedIn: todayAttendance.values.where((a) => a.hasCheckedIn).length,
      checkedOut: todayAttendance.values.where((a) => a.hasCheckedOut).length,
    );

    _isLoading = false;
    safeNotify();
  }

  /// Both "Sync Now" and "Sync Data" re-read local storage for now; there is
  /// no remote endpoint to push to.
  Future<void> sync() => load();

  /// The dashboard's "Fetch Workers" button: the very first tap (per
  /// device install) pulls the full roster (`POST attendance/list`); every
  /// tap after that only pulls what changed (`POST attendance/worker_data`)
  /// — see WorkerImportRepository.importWorkers. Upserts by National ID
  /// and reloads so the dashboard reflects it. Returns how many workers
  /// were fetched; lets any failure propagate for the caller to surface.
  Future<int> importWorkersFromServer() async {
    _isImportingWorkers = true;
    safeNotify();
    try {
      final count = await _workerImport.importWorkers();
      await _completeSetupStep(1);
      await load();
      return count;
    } finally {
      _isImportingWorkers = false;
      safeNotify();
    }
  }

  /// Refreshes the local `departments` cache from the backend
  /// (`POST attendance/department_data`) — the dashboard's "Refresh"
  /// button for departments. Returns how many were fetched; lets any
  /// failure propagate for the caller to surface.
  Future<int> fetchDepartments() async {
    _isFetchingDepartments = true;
    safeNotify();
    try {
      final count = await _lookup.refreshDepartmentFromServerTime();
      await _refreshUpdatedCounts();
      return count;
    } finally {
      _isFetchingDepartments = false;
      safeNotify();
    }
  }

  /// Refreshes the local `tasks` cache from the backend
  /// (`POST attendance/task_data`) — the dashboard's "Refresh" button for
  /// tasks. Returns how many were fetched; lets any failure propagate for
  /// the caller to surface.
  Future<int> fetchTasks() async {
    _isFetchingTasks = true;
    safeNotify();
    try {
      final count = await _lookup.refreshTasksFromServerTime();
      await _refreshUpdatedCounts();
      return count;
    } finally {
      _isFetchingTasks = false;
      safeNotify();
    }
  }

  /// The dashboard's "Attendance" button: pulls the department's check-ins
  /// and check-outs (`GET attendance/departmentwise_attendance`) into
  /// `worker_attendance`. Returns how many rows were stored; lets any failure
  /// propagate for the caller to surface.
  Future<int> fetchDepartmentAttendance() async {
    _isFetchingAttendance = true;
    safeNotify();
    try {
      final count = await _workerAttendance.importDepartmentAttendance();
      await _completeSetupStep(3);
      return count;
    } finally {
      _isFetchingAttendance = false;
      safeNotify();
    }
  }

  /// The dashboard's "Worker Tasks" button: the full list on the first tap,
  /// then only changes since the stored Worker Tasks time — see
  /// WorkerTaskImportRepository.importWorkerTasks. Returns how many were
  /// fetched; lets any failure propagate for the caller to surface.
  Future<int> fetchWorkerTasks() async {
    _isFetchingWorkerTasks = true;
    safeNotify();
    try {
      final count = await _workerTaskImport.importWorkerTasks();
      await _completeSetupStep(2);
      return count;
    } finally {
      _isFetchingWorkerTasks = false;
      safeNotify();
    }
  }

  /// Re-reads the updated-counts badge after a manual refresh/fetch action
  /// (see [fetchDepartments]/[fetchTasks]) — [importWorkersFromServer]
  /// already gets this for free via its own [load] call.
  Future<void> _refreshUpdatedCounts() async {
    _updatedCounts = await _updatedCountsRepository.fetchUpdatedCounts();
  }
}
