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

  /// GET attendance/department_assigned_tasks — the full, un-paginated list
  /// (`{"data": [...]}`).
  Future<List<RemoteWorkerTaskRecord>> workerTaskList() async {
    final data = await _client.get(ApiRoutes.workerTaskList);
    return _rows(data);
  }

  /// POST attendance/server_time_worker_task_list with [date] as the stored
  /// Worker Tasks server time (`{"date": ...}`), returning the rows changed
  /// since then.
  Future<List<RemoteWorkerTaskRecord>> serverWorkerTaskList({
    required String date,
  }) async {
    final data = await _client.post(
      ApiRoutes.serverWorkerTaskList,
      data: {'date': date},
    );
    return _rows(data);
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
