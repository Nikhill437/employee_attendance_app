/// Whether one assigned task was completed during one attendance day — a
/// `worker_task_completion` row (joined with `worker_tasks`/`tasks` for
/// display), or the not-yet-recorded default when no such row exists yet
/// for this (task, attendance day) pair (see
/// DatabaseHelper.getTaskCompletions, which LEFT JOINs so every assigned
/// task appears even before a status has ever been set).
class WorkerTaskCompletion {
  final int? completionId;
  final int workerTaskId;
  final int attendanceId;
  final int taskId;
  final String taskName;
  final bool isCompleted;

  const WorkerTaskCompletion({
    this.completionId,
    required this.workerTaskId,
    required this.attendanceId,
    required this.taskId,
    required this.taskName,
    required this.isCompleted,
  });

  /// [attendanceId] is passed in rather than read from the row because a
  /// LEFT JOIN miss (no completion recorded yet) has no
  /// `worker_task_completion.attendance_id` to read — every row in one
  /// query result shares the same attendance day regardless.
  factory WorkerTaskCompletion.fromMap(
    Map<String, dynamic> map, {
    required int attendanceId,
  }) {
    return WorkerTaskCompletion(
      completionId: map['completion_id'] as int?,
      workerTaskId: map['worker_task_id'] as int,
      attendanceId: attendanceId,
      taskId: map['task_id'] as int,
      taskName: map['task_name'] as String,
      isCompleted: map['status'] == 'yes',
    );
  }

  WorkerTaskCompletion copyWith({int? completionId, bool? isCompleted}) {
    return WorkerTaskCompletion(
      completionId: completionId ?? this.completionId,
      workerTaskId: workerTaskId,
      attendanceId: attendanceId,
      taskId: taskId,
      taskName: taskName,
      isCompleted: isCompleted ?? this.isCompleted,
    );
  }
}
