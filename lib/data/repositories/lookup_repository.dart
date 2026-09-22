import '../datasources/attendance_lookup_api.dart';
import '../datasources/database_helper.dart';
import '../models/department_model.dart';

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
    final departments = await _api.fetchDepartments();
    await _dbHelper.replaceDepartments(departments);
    final tasks = await _api.fetchTasks();
    await _dbHelper.replaceTasks(tasks);
  }

  /// The locally cached departments, for the enrollment form's dropdown.
  Future<List<Department>> getDepartments() => _dbHelper.getDepartments();
}
