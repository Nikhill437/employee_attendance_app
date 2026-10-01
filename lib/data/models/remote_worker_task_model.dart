/// One worker-task assignment row from the backend's
/// `POST attendance/worker_task_list` / `POST attendance/server_time_worker_task_list`
/// responses — both confirmed to return the same row shape (see
/// WorkerTaskListApi). Field names/envelope aren't confirmed yet (unlike
/// [RemoteWorkerRecord], whose shape is confirmed) — this mirrors the
/// local `worker_tasks` table's own column names as a best guess, same
/// precedent as every other not-yet-confirmed endpoint in this app;
/// adjust [fromJson] once the real response is seen.
class RemoteWorkerTaskRecord {
  /// The backend's own `worker_tasks.offline_worker_id`-equivalent id for
  /// this assignment — stored locally as `worker_tasks.worker_task_id`.
  final int? workerTaskId;

  /// The backend's real worker id (`workers.worker_id`) — resolved to the
  /// local `offline_worker_id` before this assignment is upserted (see
  /// DatabaseHelper.upsertRemoteWorkerTasks); a worker not yet known
  /// locally means this row is skipped rather than inserted as a
  /// dangling FK.
  final int workerId;

  /// The backend's own `tasks.task_id` — unlike [workerId], this is used
  /// as-is (tasks are synced down from the server, never generated
  /// locally, so this is already the right id to match against the
  /// local `tasks` table).
  final int taskId;

  final int? target;
  final String status;
  final String assignmentType;
  final String? assignedAt;
  final String? note;
  final String? workPhoto;
  final int? overtime;
  final int? employeeTarget;
  final int? completedTarget;
  final String? taskStatus;

  const RemoteWorkerTaskRecord({
    required this.workerTaskId,
    required this.workerId,
    required this.taskId,
    this.target,
    this.status = 'active',
    this.assignmentType = 'default',
    this.assignedAt,
    this.note,
    this.workPhoto,
    this.overtime,
    this.employeeTarget,
    this.completedTarget,
    this.taskStatus,
  });

  factory RemoteWorkerTaskRecord.fromJson(Map<String, dynamic> json) {
    return RemoteWorkerTaskRecord(
      workerTaskId: _asIntOrNull(json['worker_task_id'] ?? json['id']),
      workerId: _asInt(json['worker_id']),
      taskId: _asInt(json['task_id']),
      target: _asIntOrNull(json['target']),
      status: (json['status'] as String?) ?? 'active',
      assignmentType: (json['assignment_type'] as String?) ?? 'default',
      assignedAt: json['assigned_at'] as String?,
      note: json['note'] as String?,
      workPhoto: json['work_photo'] as String?,
      overtime: _asIntOrNull(json['overtime']),
      employeeTarget: _asIntOrNull(json['employee_target']),
      completedTarget: _asIntOrNull(json['completed_target']),
      taskStatus: json['task_status'] as String?,
    );
  }
}

int _asInt(dynamic value) {
  if (value is int) return value;
  if (value is String) return int.parse(value);
  throw FormatException('Expected an int id, got $value (${value.runtimeType})');
}

int? _asIntOrNull(dynamic value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is String) return int.tryParse(value);
  return null;
}
