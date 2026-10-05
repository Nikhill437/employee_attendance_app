import '../datasources/attendance_lookup_api.dart';
import '../datasources/database_helper.dart';
import '../models/department_model.dart';
import 'server_sync_time_store.dart';

/// Departments/tasks the enrollment form picks from — fetched from the
/// backend right after supervisor login (see SupervisorLoginViewModel) and
/// cached locally so enrollment keeps working off the last successful sync
/// even without a live connection.
class LookupRepository {
  final AttendanceLookupApi _api;
  final DatabaseHelper _dbHelper;

  LookupRepository({AttendanceLookupApi? api, DatabaseHelper? dbHelper})
    : _api = api ?? AttendanceLookupApi(),
      _dbHelper = dbHelper ?? DatabaseHelper();

  /// Replaces the local departments/tasks cache with the backend's current
  /// lists. Lets any failure propagate — the caller (login) decides whether
  /// a failed sync should be silent or surfaced.
  Future<void> syncFromRemote() async {
    await syncDepartmentsFromRemote();
    await syncTasksFromRemote();
  }

  /// Refreshes just the local `departments` cache — used right after
  /// supervisor login (see SupervisorLoginViewModel via [syncFromRemote]),
  /// a full unpaginated fetch of every department.
  Future<int> syncDepartmentsFromRemote() async {
    final departments = await _api.fetchDepartments();
    await _dbHelper.replaceDepartments(departments);
    return departments.length;
  }

  /// Refreshes just the local `tasks` cache the same way, paginated (see
  /// AttendanceLookupApi.fetchTasks).
  Future<int> syncTasksFromRemote() async {
    final tasks = await _api.fetchTasks();
    await _dbHelper.replaceTasks(tasks);
    return tasks.length;
  }

  /// The dashboard's "Refresh Departments" button
  /// (`POST attendance/department_data`) — upserts just the single
  /// department the server reports (see
  /// AttendanceLookupApi.fetch_servertime_department) into the existing
  /// cache rather than replacing it wholesale, so every other cached
  /// department is left untouched. Returns 1 if a department came back, 0
  /// if the server had nothing to report.
  Future<int> refreshDepartmentFromServerTime() async {
    final syncStartedAt = DateTime.now().toUtc().toIso8601String();
    final serverTime = await lastDepartmentServerTime.read() ?? syncStartedAt;
    final department = await _api.fetchServertimeDepartment(date: serverTime);
    if (department != null) {
      await _dbHelper.replaceDepartments([department]);
    }
    // Saved only after the local write succeeded.
    await lastDepartmentServerTime.save(syncStartedAt);
    return department == null ? 0 : 1;
  }

  /// The dashboard's "Refresh Tasks" button
  /// (`POST attendance/task_data`) — same upsert-in-place approach as
  /// [refreshDepartmentFromServerTime].
  Future<int> refreshTasksFromServerTime() async {
    final syncStartedAt = DateTime.now().toUtc().toIso8601String();
    final serverTime = await lastTaskServerTime.read() ?? syncStartedAt;
    final tasks = await _api.fetchServertimeTask(date: serverTime);
    await _dbHelper.replaceTasks(tasks);
    // Saved only after the local write succeeded.
    await lastTaskServerTime.save(syncStartedAt);
    return tasks.length;
  }

  /// The locally cached departments, for the enrollment form's dropdown.
  Future<List<Department>> getDepartments() => _dbHelper.getDepartments();
}
