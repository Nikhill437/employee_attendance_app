import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
import '../../core/network/api_routes.dart';
import '../models/remote_worker_task_model.dart';

/// Remote datasource for the backend's worker-task assignment list, in two
/// endpoints with the same row shape (see RemoteWorkerTaskRecord):
/// [workerTaskList] returns the full list, and [serverWorkerTaskList] returns
/// only what changed since a stored server time. Errors propagate, so a
/// failed call never moves the stored time.
class WorkerTaskListApi {
  final ApiClient _client;

  WorkerTaskListApi({ApiClient? client}) : _client = client ?? ApiClient();

  /// GET attendance/department_assigned_tasks, walking `page`/`totalPages`
  /// until exhausted — same pattern as `WorkerListApi.fetchAll` (`{"data":
  /// [...]}`, a response with no `totalPages` treated as a single page).
  /// [onProgress], when given, is called after each page with how many
  /// rows have been fetched so far and the current/total page numbers —
  /// the dashboard's sync bottom sheet's source of real download progress
  /// for the Employee Tasks List card.
  Future<List<RemoteWorkerTaskRecord>> workerTaskList({
    int limit = 100,
    void Function(int fetchedSoFar, int currentPage, int totalPages)?
    onProgress,
  }) async {
    final results = <RemoteWorkerTaskRecord>[];
    var page = 1;

    while (true) {
      final data = await _client.get(
        '${ApiRoutes.workerTaskList}?page=$page&limit=$limit',
      );
      results.addAll(_rows(data));

      final totalPages = data is Map ? (data['totalPages'] as int? ?? 1) : 1;
      onProgress?.call(results.length, page, totalPages);
      if (page >= totalPages) break;
      page++;
    }

    return results;
  }

  /// POST attendance/server_time_worker_task_list with [date] as the stored
  /// Worker Tasks server time (`{"date": ...}`), returning the rows changed
  /// since then — same page-walking (and [onProgress]) as [workerTaskList].
  Future<List<RemoteWorkerTaskRecord>> serverWorkerTaskList({
    required String date,
    int limit = 100,
    void Function(int fetchedSoFar, int currentPage, int totalPages)?
    onProgress,
  }) async {
    final results = <RemoteWorkerTaskRecord>[];
    var page = 1;

    while (true) {
      final data = await _client.post(
        '${ApiRoutes.serverWorkerTaskList}?page=$page&limit=$limit',
        data: {'date': date},
      );
      results.addAll(_rows(data));

      final totalPages = data is Map ? (data['totalPages'] as int? ?? 1) : 1;
      onProgress?.call(results.length, page, totalPages);
      if (page >= totalPages) break;
      page++;
    }

    return results;
  }

  List<RemoteWorkerTaskRecord> _rows(dynamic data) {
    if (data is! Map || data['data'] is! List) {
      throw ApiException('Unexpected worker task response from the server.');
    }
    return (data['data'] as List)
        .map(
          (row) => RemoteWorkerTaskRecord.fromJson(row as Map<String, dynamic>),
        )
        .toList();
  }
}
