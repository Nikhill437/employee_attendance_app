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

  /// Assigns [taskId] to [workerId] with [assignmentType] ('default' or
  /// 'temporary') — an upsert, see DatabaseHelper.assignWorkerTask.
  Future<void> assignTask({
    required int workerId,
    required int taskId,
    required String assignmentType,
  }) => _dbHelper.assignWorkerTask(
    workerId: workerId,
    taskId: taskId,
    assignmentType: assignmentType,
  );

  /// Every worker with at least one active task assignment — for the
  /// worker list's "View Tasks" button, disabled otherwise.
  Future<Set<int>> getWorkerIdsWithAssignedTasks() =>
      _dbHelper.getWorkerIdsWithAssignedTasks();

  /// Every worker whose supervisor task-status review isn't finished for
  /// today — see DatabaseHelper.getWorkerIdsWithPendingTaskReview.
  Future<Set<int>> getWorkerIdsWithPendingTaskReview() =>
      _dbHelper.getWorkerIdsWithPendingTaskReview();
}
