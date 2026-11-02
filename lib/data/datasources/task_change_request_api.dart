import '../../core/network/api_client.dart';
import '../../core/network/api_routes.dart';
import '../models/task_change_request_result_model.dart';

/// Remote datasource for submitting one task-change-request draft to the
/// backend.
class TaskChangeRequestApi {
  final ApiClient _client;

  TaskChangeRequestApi({ApiClient? client}) : _client = client ?? ApiClient();

  /// POST attendance/assigntask. Confirmed request body:
  /// `{"worker_id": ..., "department_id": ..., "division_id": ..., "tasks":
  /// [{"task_id": ..., "note": ...}]}` — one task per call, same as
  /// TaskSyncApi.syncAssignment's one-call-per-task shape, just wrapped in
  /// a single-element `tasks` array per this endpoint's own contract.
  /// [workerId] must be the backend's real worker_id, not the local one —
  /// the caller resolves that first (see TaskChangeRequestRepository.submit).
  /// The backend decides from here whether the new pricing group needs
  /// approval (`approval_required: true`, `status: "pending_approval"`,
  /// `data.request_id` set) or can be applied immediately (`status:
  /// "applied"`, no `request_id` — see TaskChangeRequestRepository.
  /// _localStatusFor).
  Future<TaskChangeRequestResult> assignTask({
    required int workerId,
    required int taskId,
    required int departmentId,
    required int divisionId,
    String? note,
  }) async {
    final response = await _client.post(
      ApiRoutes.assignTask,
      data: {
        'worker_id': workerId,
        'department_id': departmentId,
        'division_id': divisionId,
        'tasks': [
          {'task_id': taskId, 'note': note},
        ],
      },
    );
    return TaskChangeRequestResult.fromJson(response as Map<String, dynamic>);
  }
}
