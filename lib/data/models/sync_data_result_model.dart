/// One attendance day the backend confirmed as synced, from
/// `POST attendance/sync-data`'s `sync_data[].attendances[]` — matched back
/// to the local row that was submitted for it by [workerId] + [attendanceDate]
/// (the backend's response carries no local id to match on directly, see
/// AttendanceSubmissionRepository.submitAllUnsyncedAttendance).
class SyncedAttendance {
  final int attendanceId;
  final int workerId;
  final String attendanceDate;

  const SyncedAttendance({
    required this.attendanceId,
    required this.workerId,
    required this.attendanceDate,
  });

  static SyncedAttendance? fromJson(Map<String, dynamic> json) {
    final attendanceId = _asInt(json['attendance_id']);
    final workerId = _asInt(json['worker_id']);
    final attendanceDate = json['attendance_date'] as String?;
    if (attendanceId == null || workerId == null || attendanceDate == null) {
      return null;
    }
    return SyncedAttendance(
      attendanceId: attendanceId,
      workerId: workerId,
      attendanceDate: attendanceDate,
    );
  }
}

/// One task assignment the backend confirmed as synced, from
/// `POST attendance/sync-data`'s `sync_data[].worker_tasks[]` — matched
/// back to the local row that was submitted for it by [taskId] **and**
/// [taskDate] together, not [taskId] alone: each day now gets its own
/// `worker_tasks` row, so a backlog sync can legitimately include several
/// entries sharing the same task_id (one per unsynced day) — see
/// AttendanceSubmissionRepository.submitAllUnsyncedAttendance. Carries
/// along the [attendanceId] it was synced alongside so the local row can
/// store that too.
class SyncedWorkerTask {
  final int workerTaskId;
  final int taskId;
  final String? taskDate;
  final int? attendanceId;
  final String? createdAt;

  const SyncedWorkerTask({
    required this.workerTaskId,
    required this.taskId,
    this.taskDate,
    this.attendanceId,
    this.createdAt,
  });

  static SyncedWorkerTask? fromJson(Map<String, dynamic> json) {
    final workerTaskId = _asInt(json['worker_task_id']);
    final taskId = _asInt(json['task_id']);
    if (workerTaskId == null || taskId == null) return null;
    return SyncedWorkerTask(
      workerTaskId: workerTaskId,
      taskId: taskId,
      taskDate: json['task_date'] as String?,
      attendanceId: _asInt(json['attendance_id']),
      createdAt: json['created_at'] as String?,
    );
  }
}

/// The parsed result of `POST attendance/sync-data` — every confirmed
/// attendance day and task assignment across all of the response's
/// `sync_data` entries (the request only ever sends one, but this reads
/// safely regardless).
class SyncDataResult {
  final List<SyncedAttendance> attendances;
  final List<SyncedWorkerTask> workerTasks;

  const SyncDataResult({required this.attendances, required this.workerTasks});
}

int? _asInt(Object? value) {
  if (value is int) return value;
  if (value is String) return int.tryParse(value);
  return null;
}
