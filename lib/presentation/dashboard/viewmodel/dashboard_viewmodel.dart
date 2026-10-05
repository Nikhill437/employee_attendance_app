import '../../../core/base/base_view_model.dart';
import '../../../core/utils/app_time.dart';
import '../../../data/models/dashboard_summary_model.dart';
import '../../../data/models/employee_model.dart';
import '../../../data/models/updated_counts_model.dart';
import '../../../data/repositories/attendance_repository.dart';
import '../../../data/repositories/employee_repository.dart';
import '../../../data/repositories/lookup_repository.dart';
import '../../../data/repositories/updated_counts_repository.dart';
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

  Future<void> load() async {
    _isLoading = true;
    safeNotify();

    final enrolled = await _employees.getUnique();
    final presentToday = await _attendance.countPresentOn(
      AppTime.nowInUserZone(),
    );
    _updatedCounts = await _updatedCountsRepository.fetchUpdatedCounts();

    _roster = enrolled;
    // Every stored log is a check-in — there is no check-out or offline sync
    // queue in the data layer yet, so those counters stay at their defaults
    // instead of being filled with placeholder numbers.
    _summary = DashboardSummary(
      totalEmployees: enrolled.length,
      presentToday: presentToday,
      checkedIn: presentToday,
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
      return await _workerAttendance.importDepartmentAttendance();
    } finally {
      _isFetchingAttendance = false;
      safeNotify();
    }
  }

  /// The dashboard's "Fetch Worker Tasks" button: always the full roster
  /// (`POST attendance/worker_task_list`, no pagination) — see
  /// WorkerTaskImportRepository.importFromRemote. Upserts into
  /// `worker_tasks` by (worker, task). Returns how many were fetched;
  /// lets any failure propagate for the caller to surface.
  Future<int> fetchWorkerTasks() async {
    _isFetchingWorkerTasks = true;
    safeNotify();
    try {
      return await _workerTaskImport.importFromRemote();
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
