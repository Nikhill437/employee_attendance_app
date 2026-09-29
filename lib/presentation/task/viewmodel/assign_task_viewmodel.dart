import '../../../core/base/base_view_model.dart';
import '../../../data/models/department_model.dart';
import '../../../data/models/worker_attendance_model.dart';
import '../../../data/models/worker_task_completion_model.dart';
import '../../../data/repositories/employee_repository.dart';
import '../../../data/repositories/lookup_repository.dart';
import '../../../data/repositories/task_completion_sync_repository.dart';
import '../../../data/repositories/task_repository.dart';
import '../../../data/repositories/worker_attendance_repository.dart';

/// Drives the Assign Task screen: the department picker, that department's
/// task pool, and the worker's existing/newly-selected assignments within
/// whichever department is currently active.
class AssignTaskViewModel extends BaseViewModel {
  final int workerId;
  final int? initialDepartmentId;
  final TaskRepository _taskRepository;
  final LookupRepository _lookupRepository;
  final EmployeeRepository _employeeRepository;
  final TaskCompletionSyncRepository _taskCompletionSync;
  final WorkerAttendanceRepository _workerAttendance;

  /// The worker's department as currently known — starts as
  /// [initialDepartmentId], then follows every successful [save] that
  /// changes it, so re-saving without touching the dropdown again never
  /// re-triggers an update.
  int? _currentWorkerDepartmentId;

  AssignTaskViewModel({
    required this.workerId,
    this.initialDepartmentId,
    TaskRepository? taskRepository,
    LookupRepository? lookupRepository,
    EmployeeRepository? employeeRepository,
    TaskCompletionSyncRepository? taskCompletionSync,
    WorkerAttendanceRepository? workerAttendance,
  }) : _taskRepository = taskRepository ?? TaskRepository(),
       _lookupRepository = lookupRepository ?? LookupRepository(),
       _employeeRepository = employeeRepository ?? EmployeeRepository(),
       _taskCompletionSync = taskCompletionSync ?? TaskCompletionSyncRepository(),
       _workerAttendance = workerAttendance ?? WorkerAttendanceRepository() {
    _currentWorkerDepartmentId = initialDepartmentId;
  }

  bool _isLoadingDepartments = true;
  bool _isLoadingTasks = false;
  bool _isSaving = false;
  bool _isSyncingTaskStatus = false;
  bool _isLoadingDayDetails = true;
  bool _isSyncingAttendance = false;
  bool _isSavingTaskStatus = false;

  WorkerAttendanceRecord? _todayAttendance;
  List<WorkerTaskCompletion> _todayTaskCompletions = const [];

  List<Department> _departments = const [];
  Department? _selectedDepartment;

  List<Task> _departmentTasks = const [];

  /// Task ids assigned to [workerId] *within the currently selected
  /// department*, as of the last load for that department — the baseline
  /// [save] diffs the current selection against.
  Set<int> _existingTaskIds = {};

  /// The working selection — starts equal to [_existingTaskIds] each time
  /// the department changes, then the supervisor adds/removes from it.
  Set<int> _selectedTaskIds = {};

  bool get isLoadingDepartments => _isLoadingDepartments;
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

  List<Department> get departments => _departments;
  Department? get selectedDepartment => _selectedDepartment;

  /// Tasks in the selected department not already in the current
  /// selection — what the task dropdown offers.
  List<Task> get availableTasks =>
      _departmentTasks.where((t) => !_selectedTaskIds.contains(t.id)).toList();

  /// The selected tasks, for the "selected tasks" chip list.
  List<Task> get selectedTasks =>
      _departmentTasks.where((t) => _selectedTaskIds.contains(t.id)).toList();

  bool get hasSelection => _selectedTaskIds.isNotEmpty;
  bool get departmentTasksIsEmpty => _departmentTasks.isEmpty;

