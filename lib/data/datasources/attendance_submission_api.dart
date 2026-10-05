import 'dart:developer';

import '../../core/network/api_client.dart';
import '../../core/network/api_routes.dart';
import '../models/attendance_submission_model.dart';

/// Remote datasource for pushing one day's attendance, its pending task
/// completions, and any not-yet-synced task assignments to the backend in
/// a single call.
class AttendanceSubmissionApi {
  final ApiClient _client;

  AttendanceSubmissionApi({ApiClient? client})
    : _client = client ?? ApiClient();

  /// POST attendance/submit-attendance. Request body:
  /// `{"attendance": {...}, "task": [...], "worker_task": [...]}` — see
  /// AttendanceSubmissionRepository.submitAttendance for how [attendance],
  /// [tasks], and [workerTasks] are built.
  ///
  /// Confirmed response: `{"success": true, "message": ..., "attendance_id":
  /// ..., "completion_ids": [...], "worker_tasks": [{"worker_id": ...,
  /// "task_id": ..., "worker_task_id": ...}, ...]}`. `completion_ids` is
  /// positional (matches [tasks], in order — the response carries no other
  /// correlation for those); `worker_tasks` is matched by `task_id`
  /// instead, not position (see WorkerTaskSyncResult).
  Future<AttendanceSubmissionResult> submit({
    required Map<String, dynamic> attendance,
    required List<Map<String, dynamic>> tasks,
    required List<Map<String, dynamic>> workerTasks,
  }) async {
    final requestBody = {
      'attendance': attendance,
      'task': tasks,
      'worker_task': workerTasks,
    };
    log(requestBody.toString(), name: 'AttendanceSubmissionApi.submit');

    final response = await _client.post(
      ApiRoutes.submitAttendance,
      data: requestBody,
    );
    if (response is! Map) {
      throw const FormatException(
        'Unexpected response from attendance/submit-attendance',
      );
    }

    final attendanceId = response['attendance_id'];
    if (attendanceId == null) {
      throw const FormatException(
        'attendance/submit-attendance response missing attendance_id',
      );
    }

    return AttendanceSubmissionResult(
      attendanceId: attendanceId is int
          ? attendanceId
          : int.parse(attendanceId.toString()),
      completionIds: _idList(response['completion_ids']),
      workerTasks: _workerTaskResults(response['worker_tasks']),
    );
  }

  /// Parses a response id array safely — an absent, null, or malformed
  /// field just yields an empty list rather than throwing.
  List<int> _idList(Object? raw) {
    if (raw is! List) return const [];
    return raw
        .map((id) => id is int ? id : int.tryParse(id.toString()))
        .whereType<int>()
        .toList();
  }

  /// Parses the `worker_tasks` response array into [WorkerTaskSyncResult]s,
  /// skipping any entry missing either id rather than throwing — same
  /// "fail safe, not loud" approach as [_idList].
  List<WorkerTaskSyncResult> _workerTaskResults(Object? raw) {
    if (raw is! List) return const [];
    final results = <WorkerTaskSyncResult>[];
    for (final entry in raw) {
      if (entry is! Map) continue;
      final taskId = entry['task_id'];
      final workerTaskId = entry['worker_task_id'];
      if (taskId == null || workerTaskId == null) continue;
      results.add(
        WorkerTaskSyncResult(
          taskId: taskId is int ? taskId : int.parse(taskId.toString()),
          workerTaskId: workerTaskId is int
              ? workerTaskId
              : int.parse(workerTaskId.toString()),
        ),
      );
    }
    return results;
  }
}
