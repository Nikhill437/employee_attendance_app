import '../datasources/database_helper.dart';
import '../models/employee_model.dart';

/// Employee enrollment records — the source of truth the view models talk to,
/// so no screen reaches into [DatabaseHelper] directly.
class EmployeeRepository {
  final DatabaseHelper _dbHelper;

  EmployeeRepository({DatabaseHelper? dbHelper})
    : _dbHelper = dbHelper ?? DatabaseHelper();

  /// Stores a new enrollment and returns it with its assigned row id.
  Future<Employee> create(Employee employee) async {
    final id = await _dbHelper.insertAttendance(employee);
    return employee.copyWith(id: id);
  }

  Future<List<Employee>> getAll() => _dbHelper.getAllAttendance();

  Future<List<Employee>> getUnique() => _dbHelper.getUniqueEmployees();

  /// The most recent enrollment record for [employeeId], or null if that ID
  /// has never been enrolled.
  Future<Employee?> findByEmployeeId(String employeeId) =>
      _dbHelper.getEmployeeByEmployeeId(employeeId);

  /// True if [employeeId] (the National ID) is already enrolled — checked
  /// before saving a new enrollment so two workers never share one ID.
  Future<bool> isEmployeeIdTaken(String employeeId) async {
    final existing = await findByEmployeeId(employeeId);
    return existing != null;
  }

  /// Removes [employeeId]'s enrollment record(s) and attendance history.
  Future<void> delete(String employeeId) =>
      _dbHelper.deleteEmployee(employeeId);
}
