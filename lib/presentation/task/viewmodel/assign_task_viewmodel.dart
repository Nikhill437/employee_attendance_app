import '../../../core/base/base_view_model.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/utils/network_status.dart';
import '../../../data/models/department_model.dart';
import '../../../data/models/worker_attendance_model.dart';
import '../../../data/models/worker_task_completion_model.dart';
import '../../../data/models/worker_task_model.dart';
import '../../../data/repositories/task_completion_sync_repository.dart';
import '../../../data/repositories/task_repository.dart';
import '../../../data/repositories/worker_attendance_repository.dart';

/// A task shown on the Assign Task screen, along with whether it should
/// apply just for today ('temporary') or every day ('default') — see the
/// `worker_tasks.assignment_type` column doc comment in DatabaseHelper.
///
/// Populated from three sources (see [AssignTaskViewModel.loadTasks]):
/// tasks the worker is already assigned (real `worker_tasks` row —
/// [originalAssignmentType] set to that row's own type), the department's
/// own default tasks not yet assigned to this worker (preselected
/// 'default', [originalAssignmentType] null), and whatever the supervisor
/// picks from the dropdown ([originalAssignmentType] null). [save] only
/// writes rows whose [assignmentType] no longer matches
/// [originalAssignmentType], and only an entry with no
/// [originalAssignmentType] yet (nothing to lose) can be removed from the
/// list before saving.
///
/// [numericValue]/[note] are screen state only, kept alongside the task
/// while it's selected/pending here so they're ready to send once the
/// database work for them is scoped separately — [save] doesn't read or
/// write either anywhere yet.
class PendingTaskAssignment {
  final Task task;
  final String assignmentType;
  final String? originalAssignmentType;
  final double? numericValue;
  final String note;

  const PendingTaskAssignment({
    required this.task,
    required this.assignmentType,
    this.originalAssignmentType,
    this.numericValue,
    this.note = '',
  });

  bool get isAlreadyAssigned => originalAssignmentType != null;

  PendingTaskAssignment copyWith({
    String? assignmentType,
    double? numericValue,
    String? note,
  }) => PendingTaskAssignment(
    task: task,
    assignmentType: assignmentType ?? this.assignmentType,
    originalAssignmentType: originalAssignmentType,
    numericValue: numericValue ?? this.numericValue,
    note: note ?? this.note,
  );
}

/// Drives the Assign Task screen: the worker's (fixed, not editable here)
/// department's task pool, the tasks the supervisor is about to assign, and
/// today's already-assigned checklist.
class AssignTaskViewModel extends BaseViewModel {
  final int workerId;
  final int? initialDepartmentId;
  final TaskRepository _taskRepository;
  final TaskCompletionSyncRepository _taskCompletionSync;
  final WorkerAttendanceRepository _workerAttendance;

  AssignTaskViewModel({
    required this.workerId,
    this.initialDepartmentId,
    TaskRepository? taskRepository,
    TaskCompletionSyncRepository? taskCompletionSync,
    WorkerAttendanceRepository? workerAttendance,
  }) : _taskRepository = taskRepository ?? TaskRepository(),
       _taskCompletionSync = taskCompletionSync ?? TaskCompletionSyncRepository(),
       _workerAttendance = workerAttendance ?? WorkerAttendanceRepository();

  bool _isLoadingTasks = true;
  bool _isSaving = false;
  bool _isSyncingTaskStatus = false;
  bool _isLoadingDayDetails = true;
  bool _isSyncingAttendance = false;
  bool _isSavingTaskStatus = false;

  WorkerAttendanceRecord? _todayAttendance;
  List<WorkerTaskCompletion> _todayTaskCompletions = const [];

  List<Task> _departmentTasks = const [];

  /// The worker's whole task assignment list as shown on screen — already-
  /// assigned tasks, unpicked department defaults, and whatever the
  /// supervisor has picked from the dropdown but not saved yet (see
  /// [PendingTaskAssignment] and [loadTasks]).
  List<PendingTaskAssignment> _pendingTasks = const [];

