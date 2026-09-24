/// One task assigned to a worker — a `worker_tasks` row, joined with
/// `tasks` for its display name and department (see TaskRepository /
/// DatabaseHelper).
class WorkerTask {
  final int workerTaskId;
  final int workerId;
  final int taskId;
  final String taskName;

  /// The task's own department — not necessarily the worker's *current*
  /// department, since an assignment is fixed to whichever department was
  /// selected at the time (see AssignTaskViewModel). This is what's sent
  /// as `department_id` when syncing the assignment (see TaskSyncApi).
  final int departmentId;

  /// The `worker_tasks` row's own status (e.g. 'active') — distinct from
  /// [WorkerTaskCompletion]'s pending/completed, which tracks whether the
  /// task was actually done on a given attendance day.
  final String status;

  const WorkerTask({
    required this.workerTaskId,
    required this.workerId,
    required this.taskId,
    required this.taskName,
    required this.departmentId,
    required this.status,
  });

  factory WorkerTask.fromMap(Map<String, dynamic> map) {
    return WorkerTask(
      workerTaskId: map['worker_task_id'] as int,
      workerId: map['worker_id'] as int,
      taskId: map['task_id'] as int,
      taskName: map['task_name'] as String,
      departmentId: map['department_id'] as int,
      status: map['status'] as String? ?? 'active',
    );
  }
}
