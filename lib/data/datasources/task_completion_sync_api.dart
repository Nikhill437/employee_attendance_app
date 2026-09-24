import '../../core/network/api_client.dart';
import '../../core/network/api_routes.dart';
import '../models/task_completion_sync_model.dart';

/// Remote datasource for pushing one worker-task completion to the backend.
class TaskCompletionSyncApi {
  final ApiClient _client;

  TaskCompletionSyncApi({ApiClient? client}) : _client = client ?? ApiClient();

  /// POST attendance/worker-task-completion. Confirmed request body:
  /// `{"worker_task_id": ..., "attendance_id": ..., "completed_date": ...,
  /// "supervisor_id": ..., "worker_id": ..., "status": "yes"|"no"}` — one
  /// completion per call. [realWorkerTaskId]/[realAttendanceId]/
  /// [realWorkerId] must all be the backend's own real ids, not the local
  /// ones — the caller resolves each first (see
  /// TaskCompletionSyncRepository.syncWorkerTaskCompletions), since this
  /// completion can't be synced until its parent task assignment,
  /// attendance day, and worker all have one.
  ///
  /// Confirmed response on success: `{"message": ..., "completion_id":
  /// ..., "status": true}` — returns that `completion_id`, or null if the
  /// response doesn't have the expected shape.
  Future<int?> syncCompletion(
    TaskCompletionSyncRecord record, {
    required int realWorkerTaskId,
    required int realAttendanceId,
    required int realWorkerId,
  }) async {
    final response = await _client.post(
      ApiRoutes.workerTaskCompletion,
      data: {
        'worker_task_id': realWorkerTaskId,
        'attendance_id': realAttendanceId,
        'completed_date': _formatTimestamp(record.completedAt),
        'supervisor_id': record.supervisorId,
        'worker_id': realWorkerId,
        'status': record.status,
      },
    );
    return _extractId(response, 'completion_id');
  }

  int? _extractId(dynamic response, String key) {
    if (response is! Map) return null;
    final value = response[key];
    return value is int ? value : int.tryParse(value.toString());
  }

  /// The backend rejects the plain `yyyy-MM-dd HH:mm:ss` form ("completed_date
  /// must be a valid date") — it wants a real ISO-8601 UTC timestamp.
  /// `completed_at` is stored locally as `DateTime.now().toIso8601String()`
  /// (no offset, so it parses as local time); converting to UTC before
  /// formatting is what actually makes it unambiguous for the backend.
  String? _formatTimestamp(String? isoString) {
    if (isoString == null) return null;
    return DateTime.parse(isoString).toUtc().toIso8601String();
  }
}