  bool get isLoadingTasks => _isLoadingTasks;
  bool get isSaving => _isSaving;
  bool get isSyncingTaskStatus => _isSyncingTaskStatus;
  bool get isLoadingDayDetails => _isLoadingDayDetails;
  bool get isSyncingAttendance => _isSyncingAttendance;
  bool get isSavingTaskStatus => _isSavingTaskStatus;

  /// Today's check-in/check-out row for this worker, or null if they
  /// haven't been scanned yet today — drives the Day Details header's
  /// attendance section.
  WorkerAttendanceRecord? get todayAttendance => _todayAttendance;

  /// This worker's assigned tasks with their completion status for today —
  /// empty (rather than an error) when there's no attendance day to key
  /// them off yet.
  List<WorkerTaskCompletion> get todayTaskCompletions => _todayTaskCompletions;
  int get completedTaskCount =>
      _todayTaskCompletions.where((c) => c.isCompleted).length;
  int get totalTaskCount => _todayTaskCompletions.length;

  /// Tasks in the worker's department not already pending — what the task
  /// dropdown offers.
  List<Task> get availableTasks => _departmentTasks
      .where((t) => !_pendingTasks.any((p) => p.task.id == t.id))
      .toList();

  List<PendingTaskAssignment> get pendingTasks => _pendingTasks;

  bool get hasSelection => _pendingTasks.isNotEmpty;
  bool get departmentTasksIsEmpty => _departmentTasks.isEmpty;

  /// Loads the worker's (fixed) department's task pool for the dropdown,
  /// then seeds [pendingTasks] with the tasks that belong there without the
  /// supervisor picking anything: the worker's existing `worker_tasks`
  /// assignments (so their real assignment type shows and can be edited —
  /// see [save]), plus any department default task
  /// ([Task.isDefault]) they aren't already assigned, preselected
  /// 'default'. A task already assigned is never added twice even if it's
  /// also a department default.
  Future<void> loadTasks() async {
    _isLoadingTasks = true;
    safeNotify();

    final departmentId = initialDepartmentId;
    _departmentTasks = departmentId == null
        ? const []
        : await _taskRepository.getTasksByDepartment(departmentId);

    final assignedWorkerTasks = await _taskRepository.getWorkerTasks(workerId);
    final tasksById = {for (final task in _departmentTasks) task.id: task};
    final assignedTaskIds = {for (final wt in assignedWorkerTasks) wt.taskId};

    _pendingTasks = [
      for (final workerTask in assignedWorkerTasks)
        PendingTaskAssignment(
          task: tasksById[workerTask.taskId] ?? _taskFrom(workerTask),
          assignmentType: workerTask.assignmentType,
          originalAssignmentType: workerTask.assignmentType,
        ),
      for (final task in _departmentTasks)
        if (task.isDefault && !assignedTaskIds.contains(task.id))
          PendingTaskAssignment(task: task, assignmentType: 'default'),
    ];

    _isLoadingTasks = false;
    safeNotify();
  }

  /// Falls back to building a [Task] straight from [workerTask] on the rare
  /// chance it's assigned from outside [_departmentTasks] (e.g. moved
  /// departments after assignment) — so it still displays instead of being
  /// silently dropped.
  Task _taskFrom(WorkerTask workerTask) => Task(
    id: workerTask.taskId,
    departmentId: workerTask.departmentId,
    name: workerTask.taskName,
  );

  /// Loads today's attendance row (if any) and, when one exists, this
  /// worker's assigned tasks with their completion status for that day —
  /// the Day Details header/checklist shown above the task picker.
  /// Independent of [loadTasks], so picking tasks to assign never has to
  /// wait on this.
  Future<void> loadDayDetails() async {
    _isLoadingDayDetails = true;
    safeNotify();

    final attendance = await _workerAttendance.getTodayAttendance(workerId);
    _todayAttendance = attendance;
    _todayTaskCompletions = attendance == null
        ? const []
        : await _workerAttendance.getTaskCompletions(
            workerId: workerId,
            attendanceId: attendance.attendanceId,
          );

    _isLoadingDayDetails = false;
    safeNotify();
  }