  Future<void> loadDepartments() async {
    _isLoadingDepartments = true;
    safeNotify();

    _departments = await _lookupRepository.getDepartments();
    final initialId = initialDepartmentId;
    if (initialId != null) {
      for (final department in _departments) {
        if (department.id == initialId) {
          _selectedDepartment = department;
          break;
        }
      }
    }

    _isLoadingDepartments = false;
    safeNotify();
    if (_selectedDepartment != null) {
      await _loadTasksForSelectedDepartment();
    }
  }

  /// Loads today's attendance row (if any) and, when one exists, this
  /// worker's assigned tasks with their completion status for that day —
  /// the Day Details header/checklist shown above the department/task
  /// picker. Independent of [loadDepartments]/[selectDepartment], so
  /// picking tasks to assign never has to wait on this.
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
    try {
      await _workerAttendance.syncToday(workerId);
      _todayAttendance = await _workerAttendance.getTodayAttendance(workerId);
    } catch (e) {
      error = e.toString();
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

  /// Changing department clears the current task selection and reloads
  /// only that department's tasks and this worker's existing assignments
  /// within it — assignments in other departments are left untouched
  /// entirely (they're never loaded into this screen's state).
  Future<void> selectDepartment(Department? department) async {
    if (department?.id == _selectedDepartment?.id) return;
    _selectedDepartment = department;
    _departmentTasks = const [];
    _existingTaskIds = {};
    _selectedTaskIds = {};
    safeNotify();

    if (department != null) {
      await _loadTasksForSelectedDepartment();
    }
  }

  Future<void> _loadTasksForSelectedDepartment() async {
    final department = _selectedDepartment;
    if (department == null) return;

    _isLoadingTasks = true;
    safeNotify();

    final tasks = await _taskRepository.getTasksByDepartment(department.id);
    final assigned = await _taskRepository.getWorkerTasks(workerId);
    final taskIdsInDepartment = tasks.map((t) => t.id).toSet();
    final existing = assigned
        .map((a) => a.taskId)
        .where(taskIdsInDepartment.contains)
        .toSet();

    _departmentTasks = tasks;
    _existingTaskIds = existing;
    _selectedTaskIds = {...existing};
    _isLoadingTasks = false;
    safeNotify();
  }

  /// Adds [task] to the selection — called when the task dropdown picks a
  /// value; the dropdown itself always resets afterward since [task] then
  /// drops out of [availableTasks].
  void addTask(Task task) {
    _selectedTaskIds.add(task.id);
    safeNotify();
  }

  void removeTask(Task task) {
    _selectedTaskIds.remove(task.id);
    safeNotify();
  }

  /// Saves the current selection for the selected department: newly
  /// selected tasks are assigned, previously-assigned tasks the supervisor
  /// removed are unassigned — both diffed against [_existingTaskIds], so
  /// re-saving an unchanged selection is a no-op and never creates
  /// duplicate `worker_tasks` rows (the table's own
  /// UNIQUE(worker_id, task_id) backs that up regardless). If the selected
  /// department differs from the worker's current one (e.g. Production →
  /// Installation), the `workers` table is updated to match, so the
  /// worker's own record stays in sync with whichever department their
  /// tasks actually came from. Returns an error message on failed
  /// validation, or null on success.
  Future<String?> save() async {
    if (_isSaving) return null;
    final department = _selectedDepartment;
    if (department == null) return 'Select a department';
    if (_selectedTaskIds.isEmpty) return 'Select at least one task';

    final toAdd = _selectedTaskIds.difference(_existingTaskIds).toList();
    final toRemove = _existingTaskIds.difference(_selectedTaskIds).toList();
    final departmentChanged = department.id != _currentWorkerDepartmentId;
    if (toAdd.isEmpty && toRemove.isEmpty && !departmentChanged) return null;

    _isSaving = true;
    safeNotify();

    if (departmentChanged) {
      await _employeeRepository.updateDepartment(workerId, department.id);
      _currentWorkerDepartmentId = department.id;
    }
    if (toAdd.isNotEmpty) {
      await _taskRepository.assignTasks(workerId, toAdd);
    }
    if (toRemove.isNotEmpty) {
      await _taskRepository.unassignTasks(workerId, toRemove);
    }

    _existingTaskIds = {..._selectedTaskIds};
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
