import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../../core/base/base_view_model.dart';
import '../../../data/models/department_model.dart';
import '../../../data/models/worker_task_model.dart';
import '../../../data/repositories/task_repository.dart';

/// Drives the Assign Task screen: the worker's (fixed, not editable here)
/// department's task pool, the one task currently assigned to them (if
/// any — a worker only ever has one active assignment, see
/// DatabaseHelper.assignWorkerTask), and the worker/supervisor's own entry
/// for it.
class AssignTaskViewModel extends BaseViewModel {
  final int workerId;
  final int? initialDepartmentId;
  final TaskRepository _taskRepository;

  AssignTaskViewModel({
    required this.workerId,
    this.initialDepartmentId,
    TaskRepository? taskRepository,
  }) : _taskRepository = taskRepository ?? TaskRepository();

  bool _isLoadingTasks = true;
  bool _isSaving = false;
  bool _isSubmittingEntry = false;
  bool _isSavingReview = false;

  List<Task> _departmentTasks = const [];

  /// The worker's single currently-active assignment, or null if they
  /// have none.
  WorkerTask? _assignedTask;

  /// A task picked from the dropdown but not assigned yet — at most one
  /// at a time (see [addTask]).
  Task? _pendingTask;

  int? _entryNumericValue;
  File? _entryPhoto;

  int? _reviewNumericValue;
  File? _reviewPhoto;
  String _reviewNote = '';
  String _reviewTaskStatus = 'pending';

  bool get isLoadingTasks => _isLoadingTasks;
  bool get isSaving => _isSaving;
  bool get isSubmittingEntry => _isSubmittingEntry;
  bool get isSavingReview => _isSavingReview;

  WorkerTask? get assignedTask => _assignedTask;
  Task? get pendingTask => _pendingTask;

  /// Tasks in the worker's department not already assigned or pending —
  /// what the task dropdown offers.
  List<Task> get availableTasks => _departmentTasks
      .where((t) => t.id != _assignedTask?.taskId && t.id != _pendingTask?.id)
      .toList();

  /// Only one new, not-yet-saved task may be picked at a time.
  bool get canPickNewTask => _pendingTask == null;
  bool get departmentTasksIsEmpty => _departmentTasks.isEmpty;

  int? get entryNumericValue => _entryNumericValue;

  /// The photo to show on the Worker Submission card — whatever was just
  /// captured this session, falling back to the already-persisted
  /// `work_photo` otherwise.
  File? get entryPhoto => _entryPhoto ?? _persistedPhoto;

  int? get reviewNumericValue => _reviewNumericValue;

  /// The photo to show on the Supervisor Review card — same fallback as
  /// [entryPhoto], since both start out showing whatever's already saved
  /// to `work_photo` (the worker's own, until the supervisor overwrites it).
  File? get reviewPhoto => _reviewPhoto ?? _persistedPhoto;
  String get reviewNote => _reviewNote;
  String get reviewTaskStatus => _reviewTaskStatus;

  /// Whether today's Supervisor Review has already synced to the backend
  /// (`worker_tasks.worker_task_id` set on *today's* row — see
  /// WorkerTask.realWorkerTaskId) — once true, the review for today is
  /// done and the screen shows it read-only instead of editable. Flips
  /// back to false on its own the moment a new day's row is created (see
  /// DatabaseHelper.getWorkerTasks), since that fresh row always starts
  /// with no real id yet.
  bool get isReviewLocked => _assignedTask?.realWorkerTaskId != null;

  File? get _persistedPhoto {
    final path = _assignedTask?.workPhoto;
    return path == null ? null : File(path);
  }

  /// Loads the worker's (fixed) department's task pool for the dropdown,
  /// then the worker's one active assignment (if any) — re-seeding the
  /// entry/review fields from it, so a save doesn't lose what was already
  /// there for the other role.
  Future<void> loadTasks() async {
    _isLoadingTasks = true;
    safeNotify();

    final departmentId = initialDepartmentId;
    _departmentTasks = departmentId == null
        ? const []
        : await _taskRepository.getTasksByDepartment(departmentId);

    final assignedWorkerTasks = await _taskRepository.getWorkerTasks(workerId);
    _assignedTask = assignedWorkerTasks.isEmpty
        ? null
        : assignedWorkerTasks.first;

    _entryNumericValue = _assignedTask?.employeeTarget;
    _entryPhoto = null;
    _reviewNumericValue = _assignedTask?.completedTarget;
    _reviewPhoto = null;
    _reviewNote = _assignedTask?.note ?? '';
    _reviewTaskStatus = _assignedTask?.taskStatus ?? 'pending';

    _isLoadingTasks = false;
    safeNotify();
  }

