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

  /// The supervisor's approve/reject/pending verdict on this assignment
  /// (`worker_tasks.task_status`) — distinct from [status] (whether the
  /// assignment itself is active/inactive). NOT NULL on the table, with a
  /// 'pending' default, so this is never actually null once read back.
  final String taskStatus;

  /// This assignment's own overtime allowance (`worker_tasks.overtime`) —
  /// distinct from the task catalog's own [Task]-level overtime, which
  /// describes the task in general. Null until something sets one.
  final int? overtime;

  /// When this row was first created (`worker_tasks.created_at`) — sent
  /// along with a pending assignment's sync-data payload, and read back
  /// from a synced assignment's response (see SyncedWorkerTask).
  final String? createdAt;

  /// The calendar day this row's daily record belongs to
  /// (`worker_tasks.task_date`) — see that column's doc comment in
  /// DatabaseHelper. Every row returned by [TaskRepository.getWorkerTasks]
  /// has this equal to today's date; a row from [getUnsyncedWorkerTasks]
  /// may be an older, not-yet-synced day.
  final String taskDate;

  /// The backend's own id for this assignment (`worker_tasks.worker_task_id`
  /// — not to be confused with [workerTaskId], which is this row's own
  /// *local* id) — null until this specific day's record has synced. Drives
  /// whether the Supervisor Review section for this day is locked
  /// read-only (see AssignTaskViewModel.isReviewLocked).
  final int? realWorkerTaskId;

  /// The task catalog's own daily quantity goal and hourly/piece rate
  /// (`tasks.target`/`tasks.rate`) — the same read-only, backend-defined
  /// values [Task.target]/[Task.rate] carry, joined in here so the
  /// Currently Assigned banner can show them without a second lookup.
  /// Null when the backend hasn't set one.
  final int? taskTarget;
  final int? taskRate;

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
    this.taskStatus = 'pending',
    this.overtime,
    this.createdAt,
    this.taskDate = '',
    this.realWorkerTaskId,
    this.taskTarget,
    this.taskRate,
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
      taskStatus: map['task_status'] as String? ?? 'pending',
      overtime: map['overtime'] as int?,
      createdAt: map['created_at'] as String?,
      taskDate: map['task_date'] as String? ?? '',
      realWorkerTaskId: map['real_worker_task_id'] as int?,
      taskTarget: map['task_target'] as int?,
      taskRate: map['task_rate'] as int?,
    );
  }
}
