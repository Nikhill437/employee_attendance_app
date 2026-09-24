import '../../core/network/api_client.dart';
import '../../core/network/api_routes.dart';

/// Remote datasource for pushing one worker-task assignment to the backend.
class TaskSyncApi {
  final ApiClient _client;

  TaskSyncApi({ApiClient? client}) : _client = client ?? ApiClient();

  /// POST attendance/assigntask. Confirmed request body:
  /// `{"worker_id": ..., "task_id": ..., "department_id": ..., "status":
  /// ...}` — one assignment per call, so a worker with several assigned
  /// tasks needs one call per task (see TaskSyncRepository.syncWorkerTasks).
  /// [workerId] must be the backend's real worker_id, not the local one —
  /// the caller resolves that first (see
  /// TaskSyncRepository.syncWorkerTasks), since the backend needs to know
  /// which of its own workers this task belongs to.
  ///
  /// Confirmed response on success: `{"message": ..., "worker_task_id":
  /// ..., "status": true}` — returns that `worker_task_id`, or null if the
  /// response doesn't have the expected shape.
  Future<int?> syncAssignment({
    required int workerId,
    required int taskId,
    required int departmentId,
    required String status,
  }) async {
    final response = await _client.post(
      ApiRoutes.assignTask,
      data: {
        'worker_id': workerId,
        'task_id': taskId,
        'department_id': departmentId,
        'status': status,
      },
    );
    return _extractId(response, 'worker_task_id');
  }

  int? _extractId(dynamic response, String key) {
    if (response is! Map) return null;
    final value = response[key];
    return value is int ? value : int.tryParse(value.toString());
  }
}
