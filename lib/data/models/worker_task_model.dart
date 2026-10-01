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

  /// The `worker_tasks` row's own status (e.g. 'active').
  final String status;

  /// 'default' (available to the worker every day) or 'temporary' (only
  /// for the day named by the row's `assigned_at` date) — see the
  /// `worker_tasks.assignment_type` column doc comment in DatabaseHelper.
  final String assignmentType;

  /// The worker's own checkout-time numeric reading for this task
  /// (`worker_tasks.employee_target`) — see assign_task_screen.dart's
  /// Worker Submission card. Null until they save one.
  final int? employeeTarget;

  /// Local file path of the photo captured for this task, copied into
  /// permanent app storage the same way
  /// EnrollmentFormViewModel.captureNationalIdImage does — set by either
  /// the worker's own submission or, if they captured a new one, the
  /// supervisor's review. Null until either saves one.
  final String? workPhoto;

  /// The supervisor's own numeric review of this task
  /// (`worker_tasks.completed_target`) — distinct from [employeeTarget].
  /// Null until the supervisor saves one.
  final int? completedTarget;

  /// The supervisor's note on this assignment (`worker_tasks.note`).
  final String? note;

  const WorkerTask({
    required this.workerTaskId,
    required this.workerId,
    required this.taskId,
    required this.taskName,
    required this.departmentId,
    required this.status,
    required this.assignmentType,
    this.employeeTarget,
    this.workPhoto,
    this.completedTarget,
    this.note,
  });

  factory WorkerTask.fromMap(Map<String, dynamic> map) {
    return WorkerTask(
      workerTaskId: map['worker_task_id'] as int,
      workerId: map['worker_id'] as int,
      taskId: map['task_id'] as int,
      taskName: map['task_name'] as String,
      departmentId: map['department_id'] as int,
      status: map['status'] as String? ?? 'active',
      assignmentType: map['assignment_type'] as String? ?? 'default',
      employeeTarget: map['employee_target'] as int?,
      workPhoto: map['work_photo'] as String?,
      completedTarget: map['completed_target'] as int?,
      note: map['note'] as String?,
    );
  }
}
