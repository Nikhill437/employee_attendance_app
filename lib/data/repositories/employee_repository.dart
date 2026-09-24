import '../datasources/database_helper.dart';
import '../models/employee_model.dart';

/// Employee enrollment records — the source of truth the view models talk to,
/// so no screen reaches into [DatabaseHelper] directly.
class EmployeeRepository {
  final DatabaseHelper _dbHelper;

  EmployeeRepository({DatabaseHelper? dbHelper})
    : _dbHelper = dbHelper ?? DatabaseHelper();

  /// Stores a new enrollment (in the `workers` table) and returns it with
  /// its assigned row id.
  Future<Employee> create(Employee employee) async {
    final id = await _dbHelper.insertWorkerRecord(employee);
    return employee.copyWith(id: id);
  }

  Future<List<Employee>> getAll() => _dbHelper.getAllWorkers();

  /// `national_id` is unique on the `workers` table, so this is just every
  /// worker — kept as a separate method name for the view models that ask
  /// for "the unique roster" explicitly.
  Future<List<Employee>> getUnique() => _dbHelper.getAllWorkers();

  /// The enrollment record for [employeeId] (their National ID), or null if
  /// that ID has never been enrolled.
  Future<Employee?> findByEmployeeId(String employeeId) =>
      _dbHelper.getWorkerByNationalId(employeeId);

  /// True if [employeeId] (the National ID) is already enrolled — checked
  /// before saving a new enrollment so two workers never share one ID.
  Future<bool> isEmployeeIdTaken(String employeeId) async {
    final existing = await findByEmployeeId(employeeId);
    return existing != null;
  }

  /// Removes [employeeId]'s worker record and attendance history.
  Future<void> delete(String employeeId) =>
      _dbHelper.deleteEmployee(employeeId);

  /// Marks [employeeId] as synced — call after a successful
  /// `POST attendance/sync-worker` (see WorkerSyncRepository).
  /// [realWorkerId] is the backend's own id from that response, when known.
  Future<void> markSynced(String employeeId, {int? realWorkerId}) =>
      _dbHelper.markWorkerSynced(employeeId, realWorkerId: realWorkerId);

  /// The backend's real id for the worker at local id [offlineWorkerId], or
  /// null if they haven't been synced or imported yet.
  Future<int?> getRemoteWorkerId(int offlineWorkerId) =>
      _dbHelper.getRemoteWorkerId(offlineWorkerId);

  /// Reassigns [workerId] (their local `offline_worker_id`) to
  /// [departmentId] — called from the Assign Task screen when the
  /// supervisor picks a different department than the worker's current one.
  Future<void> updateDepartment(int workerId, int departmentId) =>
      _dbHelper.updateWorkerDepartment(workerId, departmentId);
}
