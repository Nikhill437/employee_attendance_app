/// One entry of the response's `worker_tasks` array — the real
/// `worker_task_id` the backend assigned to the task-assignment identified
/// by [taskId], so it can be matched back to the local `worker_tasks` row
/// by task id rather than by array position.
class WorkerTaskSyncResult {
  final int taskId;
  final int workerTaskId;

  const WorkerTaskSyncResult({
    required this.taskId,
    required this.workerTaskId,
  });
}

/// The backend's response to `POST attendance/submit-attendance` — the
/// attendance day's real id, one completion id per entry in the request's
/// `task` array (positional — the response carries no other correlation
/// for these), and the real id for each task assignment in the request's
/// `worker_task` array (matched by `task_id`, not position).
class AttendanceSubmissionResult {
  final int attendanceId;
  final List<int> completionIds;
  final List<WorkerTaskSyncResult> workerTasks;

  const AttendanceSubmissionResult({
    required this.attendanceId,
    required this.completionIds,
    required this.workerTasks,
  });
}
