import 'dart:developer';

import '../datasources/database_helper.dart';
import '../datasources/task_completion_sync_api.dart';

/// How many of a worker's pending task completions a
/// [TaskCompletionSyncRepository.syncWorkerTaskCompletions] call pushed
/// successfully.
class TaskCompletionSyncResult {
  final int succeeded;
  final int total;

  const TaskCompletionSyncResult({required this.succeeded, required this.total});

  bool get hasFailures => succeeded < total;
}

/// Pushes a worker's task-completion rows (Yes or No) to the backend
/// (`POST attendance/worker-task-completion`), one request per row, skipping
/// whatever's already synced (`worker_task_completion.is_synced`).
class TaskCompletionSyncRepository {
  final DatabaseHelper _dbHelper;
  final TaskCompletionSyncApi _api;

  TaskCompletionSyncRepository({
    DatabaseHelper? dbHelper,
    TaskCompletionSyncApi? api,
  }) : _dbHelper = dbHelper ?? DatabaseHelper(),
       _api = api ?? TaskCompletionSyncApi();

  /// Syncs every unsynced completion for [workerId]. Each completion needs
  /// its parent task assignment, attendance day, and worker to already
  /// have a real backend id of their own (see DatabaseHelper.
  /// getRemoteWorkerTaskId/getRemoteAttendanceId/getRemoteWorkerId) —
  /// one that isn't synced yet is skipped and left for a later attempt,
  /// same as a completion whose own push fails.
  Future<TaskCompletionSyncResult> syncWorkerTaskCompletions(
    int workerId,
  ) async {
    final pending = await _dbHelper.getUnsyncedTaskCompletions(workerId);
    log(
      'syncWorkerTaskCompletions($workerId): ${pending.length} pending completion(s)',
    );
    var succeeded = 0;

    for (final record in pending) {
      final realWorkerId = await _dbHelper.getRemoteWorkerId(record.workerId);
      final realWorkerTaskId = await _dbHelper.getRemoteWorkerTaskId(
        record.workerTaskId,
      );
      final realAttendanceId = await _dbHelper.getRemoteAttendanceId(
        record.attendanceId,
      );
      if (realWorkerId == null ||
          realWorkerTaskId == null ||
          realAttendanceId == null) {
        // Nothing is posted for this one — the backend needs the real
        // worker/worker_task/attendance ids from their own sync calls
        // first, so this stays unsynced until those have run.
        log(
          'Skipping completion ${record.completionId}: missing real id — '
          'worker=$realWorkerId workerTask=$realWorkerTaskId '
          'attendance=$realAttendanceId (sync the worker/tasks/attendance '
          'first)',
        );
        continue;
      }

      try {
        final realCompletionId = await _api.syncCompletion(
          record,
          realWorkerTaskId: realWorkerTaskId,
          realAttendanceId: realAttendanceId,
          realWorkerId: realWorkerId,
        );
        await _dbHelper.markWorkerTaskCompletionSynced(
          record.completionId,
          realCompletionId: realCompletionId,
        );
        succeeded++;
      } catch (e) {
        // Left unsynced — retried on the next sync attempt.
        log('Failed to sync completion ${record.completionId}: $e');
      }
    }

    return TaskCompletionSyncResult(succeeded: succeeded, total: pending.length);
  }
}
