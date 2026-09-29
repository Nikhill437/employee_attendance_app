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
  /// Unlike [fetchTasks], this endpoint hasn't been observed paginating —
  /// every department has come back in one page so far.
  Future<List<Department>> fetchDepartments() async {
    final data = await _client.post(ApiRoutes.listDepartments);
    return _asList(data).map(Department.fromRemote).toList();
  }

  /// POST attendance/list_task, walking `page`/`totalPages` until
  /// exhausted — same pattern as `WorkerListApi.fetchAll`. Confirmed
  /// response shape: `{"data": [...], "totalPages": ..., "currentPage":
  /// ...}`, each item shaped like `{"task_id": ..., "department_id": ...,
  /// "task_name": ...}`. Confirmed paginated at 10/page server-side
  /// (e.g. 108 tasks across 11 pages) — a single unpaginated call only
  /// ever saw the first page, so most departments' tasks never made it
  /// into the local cache and their dropdowns looked empty.
  Future<List<Task>> fetchTasks({int limit = 100}) async {
    final results = <Task>[];
    var page = 1;

    while (true) {
      final data = await _client.post(
        '${ApiRoutes.listTasks}?page=$page&limit=$limit',
      );
      if (data is! Map || data['data'] is! List) break;
      final rows = data['data'] as List;
      results.addAll(
        rows.map((row) => Task.fromRemote(row as Map<String, dynamic>)),
      );

      final totalPages = data['totalPages'] as int? ?? 1;
      if (page >= totalPages) break;
      page++;
    }

    return results;
  }

  List<Map<String, dynamic>> _asList(dynamic data) {
    if (data is List) return data.cast<Map<String, dynamic>>();
    if (data is Map && data['data'] is List) {
      return (data['data'] as List).cast<Map<String, dynamic>>();
    }
    return const [];
  }
}
