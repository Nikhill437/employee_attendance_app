import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../../core/base/base_view_model.dart';
import '../../../core/utils/app_time.dart';
import '../../../data/models/department_model.dart';
import '../../../data/models/worker_task_model.dart';
import '../../../data/repositories/supervisor_session_repository.dart';
import '../../../data/repositories/task_change_request_repository.dart';
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
  final TaskChangeRequestRepository _taskChangeRequests;
  final SupervisorSessionRepository _session;

  AssignTaskViewModel({
    required this.workerId,
    this.initialDepartmentId,
    TaskRepository? taskRepository,
    TaskChangeRequestRepository? taskChangeRequests,
    SupervisorSessionRepository? session,
  }) : _taskRepository = taskRepository ?? TaskRepository(),
       _taskChangeRequests =
           taskChangeRequests ?? TaskChangeRequestRepository(),
       _session = session ?? SupervisorSessionRepository();

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
  bool _workerSynced = false;
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

  /// Whether assigning [pendingTask] would move the worker into a
  /// different pricing group than their current assignment — [save] then
  /// raises a task-change-request draft instead of assigning it outright
  /// (see TaskChangeRequestRepository). False (the plain assignment flow)
  /// whenever either side's pricing group isn't known, so incomplete
  /// pricing data never blocks or redirects an otherwise-normal assignment.
  bool get pendingTaskNeedsApproval {
    final proposed = _pendingTask?.pricingGroupId;
    final current = _assignedTask?.taskPricingGroupId;
    return proposed != null && current != null && proposed != current;
  }

  /// True once [save] has actually raised a task-change-request draft
  /// (rather than assigning the task outright) — the screen reads this
  /// right after a successful [save] to show "submitted for approval"
  /// instead of "task assigned".
  bool _lastSaveWasApprovalRequest = false;
  bool get lastSaveWasApprovalRequest => _lastSaveWasApprovalRequest;

  int? get entryNumericValue => _entryNumericValue;

  /// The photo to show on the Worker Submission card — only whatever was
  /// just captured this session, deliberately never falling back to
  /// `work_photo` the way [reviewPhoto] does: this card only ever appears
  /// once, at that day's one checkout scan (see MarkAttendanceScreen
  /// ._openFollowUpScreen's WorkerScanOutcome.checkedOut case — a later
  /// scan the same day is WorkerScanOutcome.alreadyCheckedOut and never
  /// reopens it), so there's no legitimate "resume where I left off" case
  /// to prefill for — only ever a brand-new entry.
  File? get entryPhoto => _entryPhoto;

  int? get reviewNumericValue => _reviewNumericValue;

  /// The photo to show on the Supervisor Review card — whatever's already
  /// saved to `work_photo` (the worker's own submission), until the
  /// supervisor captures their own to override it with. Unlike
  /// [entryPhoto], this prefill is legitimate: the supervisor is reviewing
  /// what the worker just submitted, not making a fresh entry.
  File? get reviewPhoto => _reviewPhoto ?? _persistedPhoto;
  String get reviewNote => _reviewNote;
  String get reviewTaskStatus => _reviewTaskStatus;

  /// Whether the assigned task's own type (`tasks.task_type`) is Task Based
  /// or Hour Based — the only types the Completion count/hours field
  /// applies to, on both the worker's own Worker Submission card and the
  /// Supervisor Review card (Daily/Monthly tasks aren't counted or timed
  /// per day, so there's nothing for either of them to enter there).
  bool get reviewNeedsCompletionCount {
    final type = _assignedTask?.taskType;
    return type == TaskType.taskBased.name || type == TaskType.hourBased.name;
  }

  /// Whether the shown assignment is today's record. An earlier day's
  /// persistent assignment is displayed, but nothing can be saved on it until
  /// the worker checks in and today's record is created.
  bool get isAssignmentToday => _assignedTask?.taskDate == _todayKey();

  String _todayKey() {
    final now = AppTime.nowInUserZone();
    return '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
  }

  /// Whether today's Supervisor Review has already synced to the backend
  /// (`worker_tasks.worker_task_id` set on *today's* row — see
  /// WorkerTask.realWorkerTaskId) — once true, the review for today is
  /// done and the screen shows it read-only instead of editable. Flips
  /// back to false on its own the moment a new day's row is created (see
  /// DatabaseHelper.getWorkerTasks), since that fresh row always starts
  /// with no real id yet.
  ///
  /// For Task Based/Hourly tasks, synced alone isn't enough — a synced row
  /// can still be sitting on its never-filled-in default completed_target,
  /// so [reviewNeedsCompletionCount]'s own field being filled in is checked
  /// too. Daily/Monthly tasks have no such field to check (it's hidden —
  /// see [reviewNeedsCompletionCount]), so for them sync alone is the only
  /// signal there is: otherwise they'd never lock at all, since
  /// completed_target stays null forever for that task type.
  bool get isReviewLocked {
    if (!_workerSynced) return false;
    if (reviewNeedsCompletionCount) return _assignedTask?.completedTarget != null;
    return true;
  }

  File? get _persistedPhoto {
    final path = _assignedTask?.workPhoto;
    return path == null ? null : File(path);
  }

  /// Loads the worker's (fixed) department's task pool for the dropdown,
  /// then the worker's one active assignment (if any) — re-seeding the
  /// review fields from it, so a save doesn't lose what was already there
  /// for the supervisor's side. The worker's own entry fields are never
  /// re-seeded from it (see [entryPhoto]'s doc comment) — every call starts
  /// them blank, since this screen's checkout mode only ever represents a
  /// brand-new entry, never a resumed one.
  Future<void> loadTasks() async {
    _isLoadingTasks = true;
    safeNotify();

    final departmentId = initialDepartmentId;
    _departmentTasks = departmentId == null
        ? const []
        : await _taskRepository.getTasksByDepartment(departmentId);

    _assignedTask = await _taskRepository.getCurrentAssignment(workerId);
    _workerSynced = await _taskRepository.isWorkerSynced(workerId);

    _entryNumericValue = null;
    _entryPhoto = null;
    // The review is prefilled from today's record, so values saved before
    // sync are still there. A persistent assignment from an earlier day, or a
    // new day's record, has no review, so the fields start empty. Last day's
    // review stays on that day's record.
    if (isAssignmentToday) {
      _reviewNumericValue = _assignedTask?.completedTarget;
      _reviewTaskStatus = _assignedTask?.taskStatus ?? 'pending';
      _reviewNote = _assignedTask?.supervisorNote ?? '';
    } else {
      _reviewNumericValue = null;
      _reviewTaskStatus = 'pending';
      _reviewNote = '';
    }
    _reviewPhoto = null;

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
    _pendingNote = '';
    safeNotify();
  }

  String _pendingNote = '';

  /// The optional note for the task picked above, saved with the assignment.
  String get pendingNote => _pendingNote;

  void setPendingNote(String note) {
    _pendingNote = note;
    safeNotify();
  }

  /// Assigns [pendingTask] as the worker's one active task — whatever was
  /// previously active for them is flipped inactive (see
  /// DatabaseHelper.assignWorkerTask) — unless [pendingTaskNeedsApproval],
  /// in which case this instead raises a local, not-yet-submitted
  /// task-change-request draft (see
  /// TaskChangeRequestRepository.createLocalRequest) and leaves the
  /// worker's actual assignment untouched until that request is approved
  /// through the existing (separate) approval workflow. The draft is
  /// deliberately **not** submitted here — the worker list's Not Synced/
  /// Sync button is the only thing that calls `TaskChangeRequestApi.
  /// assignTask` (see WorkerListViewModel.syncTaskChangeRequest), so this
  /// never calls the API itself. The screen has no reason field for this
  /// path (the confirm dialog is the only prompt), so [TaskPricingChangeRequest.
  /// reason] is left null; a normal assignment's note stays optional and
  /// unaffected. Returns an error message on failed validation, or null
  /// on success — check [lastSaveWasApprovalRequest] afterward to tell
  /// which path a successful save actually took.
  Future<String?> save() async {
    if (_isSaving) return null;
    final task = _pendingTask;
    if (task == null) return 'Select a task to assign';

    final needsApproval = pendingTaskNeedsApproval;
    final trimmedNote = _pendingNote.trim();

    _isSaving = true;
    safeNotify();

    if (needsApproval) {
      final requestedBy = await _session.getSupervisorId();
      await _taskChangeRequests.createLocalRequest(
        workerId: workerId,
        taskId: task.id,
        currentPricingGroupId: _assignedTask?.taskPricingGroupId,
        proposedPricingGroupId: task.pricingGroupId!,
        oldRate: _assignedTask?.taskRate,
        newRate: task.rate ?? 0,
        reason: null,
        requestedBy: requestedBy ?? 0,
      );
      _lastSaveWasApprovalRequest = true;
    } else {
      await _taskRepository.assignTask(
        workerId: workerId,
        taskId: task.id,
        note: trimmedNote.isEmpty ? null : trimmedNote,
      );
      _lastSaveWasApprovalRequest = false;
    }
    _pendingTask = null;
    _pendingNote = '';
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
  /// [entryPhoto] into `worker_tasks.employee_target`/`work_photo`. Both are
  /// optional — an empty form still saves. Saving updates the worker's
  /// existing `worker_tasks` row by its own id rather than ever inserting a
  /// new one, so checking out again for the same task never creates a
  /// duplicate record.
  Future<String?> saveWorkerEntry() async {
    final task = _assignedTask;
    if (task == null) return 'No task assigned yet';
    if (!isAssignmentToday) return 'Check in today first';
    if (_isSubmittingEntry) return null;

    _isSubmittingEntry = true;
    safeNotify();
    try {
      final newPhotoPath = _entryPhoto?.path;
      final oldPhotoPath = task.workPhoto;
      await _taskRepository.submitWorkerTaskEntry(
        workerTaskId: task.workerTaskId,
        workerId: workerId,
        employeeTarget: _entryNumericValue,
        workPhoto: newPhotoPath,
      );
      // The old photo is now orphaned once the new one is saved as
      // work_photo — delete it so a stale reference can never linger (see
      // _copyToPermanentStorage, which only ever creates new files).
      if (newPhotoPath != null && oldPhotoPath != null) {
        await _deletePhotoIfReplaced(oldPhotoPath, newPhotoPath);
      }
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
    if (!isAssignmentToday) return 'Check in today first';
    if (isReviewLocked) return 'Already synced for today';
    if (_isSavingReview) return null;

    _isSavingReview = true;
    safeNotify();
    try {
      final newPhotoPath = _reviewPhoto?.path;
      final oldPhotoPath = task.workPhoto;
      await _taskRepository.saveSupervisorTaskReview(
        workerTaskId: task.workerTaskId,
        workerId: workerId,
        completedTarget: _reviewNumericValue,
        workPhoto: newPhotoPath,
        note: _reviewNote.trim().isEmpty ? null : _reviewNote.trim(),
        taskStatus: _reviewTaskStatus,
      );
      // Same cleanup as saveWorkerEntry — the review can also replace
      // work_photo with a freshly captured one.
      if (newPhotoPath != null && oldPhotoPath != null) {
        await _deletePhotoIfReplaced(oldPhotoPath, newPhotoPath);
      }
      await loadTasks();
      return null;
    } finally {
      _isSavingReview = false;
      safeNotify();
    }
  }

  /// Deletes [oldPath] once [newPath] has been saved as its replacement —
  /// best-effort: a failed delete just leaves an orphan file (the
  /// pre-existing behavior), never lets cleanup itself fail a successful
  /// save. A no-op when [oldPath] and [newPath] are actually the same file.
  Future<void> _deletePhotoIfReplaced(String oldPath, String newPath) async {
    if (oldPath == newPath) return;
    try {
      final oldFile = File(oldPath);
      if (await oldFile.exists()) {
        await oldFile.delete();
      }
    } catch (_) {
      // Ignored — see doc comment above.
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
