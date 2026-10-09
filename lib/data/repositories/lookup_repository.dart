import '../../core/utils/app_time.dart';
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
  /// a full fetch of every department (paginated, see
  /// AttendanceLookupApi.fetchDepartments). Saves the Department server
  /// time once the local write succeeds, so later department refreshes
  /// ask only for changes since this login.
  Future<int> syncDepartmentsFromRemote() async {
    final syncStartedAt = DateTime.now().toUtc().toIso8601String();
    final departments = await _api.fetchDepartments();
    await _dbHelper.replaceDepartments(departments);
    await lastDepartmentServerTime.save(syncStartedAt);
    return departments.length;
  }

  /// Refreshes just the local `tasks` cache the same way, paginated (see
  /// AttendanceLookupApi.fetchTasks). Saves the Task server time once the
  /// local write succeeds.
  Future<int> syncTasksFromRemote() async {
    final syncStartedAt = DateTime.now().toUtc().toIso8601String();
    final tasks = await _api.fetchTasks();
    await _dbHelper.replaceTasks(tasks);
    await lastTaskServerTime.save(syncStartedAt);
    return tasks.length;
  }

  /// The dashboard's "Check For New Data" action for departments. With no
  /// stored Department server time (never synced, or just cleared by
  /// [clearDepartments]) this pulls the full list the same way
  /// [syncDepartmentsFromRemote] does (see AttendanceLookupApi.
  /// fetchDepartments) — the initial-fetch behavior. Every later call sends
  /// the stored time to `POST attendance/department_data` (see
  /// AttendanceLookupApi.fetchServertimeDepartment) and upserts whichever
  /// departments the server reports changed into the existing cache rather
  /// than replacing it wholesale, so every other cached department is left
  /// untouched. The new time is saved only after the local write succeeds,
  /// so a failed fetch leaves it unchanged. Returns how many came back.
  Future<int> refreshDepartmentFromServerTime({
    void Function(int fetchedSoFar, int currentPage, int totalPages)?
    onProgress,
  }) async {
    final syncStartedAt = DateTime.now().toUtc().toIso8601String();
    final storedTime = await lastDepartmentServerTime.read();
    final departments = storedTime == null
        ? await _api.fetchDepartments()
        : await _api.fetchServertimeDepartment(
            date: storedTime,
            onProgress: onProgress,
          );
    if (departments.isNotEmpty) {
      await _dbHelper.replaceDepartments(departments);
    }
    // Saved only after the local write succeeded.
    await lastDepartmentServerTime.save(syncStartedAt);
    return departments.length;
  }

  /// The dashboard's "Check For New Data" action for tasks — same
  /// initial-fetch-then-incremental approach as
  /// [refreshDepartmentFromServerTime].
  Future<int> refreshTasksFromServerTime({
    void Function(int fetchedSoFar, int currentPage, int totalPages)?
    onProgress,
  }) async {
    final syncStartedAt = DateTime.now().toUtc().toIso8601String();
    final storedTime = await lastTaskServerTime.read();
    final tasks = storedTime == null
        ? await _api.fetchTasks()
        : await _api.fetchServertimeTask(
            date: storedTime,
            onProgress: onProgress,
          );
    await _dbHelper.replaceTasks(tasks);
    // Saved only after the local write succeeded.
    await lastTaskServerTime.save(syncStartedAt);
    return tasks.length;
  }

  /// The locally cached departments, for the enrollment form's dropdown.
  Future<List<Department>> getDepartments() => _dbHelper.getDepartments();

  /// How many departments/tasks are cached locally — the dashboard
  /// overview cards' total stat.
  Future<int> getDepartmentCount() => _dbHelper.getDepartmentCount();
  Future<int> getTaskCatalogCount() => _dbHelper.getTaskCatalogCount();

  /// The last successful department/task sync's start time, in the
  /// supervisor's own timezone (see AppTime) — null if none has run yet.
  Future<DateTime?> departmentsLastSyncedAt() async {
    final stored = await lastDepartmentServerTime.read();
    final parsed = stored == null ? null : DateTime.tryParse(stored);
    return parsed == null ? null : AppTime.toUserTime(parsed);
  }

  Future<DateTime?> tasksLastSyncedAt() async {
    final stored = await lastTaskServerTime.read();
    final parsed = stored == null ? null : DateTime.tryParse(stored);
    return parsed == null ? null : AppTime.toUserTime(parsed);
  }

  /// The Departments card's Clear action: wipes the local cache and resets
  /// its sync checkpoint, so the next [refreshDepartmentFromServerTime]
  /// call pulls the full list again (its initial-fetch behavior) instead
  /// of asking for changes since a stale time. Departments are pure
  /// server-reflected reference data, so nothing local is lost.
  Future<void> clearDepartments() async {
    await _dbHelper.clearDepartments();
    await lastDepartmentServerTime.clear();
  }

  /// The Tasks card's Clear action — same as [clearDepartments], for the
  /// local `tasks` catalog cache and its server-time checkpoint.
  Future<void> clearTaskCatalog() async {
    await _dbHelper.clearTaskCatalog();
    await lastTaskServerTime.clear();
  }
}
