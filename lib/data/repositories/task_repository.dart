import '../datasources/database_helper.dart';
import '../models/department_model.dart';
import '../models/worker_task_model.dart';

/// Task assignment — which tasks exist per department, and which are
/// assigned to a given worker (the `tasks` / `worker_tasks` tables).
class TaskRepository {
  final DatabaseHelper _dbHelper;

  TaskRepository({DatabaseHelper? dbHelper})
    : _dbHelper = dbHelper ?? DatabaseHelper();

  /// Tasks in [departmentId] — the pool the Assign Task screen picks from,
  /// since a worker can only be assigned tasks from their own department.
  Future<List<Task>> getTasksByDepartment(int departmentId) =>
      _dbHelper.getTasksByDepartment(departmentId);

  /// Whether [workerId]'s local record has been synced — see
  /// DatabaseHelper.isWorkerSynced.
  Future<bool> isWorkerSynced(int workerId) =>
      _dbHelper.isWorkerSynced(workerId);

  /// Every task currently assigned to [workerId].
  Future<List<WorkerTask>> getWorkerTasks(int workerId) =>
      _dbHelper.getWorkerTasks(workerId);

  /// The persistent assignment the assign screen shows — see
  /// DatabaseHelper.getCurrentAssignment.
  Future<WorkerTask?> getCurrentAssignment(int workerId) =>
      _dbHelper.getCurrentAssignment(workerId);

  /// Assigns [taskIds] to [workerId]; already-assigned tasks are silently
  /// skipped (see DatabaseHelper.assignWorkerTasks).
  Future<void> assignTasks(int workerId, List<int> taskIds) =>
      _dbHelper.assignWorkerTasks(workerId, taskIds);

  /// Removes [taskIds] from [workerId]'s assignments.
  Future<void> unassignTasks(int workerId, List<int> taskIds) =>
      _dbHelper.unassignWorkerTasks(workerId, taskIds);

  /// Assigns [taskId] to [workerId] as their one active task, replacing
  /// whatever else was active — an upsert, see DatabaseHelper.assignWorkerTask.
  /// [isDefault] true makes it the worker's standing assignment; false
  /// makes it a one-day-only "Today" assignment.
  Future<void> assignTask({
    required int workerId,
    required int taskId,
    String? note,
    required bool isDefault,
  }) => _dbHelper.assignWorkerTask(
    workerId: workerId,
    taskId: taskId,
    note: note,
    isDefault: isDefault,
  );

  /// The worker's task records that belong to [date] (yyyy-MM-dd), any
  /// status — see DatabaseHelper.getWorkerTasksForDate.
  Future<List<WorkerTask>> getWorkerTasksForDate(int workerId, String date) =>
      _dbHelper.getWorkerTasksForDate(workerId, date);

  /// Every worker_id's current active assignment's task_status — see
  /// DatabaseHelper.getWorkerTaskStatusByWorker.
  Future<Map<int, String>> getWorkerTaskStatusByWorker() =>
      _dbHelper.getWorkerTaskStatusByWorker();

  /// Every worker with at least one active task assignment — for the
  /// worker list's "View Tasks" button, disabled otherwise.
  Future<Set<int>> getWorkerIdsWithAssignedTasks() =>
      _dbHelper.getWorkerIdsWithAssignedTasks();

  /// The worker's own checkout-time numeric/photo entry for [workerTaskId]
  /// — see DatabaseHelper.submitWorkerTaskEntry.
  Future<void> submitWorkerTaskEntry({
    required int workerTaskId,
    required int workerId,
    int? employeeTarget,
    String? workPhoto,
  }) => _dbHelper.submitWorkerTaskEntry(
    workerTaskId: workerTaskId,
    workerId: workerId,
    employeeTarget: employeeTarget,
    workPhoto: workPhoto,
  );

  /// The supervisor's review of the same assignment — see
  /// DatabaseHelper.saveSupervisorTaskReview.
  Future<void> saveSupervisorTaskReview({
    required int workerTaskId,
    required int workerId,
    int? completedTarget,
    String? workPhoto,
    String? note,
    String taskStatus = 'pending',
  }) => _dbHelper.saveSupervisorTaskReview(
    workerTaskId: workerTaskId,
    workerId: workerId,
    completedTarget: completedTarget,
    workPhoto: workPhoto,
    note: note,
    taskStatus: taskStatus,
  );
}
