import '../../../core/base/base_view_model.dart';
import '../../../data/models/department_model.dart';
import '../../../data/repositories/employee_repository.dart';
import '../../../data/repositories/lookup_repository.dart';
import '../../../data/repositories/task_repository.dart';

/// Drives the Assign Task screen: the department picker, that department's
/// task pool, and the worker's existing/newly-selected assignments within
/// whichever department is currently active.
class AssignTaskViewModel extends BaseViewModel {
  final int workerId;
  final int? initialDepartmentId;
  final TaskRepository _taskRepository;
  final LookupRepository _lookupRepository;
  final EmployeeRepository _employeeRepository;

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
  }) : _taskRepository = taskRepository ?? TaskRepository(),
       _lookupRepository = lookupRepository ?? LookupRepository(),
       _employeeRepository = employeeRepository ?? EmployeeRepository() {
    _currentWorkerDepartmentId = initialDepartmentId;
  }

  bool _isLoadingDepartments = true;
  bool _isLoadingTasks = false;
  bool _isSaving = false;

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
    return null;
  }
}
