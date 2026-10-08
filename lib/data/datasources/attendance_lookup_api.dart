import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
import '../../core/network/api_routes.dart';
import '../models/department_model.dart';

/// Remote datasource for the reference lists (departments/tasks) an
/// enrollment picks from.
class AttendanceLookupApi {
  final ApiClient _client;

  AttendanceLookupApi({ApiClient? client}) : _client = client ?? ApiClient();

  /// POST attendance/searchDept, walking `page`/`totalPages` until
  /// exhausted — same pattern as [fetchTasks]/`WorkerListApi.fetchAll`.
  /// Confirmed response shape: `{"data": [{"department_id": 3,
  /// "department_name": "cleaning"}, ...]}`; a response with no
  /// `totalPages` (or a bare list, via [_asList]) is treated as a single
  /// page.
  Future<List<Department>> fetchDepartments({int limit = 100}) async {
    final results = <Department>[];
    var page = 1;

    while (true) {
      final data = await _client.post(
        '${ApiRoutes.listDepartments}?page=$page&limit=$limit',
      );
      results.addAll(_asList(data).map(Department.fromRemote));

      final totalPages = data is Map ? (data['totalPages'] as int? ?? 1) : 1;
      if (page >= totalPages) break;
      page++;
    }

    return results;
  }

  /// POST attendance/department_data, walking `page`/`totalPages` until
  /// exhausted — same pattern as [fetchDepartments], which this shares its
  /// response shape with (`{"data": [{"department_id": 1,
  /// "department_name": "maintainance", ...}, ...]}`), not the single
  /// object previously assumed here. [date] is the stored department
  /// server time (see LookupRepository). Errors propagate, so a failed
  /// call never advances that time.
  /// [onProgress], when given, is called after each page with how many
  /// rows have been fetched so far and the current/total page numbers —
  /// the dashboard's sync bottom sheet's source of real download progress
  /// for the Departments card, same as `WorkerListApi.fetchAll`.
  Future<List<Department>> fetchServertimeDepartment({
    required String date,
    int limit = 100,
    void Function(int fetchedSoFar, int currentPage, int totalPages)?
    onProgress,
  }) async {
    final results = <Department>[];
    var page = 1;

    while (true) {
      final data = await _client.post(
        '${ApiRoutes.serverTimeDepartment}?page=$page&limit=$limit',
        data: {'date': date},
      );
      if (data is! Map) {
        throw ApiException('Unexpected department response from the server.');
      }
      results.addAll(_asList(data).map(Department.fromRemote));

      final totalPages = data['totalPages'] as int? ?? 1;
      onProgress?.call(results.length, page, totalPages);
      if (page >= totalPages) break;
      page++;
    }

    return results;
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
        '${ApiRoutes.deptTasks}?page=$page&limit=$limit',
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

  /// POST attendance/task_data, walking `page`/`totalPages` until
  /// exhausted — same pattern as [fetchTasks]. Confirmed response shape:
  /// `{"success": true, "data": [{"task_id": ..., "department_id": ...,
  /// "task_name": ..., "isdefault": "yes" | null}, ...]}`. [date] is the
  /// stored task server time (see LookupRepository). Errors propagate, so
  /// a failed call never advances that time.
  /// [onProgress], when given, is called after each page the same way
  /// [fetchServertimeDepartment]'s is — the dashboard's sync bottom
  /// sheet's source of real download progress for the Tasks card.
  Future<List<Task>> fetchServertimeTask({
    required String date,
    int limit = 100,
    void Function(int fetchedSoFar, int currentPage, int totalPages)?
    onProgress,
  }) async {
    final results = <Task>[];
    var page = 1;

    while (true) {
      final data = await _client.post(
        '${ApiRoutes.serverTimeTasks}?page=$page&limit=$limit',
        data: {'date': date},
      );
      if (data is! Map || data['data'] is! List) {
        throw ApiException('Unexpected task response from the server.');
      }
      final rows = data['data'] as List;
      results.addAll(
        rows.map((row) => Task.fromRemote(row as Map<String, dynamic>)),
      );

      final totalPages = data['totalPages'] as int? ?? 1;
      onProgress?.call(results.length, page, totalPages);
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
