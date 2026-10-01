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

  /// Every task currently assigned to [workerId].
  Future<List<WorkerTask>> getWorkerTasks(int workerId) =>
      _dbHelper.getWorkerTasks(workerId);

  /// Assigns [taskIds] to [workerId]; already-assigned tasks are silently
  /// skipped (see DatabaseHelper.assignWorkerTasks).
  Future<void> assignTasks(int workerId, List<int> taskIds) =>
      _dbHelper.assignWorkerTasks(workerId, taskIds);

  /// Removes [taskIds] from [workerId]'s assignments.
  Future<void> unassignTasks(int workerId, List<int> taskIds) =>
      _dbHelper.unassignWorkerTasks(workerId, taskIds);

  /// Assigns [taskId] to [workerId] as their one active task, replacing
  /// whatever else was active — an upsert, see DatabaseHelper.assignWorkerTask.
  Future<void> assignTask({required int workerId, required int taskId}) =>
      _dbHelper.assignWorkerTask(workerId: workerId, taskId: taskId);

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
  }) => _dbHelper.saveSupervisorTaskReview(
    workerTaskId: workerTaskId,
    workerId: workerId,
    completedTarget: completedTarget,
    workPhoto: workPhoto,
    note: note,
  );
}
