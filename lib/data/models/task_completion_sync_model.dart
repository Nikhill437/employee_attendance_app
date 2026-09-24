/// One `worker_task_completion` row not yet pushed to
/// `POST attendance/worker-task-completion` — see
/// DatabaseHelper.getUnsyncedTaskCompletions.
class TaskCompletionSyncRecord {
  final int completionId;
  final int workerTaskId;
  final int attendanceId;
  final int workerId;
  final int supervisorId;
  final String? completedAt;

  /// 'yes' or 'no' — the supervisor's Yes/No call on task_status_screen.dart.
  final String status;

  const TaskCompletionSyncRecord({
    required this.completionId,
    required this.workerTaskId,
    required this.attendanceId,
    required this.workerId,
    required this.supervisorId,
    required this.completedAt,
    required this.status,
  });

  factory TaskCompletionSyncRecord.fromMap(Map<String, dynamic> map) {
    return TaskCompletionSyncRecord(
      completionId: map['completion_id'] as int,
      workerTaskId: map['worker_task_id'] as int,
      attendanceId: map['attendance_id'] as int,
      workerId: map['worker_id'] as int,
      supervisorId: map['supervisor_id'] as int,
      completedAt: map['completed_at'] as String?,
      status: map['status'] as String,
    );
  }
}