  /// Picks [task] to assign next — called when the task dropdown picks a
  /// value. A no-op while a pick is already pending (see [canPickNewTask]).
  void addTask(Task task) {
    if (_pendingTask != null) return;
    _pendingTask = task;
    safeNotify();
  }

  /// Clears the pending pick, re-opening the dropdown.
  void removePendingTask() {
    _pendingTask = null;
    safeNotify();
  }

  /// Assigns [pendingTask] as the worker's one active task — whatever was
  /// previously active for them is flipped inactive (see
  /// DatabaseHelper.assignWorkerTask). Returns an error message on failed
  /// validation, or null on success.
  Future<String?> save() async {
    if (_isSaving) return null;
    final task = _pendingTask;
    if (task == null) return 'Select a task to assign';

    _isSaving = true;
    safeNotify();

    await _taskRepository.assignTask(workerId: workerId, taskId: task.id);
    _pendingTask = null;
    await loadTasks();

    _isSaving = false;
    safeNotify();
    return null;
  }

  void setEntryNumericValue(int? value) {
    _entryNumericValue = value;
    safeNotify();
  }

  /// Copies the just-captured photo into permanent app storage (the path
  /// image_picker/the camera return can be a cache/temp location the OS is
  /// free to clear) — same pattern as
  /// EnrollmentFormViewModel.captureNationalIdImage, since this one does
  /// get persisted (into `worker_tasks.work_photo`).
  Future<void> captureEntryPhoto(File pickedFile) async {
    _entryPhoto = await _copyToPermanentStorage(pickedFile);
    safeNotify();
  }

  /// The worker's checkout-time Save — writes [entryNumericValue]/
  /// [entryPhoto] into `worker_tasks.employee_target`/`work_photo`.
  /// Quantity is required (the photo stays optional); saving updates the
  /// worker's existing `worker_tasks` row by its own id rather than ever
  /// inserting a new one, so checking out again for the same task never
  /// creates a duplicate record.
  Future<String?> saveWorkerEntry() async {
    final task = _assignedTask;
    if (task == null) return 'No task assigned yet';
    if (_entryNumericValue == null) return 'Quantity is required';
    if (_isSubmittingEntry) return null;

    _isSubmittingEntry = true;
    safeNotify();
    try {
      await _taskRepository.submitWorkerTaskEntry(
        workerTaskId: task.workerTaskId,
        workerId: workerId,
        employeeTarget: _entryNumericValue,
        workPhoto: _entryPhoto?.path,
      );
      await loadTasks();
      return null;
    } finally {
      _isSubmittingEntry = false;
      safeNotify();
    }
  }

  void setReviewNumericValue(int? value) {
    _reviewNumericValue = value;
    safeNotify();
  }

  Future<void> captureReviewPhoto(File pickedFile) async {
    _reviewPhoto = await _copyToPermanentStorage(pickedFile);
    safeNotify();
  }

  void setReviewNote(String note) {
    _reviewNote = note;
    safeNotify();
  }

  void setReviewTaskStatus(String status) {
    _reviewTaskStatus = status;
    safeNotify();
  }

  /// The supervisor's Save — writes [reviewNumericValue]/[reviewNote]/
  /// [reviewTaskStatus] into `worker_tasks.completed_target`/`note`/
  /// `task_status`, and overwrites `work_photo` only if the supervisor
  /// actually captured a new one this session ([_reviewPhoto] non-null —
  /// [reviewPhoto]'s persisted fallback doesn't count as "captured").
  Future<String?> saveSupervisorReview() async {
    final task = _assignedTask;
    if (task == null) return 'No task assigned yet';
    if (isReviewLocked) return 'Already synced for today';
    if (_reviewNumericValue == null) return 'Quantity is required';
    if (_isSavingReview) return null;

    _isSavingReview = true;
    safeNotify();
    try {
      await _taskRepository.saveSupervisorTaskReview(
        workerTaskId: task.workerTaskId,
        workerId: workerId,
        completedTarget: _reviewNumericValue,
        workPhoto: _reviewPhoto?.path,
        note: _reviewNote.trim().isEmpty ? null : _reviewNote.trim(),
        taskStatus: _reviewTaskStatus,
      );
      await loadTasks();
      return null;
    } finally {
      _isSavingReview = false;
      safeNotify();
    }
  }

  Future<File> _copyToPermanentStorage(File pickedFile) async {
    final docsDir = await getApplicationDocumentsDirectory();
    final dir = Directory('${docsDir.path}/worker_task_photos');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final extension = pickedFile.path.contains('.')
        ? pickedFile.path.split('.').last
        : 'jpg';
    final destPath =
        '${dir.path}/${DateTime.now().millisecondsSinceEpoch}.$extension';
    return pickedFile.copy(destPath);
  }
}
