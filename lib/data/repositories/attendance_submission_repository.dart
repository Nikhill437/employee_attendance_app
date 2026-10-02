import '../../core/utils/app_time.dart';
import '../datasources/attendance_submission_api.dart';
import '../datasources/database_helper.dart';
import '../datasources/sync_data_api.dart';
import '../models/sync_data_result_model.dart';
import '../models/worker_task_model.dart';
import 'worker_sync_repository.dart';

/// Pushes one worker's today's attendance and any not-yet-synced task
/// assignments to the backend together
/// (`POST attendance/submit-attendance`), replacing separate calls to
/// `attendance/check-in` and `attendance/assigntask` for this flow.
class AttendanceSubmissionRepository {
  final DatabaseHelper _dbHelper;
  final AttendanceSubmissionApi _api;
  final SyncDataApi _syncDataApi;
  final WorkerSyncRepository _workerSync;

  AttendanceSubmissionRepository({
    DatabaseHelper? dbHelper,
    AttendanceSubmissionApi? api,
    SyncDataApi? syncDataApi,
    WorkerSyncRepository? workerSync,
  }) : _dbHelper = dbHelper ?? DatabaseHelper(),
       _api = api ?? AttendanceSubmissionApi(),
       _syncDataApi = syncDataApi ?? SyncDataApi(),
       _workerSync = workerSync ?? WorkerSyncRepository();

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

    // The task-status review feature (and its `worker_task_completion`
    // table) has been removed — there is nothing to populate this
    // endpoint's `task` array with, but the key is still sent (empty) to
    // keep the request shape the backend expects.
    const taskPayloads = <Map<String, dynamic>>[];

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
            'assignment_type': assignment.assignmentType,
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
    // worker_tasks, unlike completion_ids, is matched by task_id — the
    // response's own shape (see WorkerTaskSyncResult) — not by position,
    // so this doesn't depend on the backend preserving request order. This
    // endpoint only ever handles *today's* attendance, so a same-task_id
    // collision across several unsynced days (see [_matchWorkerTasks],
    // used by [submitAllUnsyncedAttendance] instead) isn't a concern here.
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

  /// An approved worker's "Sync"/"Not synced" tap — pushes every
  /// `worker_attendance` day not yet synced (not just today's, unlike
  /// [submitAttendance]) together with any pending task-assignment review
  /// (`POST attendance/sync-data`, multipart so a reviewed task's photo can
  /// go along with it). Throws if there's nothing unsynced to push, if the
  /// worker can't be resolved to a real backend id, or lets the network
  /// call's failure/an unsuccessful response propagate — exactly like
  /// [submitAttendance], nothing is marked synced until the response
  /// actually confirms it.
  Future<void> submitAllUnsyncedAttendance(
    String employeeId,
    int workerId,
  ) async {
    var realWorkerId = await _dbHelper.getRemoteWorkerId(workerId);
    if (realWorkerId == null) {
      await _workerSync.syncWorker(employeeId);
      realWorkerId = await _dbHelper.getRemoteWorkerId(workerId);
      if (realWorkerId == null) {
        throw StateError('Could not resolve this worker\'s backend id');
      }
    }

    final unsyncedAttendance = await _dbHelper.getUnsyncedAttendance(workerId);
    if (unsyncedAttendance.isEmpty) {
      throw StateError('No unsynced attendance recorded for this worker');
    }

    final pendingAssignments = await _dbHelper.getUnsyncedWorkerTasks(workerId);

    final result = await _syncDataApi.submit(
      attendance: unsyncedAttendance
          .map(
            (attendance) => {
              'worker_id': realWorkerId,
              'attendance_date': attendance.attendanceDate,
              'check_in_time': _formatTimestamp(attendance.checkInTime),
              'check_out_time': _formatTimestamp(attendance.checkOutTime),
              'check_in_face_verified': attendance.checkInFaceVerified ? 1 : 0,
              'check_out_face_verified': attendance.checkOutFaceVerified
                  ? 1
                  : 0,
            },
          )
          .toList(),
      workerTasks: pendingAssignments,
      realWorkerId: realWorkerId,
    );

    // Matched by (attendance_date) rather than position — the response's
    // own shape, same reasoning as submitAttendance's task_id matching for
    // worker_tasks below. Every row this call just submitted belongs to
    // this one worker, so the date alone is enough to disambiguate.
    final localByDate = {
      for (final attendance in unsyncedAttendance)
        attendance.attendanceDate: attendance,
    };
    for (final synced in result.attendances) {
      final local = localByDate[synced.attendanceDate];
      if (local == null) continue;
      await _dbHelper.markWorkerAttendanceSynced(
        local.attendanceId,
        realAttendanceId: synced.attendanceId,
      );
    }

    for (final match in _matchWorkerTasks(
      pendingAssignments,
      result.workerTasks,
    )) {
      await _dbHelper.markWorkerTaskSynced(
        match.key.workerTaskId,
        match.value.workerTaskId,
        realAttendanceId: match.value.attendanceId,
      );
    }

    await _dbHelper.markWorkerSyncedById(workerId);
  }

  /// Matches [SyncDataApi.submit]'s response `worker_tasks` entries back
  /// to the local rows that were actually submitted in [pending] — not by
  /// task_id alone, since each day now gets its own `worker_tasks` row, so
  /// a backlog sync can legitimately include several entries sharing the
  /// same task_id (one per unsynced day). Primarily matched by (task_id,
  /// task_date); falls back to matching by task_id alone — against
  /// whichever local row (oldest first, since [pending] already comes back
  /// in that order) hasn't been matched yet — for a response that doesn't
  /// echo task_date back, since that's not confirmed either way against a
  /// real backend yet.
  List<MapEntry<WorkerTask, SyncedWorkerTask>> _matchWorkerTasks(
    List<WorkerTask> pending,
    List<SyncedWorkerTask> synced,
  ) {
    final remaining = List<WorkerTask>.from(pending);
    final matches = <MapEntry<WorkerTask, SyncedWorkerTask>>[];

    for (final entry in synced) {
      WorkerTask? match;
      if (entry.taskDate != null) {
        for (final candidate in remaining) {
          if (candidate.taskId == entry.taskId &&
              candidate.taskDate == entry.taskDate) {
            match = candidate;
            break;
          }
        }
      }
      match ??= remaining.cast<WorkerTask?>().firstWhere(
        (candidate) => candidate!.taskId == entry.taskId,
        orElse: () => null,
      );
      if (match == null) continue;
      matches.add(MapEntry(match, entry));
      remaining.remove(match);
    }
    return matches;
  }

  /// Same UTC conversion `WorkerAttendanceSyncApi` already uses — see its
  /// doc comment for why plain `.toUtc()` would be wrong here.
  String? _formatTimestamp(String? isoString) {
    if (isoString == null) return null;
    return AppTime.userWallTimeToUtc(
      DateTime.parse(isoString),
    ).toIso8601String();
  }
}
