import '../../core/utils/app_time.dart';
import '../datasources/attendance_submission_api.dart';
import '../datasources/database_helper.dart';
import 'worker_sync_repository.dart';

/// Pushes one worker's today's attendance, its pending task completions,
/// and any not-yet-synced task assignments to the backend together
/// (`POST attendance/submit-attendance`), replacing separate calls to
/// `attendance/check-in`, `attendance/worker-task-completion`, and
/// `attendance/assigntask` for this flow.
class AttendanceSubmissionRepository {
  final DatabaseHelper _dbHelper;
  final AttendanceSubmissionApi _api;
  final WorkerSyncRepository _workerSync;

  AttendanceSubmissionRepository({
    DatabaseHelper? dbHelper,
    AttendanceSubmissionApi? api,
    WorkerSyncRepository? workerSync,
  }) : _dbHelper = dbHelper ?? DatabaseHelper(),
       _api = api ?? AttendanceSubmissionApi(),
       _workerSync = workerSync ?? WorkerSyncRepository();

  /// Every `worker_task` entry's fixed shape — this app doesn't track a
  /// real "assignment type" anywhere locally, so this is the only value
  /// ever sent.
  static const _defaultAssignmentType = 'default';

  /// Throws if there's no attendance recorded today for [workerId], if the
  /// worker can't be resolved to a real backend id (including if an
  /// automatic profile sync attempt fails), or lets the network call's
  /// failure propagate. Local rows are only marked synced after the API
  /// call succeeds AND the returned ids are written back successfully —
  /// a failure at any point leaves everything as "not synced" so a retry
  /// picks up right where it left off.
  Future<void> submitAttendance(String employeeId, int workerId) async {
    var realWorkerId = await _dbHelper.getRemoteWorkerId(workerId);
    if (realWorkerId == null) {
      // This call needs a real worker_id to send — sync the worker's own
      // profile first (same as tapping "Sync" used to do on its own).
      await _workerSync.syncWorker(employeeId);
      realWorkerId = await _dbHelper.getRemoteWorkerId(workerId);
      if (realWorkerId == null) {
        throw StateError('Could not resolve this worker\'s backend id');
      }
    }

    final attendance = await _dbHelper.getTodayAttendance(workerId);
    if (attendance == null) {
      throw StateError('No attendance recorded today for this worker');
    }

    // Every pending completion goes out — unlike the old per-completion
    // sync (TaskCompletionSyncRepository), this payload carries no
    // worker_task_id per entry, so there's no need to wait for the parent
    // assignment to have a real backend id first (that used to mean a
    // task assigned and completed in the same visit needed a second Sync
    // tap; not anymore, since its assignment goes out in the same call via
    // [workerTaskPayloads] below). `task_id` is included instead — the
    // task's own real id, available the moment tasks sync down from the
    // server, independent of whether this worker's assignment has synced.
    final pendingCompletions = await _dbHelper.getUnsyncedTaskCompletions(
      workerId,
    );
    final taskPayloads = <Map<String, dynamic>>[];
    for (final completion in pendingCompletions) {
      final taskId = await _dbHelper.getTaskIdForWorkerTask(
        completion.workerTaskId,
      );
      taskPayloads.add({
        'task_id': taskId,
        'completed_date': _formatTimestamp(completion.completedAt),
        'supervisor_id': completion.supervisorId,
        'worker_id': realWorkerId,
        'status': completion.status,
      });
    }

    // Task *assignments* not yet pushed to the backend at all — task_id is
    // already the backend's real id (tasks are synced down from the
    // server, never pushed up), so only the worker_task row itself needs
    // resolving, same as the (now-unused-here) TaskSyncRepository did.
    final pendingAssignments = await _dbHelper.getUnsyncedWorkerTasks(workerId);
    final workerTaskPayloads = pendingAssignments
        .map(
          (assignment) => {
            'worker_id': realWorkerId,
            'task_id': assignment.taskId,
            'status': assignment.status,
            'department_id': assignment.departmentId,
            'assignment_type': _defaultAssignmentType,
          },
        )
        .toList();

    final result = await _api.submit(
      attendance: {
        'worker_id': realWorkerId,
        'attendance_date': attendance.attendanceDate,
        'check_in_time': _formatTimestamp(attendance.checkInTime),
        'check_out_time': _formatTimestamp(attendance.checkOutTime),
        'check_in_face_verified': attendance.checkInFaceVerified ? 1 : 0,
        'check_out_face_verified': attendance.checkOutFaceVerified ? 1 : 0,
      },
      tasks: taskPayloads,
      workerTasks: workerTaskPayloads,
    );

    await _dbHelper.markWorkerAttendanceSynced(
      attendance.attendanceId,
      realAttendanceId: result.attendanceId,
    );
    // completion_ids is positional — matched back to pendingCompletions
    // (built in the same order taskPayloads was), since the response
    // carries no other correlation for those. Safe against a
    // shorter-than-sent (or empty/null) array: whichever wasn't returned
    // an id just stays unsynced for a retry.
    for (
      var i = 0;
      i < pendingCompletions.length && i < result.completionIds.length;
      i++
    ) {
      await _dbHelper.markWorkerTaskCompletionSynced(
        pendingCompletions[i].completionId,
        realCompletionId: result.completionIds[i],
      );
    }
    // worker_tasks, unlike completion_ids, is matched by task_id — the
    // response's own shape (see WorkerTaskSyncResult) — not by position,
    // so this doesn't depend on the backend preserving request order.
    final realWorkerTaskIdByTaskId = {
      for (final entry in result.workerTasks) entry.taskId: entry.workerTaskId,
    };
    for (final assignment in pendingAssignments) {
      final realWorkerTaskId = realWorkerTaskIdByTaskId[assignment.taskId];
      if (realWorkerTaskId == null) continue;
      await _dbHelper.markWorkerTaskSynced(
        assignment.workerTaskId,
        realWorkerTaskId,
      );
    }
    await _dbHelper.markWorkerSyncedById(workerId);
  }

  /// Same UTC conversion `WorkerAttendanceSyncApi`/`TaskCompletionSyncApi`
  /// already use — see either's doc comment for why plain `.toUtc()` would
  /// be wrong here.
  String? _formatTimestamp(String? isoString) {
    if (isoString == null) return null;
    return AppTime.userWallTimeToUtc(
      DateTime.parse(isoString),
    ).toIso8601String();
  }
}