  /// Retries pushing today's attendance record to the backend — the same
  /// sync the worker list's Attendance Sync action used to trigger. Returns
  /// an error message on failure, or null on success (after which
  /// [todayAttendance] reflects the now-synced row).
  Future<String?> syncAttendance() async {
    if (_isSyncingAttendance) return null;
    _isSyncingAttendance = true;
    safeNotify();

    String? error;
    if (!await NetworkStatus.isOnline()) {
      error = 'No internet connection. Please check your network and try again.';
    } else {
      try {
        await _workerAttendance.syncToday(workerId);
        _todayAttendance = await _workerAttendance.getTodayAttendance(workerId);
      } catch (e) {
        error = ApiException.messageFor(e);
      }
    }

    _isSyncingAttendance = false;
    safeNotify();
    return error;
  }

  /// Sets [completion]'s Is Completed toggle on screen only — [saveTaskStatus]
  /// is what actually writes it to `worker_task_completion`, same as
  /// task_status_screen.dart's own Yes/No toggle ("Toggles only change
  /// what's on screen — Save is what writes them").
  void setTaskCompletion(WorkerTaskCompletion completion, bool isCompleted) {
    _replaceTodayCompletion(completion.copyWith(isCompleted: isCompleted));
  }

  /// Writes every one of today's Is Completed toggles to
  /// `worker_task_completion` — a no-op returning an explanatory message
  /// if there's no attendance day to record them against. Returns null on
  /// success, or an error message on failure, for the caller's snackbar.
  Future<String?> saveTaskStatus() async {
    if (_isSavingTaskStatus) return null;
    final attendance = _todayAttendance;
    if (attendance == null) return 'Worker has no attendance recorded today';
    if (_todayTaskCompletions.isEmpty) return 'No tasks to save';

    _isSavingTaskStatus = true;
    safeNotify();

    try {
      for (final completion in _todayTaskCompletions) {
        await _workerAttendance.setTaskCompletion(
          workerTaskId: completion.workerTaskId,
          workerId: workerId,
          attendanceId: attendance.attendanceId,
          isCompleted: completion.isCompleted,
          remarks: completion.remarks,
        );
      }
      return null;
    } catch (e) {
      return 'Could not save task status: $e';
    } finally {
      _isSavingTaskStatus = false;
      safeNotify();
    }
  }

  void _replaceTodayCompletion(WorkerTaskCompletion updated) {
    _todayTaskCompletions = [
      for (final completion in _todayTaskCompletions)
        completion.workerTaskId == updated.workerTaskId ? updated : completion,
    ];
    safeNotify();
  }

  /// Adds [task] to the pending list — called when the task dropdown picks
  /// a value; the dropdown itself always resets afterward since [task] then
  /// drops out of [availableTasks]. Its assignment type defaults from the
  /// task's own [Task.isDefault], but the supervisor can flip it on the
  /// pending card before saving.
  void addTask(Task task) {
    if (_pendingTasks.any((p) => p.task.id == task.id)) return;
    _pendingTasks = [
      ..._pendingTasks,
      PendingTaskAssignment(
        task: task,
        assignmentType: task.isDefault ? 'default' : 'temporary',
      ),
    ];
    safeNotify();
  }

  /// No-ops for an already-assigned task — there's no unassign flow here,
  /// so removing it from the list without deleting its `worker_tasks` row
  /// would just reappear on the next [loadTasks] and misleadingly look
  /// removed until then. Only a still-unsaved pick (a fresh dropdown
  /// selection, or an unpicked department default) can be dropped this way.
  void removePendingTask(PendingTaskAssignment assignment) {
    if (assignment.isAlreadyAssigned) return;
    _pendingTasks = _pendingTasks
        .where((p) => p.task.id != assignment.task.id)
        .toList();
    safeNotify();
  }

  /// Flips a pending task between 'temporary' (scheduled for today only)
  /// and 'default' (kept as a standing assignment).
  void setPendingAssignmentType(
    PendingTaskAssignment assignment,
    String assignmentType,
  ) {
    _pendingTasks = [
      for (final p in _pendingTasks)
        p.task.id == assignment.task.id
            ? p.copyWith(assignmentType: assignmentType)
            : p,
    ];
    safeNotify();
  }

