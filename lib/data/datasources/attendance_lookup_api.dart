import '../../core/network/api_client.dart';
import '../../core/network/api_routes.dart';
import '../models/department_model.dart';

/// Remote datasource for the reference lists (departments/tasks) an
/// enrollment picks from.
class AttendanceLookupApi {
  final ApiClient _client;

  AttendanceLookupApi({ApiClient? client}) : _client = client ?? ApiClient();

  /// POST attendance/searchDept. Confirmed response shape:
  /// `{"data": [{"department_id": 3, "department_name": "cleaning"}, ...]}`.
  Future<List<Department>> fetchDepartments() async {
    final data = await _client.post(ApiRoutes.listDepartments);
    return _asList(data).map(Department.fromRemote).toList();
  }

  /// POST attendance/list_task. Response shape not confirmed yet — this
  /// assumes the same `{"data": [...]}` envelope as departments, with each
  /// item shaped like `{"task_id": ..., "department_id": ..., "task_name":
  /// ...}`. Adjust once the real contract is confirmed (same way
  /// `fetchDepartments` was updated once `searchDept`'s real response and
  /// URL were confirmed).
  Future<List<Task>> fetchTasks() async {
    final data = await _client.post(ApiRoutes.listTasks);
    return _asList(data).map(Task.fromRemote).toList();
  }

  List<Map<String, dynamic>> _asList(dynamic data) {
    if (data is List) return data.cast<Map<String, dynamic>>();
    if (data is Map && data['data'] is List) {
      return (data['data'] as List).cast<Map<String, dynamic>>();
    }
    return const [];
  }
}
