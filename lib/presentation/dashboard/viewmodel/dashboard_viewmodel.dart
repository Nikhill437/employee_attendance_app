import '../../../core/base/base_view_model.dart';
import '../../../data/models/dashboard_summary_model.dart';
import '../../../data/models/employee_model.dart';
import '../../../data/repositories/attendance_repository.dart';
import '../../../data/repositories/employee_repository.dart';
import '../../../data/repositories/lookup_repository.dart';
import '../../../data/repositories/worker_import_repository.dart';

/// Loads the supervisor dashboard figures.
class DashboardViewModel extends BaseViewModel {
  final EmployeeRepository _employees;
  final AttendanceRepository _attendance;
  final WorkerImportRepository _workerImport;
  final LookupRepository _lookup;

  DashboardViewModel({
    EmployeeRepository? employees,
    AttendanceRepository? attendance,
    WorkerImportRepository? workerImport,
    LookupRepository? lookup,
  }) : _employees = employees ?? EmployeeRepository(),
       _attendance = attendance ?? AttendanceRepository(),
       _workerImport = workerImport ?? WorkerImportRepository(),
       _lookup = lookup ?? LookupRepository();

  bool _isLoading = true;
  bool _isImportingWorkers = false;
  bool _isFetchingDepartments = false;
  bool _isFetchingTasks = false;
  DashboardSummary _summary = const DashboardSummary();
  List<Employee> _roster = const [];

  bool get isLoading => _isLoading;
  bool get isImportingWorkers => _isImportingWorkers;
  bool get isFetchingDepartments => _isFetchingDepartments;
  bool get isFetchingTasks => _isFetchingTasks;
  DashboardSummary get summary => _summary;

  /// Every enrolled employee, for the dashboard's employee list section.
  List<Employee> get roster => _roster;

  Future<void> load() async {
    _isLoading = true;
    safeNotify();

    final enrolled = await _employees.getUnique();
    final presentToday = await _attendance.countPresentOn(DateTime.now());

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

  /// Fetches the full worker roster from the backend
  /// (`POST attendance/list`), upserts it locally by National ID, and
  /// reloads so the dashboard reflects it. Returns how many workers were
  /// fetched; lets any failure propagate for the caller to surface.
  Future<int> importWorkersFromServer() async {
    _isImportingWorkers = true;
    safeNotify();
    try {
      final count = await _workerImport.importFromRemote();
      await load();
      return count;
    } finally {
      _isImportingWorkers = false;
      safeNotify();
    }
  }

  /// Refreshes the local `departments` cache from the backend
  /// (`POST attendance/searchDept`). Returns how many were fetched; lets
  /// any failure propagate for the caller to surface.
  Future<int> fetchDepartments() async {
    _isFetchingDepartments = true;
    safeNotify();
    try {
      return await _lookup.syncDepartmentsFromRemote();
    } finally {
      _isFetchingDepartments = false;
      safeNotify();
    }
  }

  /// Refreshes the local `tasks` cache from the backend
  /// (`POST attendance/list_task`). Returns how many were fetched; lets
  /// any failure propagate for the caller to surface.
  Future<int> fetchTasks() async {
    _isFetchingTasks = true;
    safeNotify();
    try {
      return await _lookup.syncTasksFromRemote();
    } finally {
      _isFetchingTasks = false;
      safeNotify();
    }
  }
}