  /// Screen state only — see [PendingTaskAssignment.numericValue].
  void setPendingNumericValue(
    PendingTaskAssignment assignment,
    double? numericValue,
  ) {
    _pendingTasks = [
      for (final p in _pendingTasks)
        p.task.id == assignment.task.id
            ? PendingTaskAssignment(
                task: p.task,
                assignmentType: p.assignmentType,
                originalAssignmentType: p.originalAssignmentType,
                numericValue: numericValue,
                note: p.note,
              )
            : p,
    ];
    safeNotify();
  }

  /// Screen state only — see [PendingTaskAssignment.note].
  void setPendingNote(PendingTaskAssignment assignment, String note) {
    _pendingTasks = [
      for (final p in _pendingTasks)
        p.task.id == assignment.task.id
            ? PendingTaskAssignment(
                task: p.task,
                assignmentType: p.assignmentType,
                originalAssignmentType: p.originalAssignmentType,
                numericValue: p.numericValue,
                note: note,
              )
            : p,
    ];
    safeNotify();
  }

  /// Saves every task in [pendingTasks] whose [PendingTaskAssignment.
  /// assignmentType] doesn't already match what's in `worker_tasks —
  /// skipping an already-assigned task the supervisor didn't touch avoids
  /// pointlessly bumping its `assigned_at`/sync state. Each write is an
  /// upsert per task (see DatabaseHelper.assignWorkerTask) keyed on
  /// worker+task, so a Default/Today change updates that one existing row
  /// in place rather than creating a duplicate. Returns an error message on
  /// failed validation, or null on success.
  Future<String?> save() async {
    if (_isSaving) return null;
    if (_pendingTasks.isEmpty) return 'Select at least one task';

    _isSaving = true;
    safeNotify();

    for (final assignment in _pendingTasks) {
      if (assignment.assignmentType == assignment.originalAssignmentType) {
        continue;
      }
      await _taskRepository.assignTask(
        workerId: workerId,
        taskId: assignment.task.id,
        assignmentType: assignment.assignmentType,
      );
    }
    // Reload rather than clearing — pendingTasks now doubles as the
    // worker's live assignment list (see loadTasks), so already-assigned
    // tasks (and unpicked defaults) should stay visible/editable, just with
    // their now-current originalAssignmentType.
    await loadTasks();

    _isSaving = false;
    safeNotify();
    // Newly assigned tasks should show up in today's checklist immediately
    // rather than only after the screen is reopened.
    if (_todayAttendance != null) await loadDayDetails();
    return null;
  }

  /// Pushes this worker's pending task-status (completion) records to the
  /// backend, same sync as the worker list's — reachable here too since a
  /// supervisor may land back on this screen right after marking
  /// completions on task_status_screen.dart. Refuses to call the API at all
  /// if any pending record's attendance day hasn't been synced yet (the
  /// completion payload needs that day's real attendance_id), returning
  /// 'Sync attendance first' instead. Returns the message to show in a
  /// snackbar either way. Guards against a second tap while already
  /// syncing.
  Future<String?> syncTaskStatus() async {
    if (_isSyncingTaskStatus) return null;
    _isSyncingTaskStatus = true;
    safeNotify();

    try {
      if (!await NetworkStatus.isOnline()) {
        return 'No internet connection. Please check your network and try again.';
      }
      if (await _taskCompletionSync.hasCompletionsAwaitingAttendanceSync(
        workerId,
      )) {
        return 'Sync attendance first';
      }
      final result = await _taskCompletionSync.syncWorkerTaskCompletions(
        workerId,
      );
      if (result.total == 0) return 'No task status to sync';
      if (result.hasFailures) {
        return 'Synced ${result.succeeded} of ${result.total} task status '
            'update(s) — ${result.total - result.succeeded} failed';
      }
      return 'Synced ${result.succeeded} task status update(s)';
    } finally {
      _isSyncingTaskStatus = false;
      safeNotify();
    }
  }
}
