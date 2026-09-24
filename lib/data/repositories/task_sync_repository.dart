import '../datasources/database_helper.dart';
import '../datasources/task_sync_api.dart';
import 'task_repository.dart';

/// How many of a worker's task assignments a [TaskSyncRepository.syncWorkerTasks]
/// call pushed successfully, and which ones (by task name) failed.
class TaskSyncResult {
  final int succeeded;
  final int total;
  final List<String> failed;

  const TaskSyncResult({
    required this.succeeded,
    required this.total,
    required this.failed,
  });

  bool get hasFailures => failed.isNotEmpty;
}

/// Pushes a worker's task assignments to the backend
/// (`POST attendance/assigntask`) — one request per assignment, since the
/// endpoint only takes one at a time.
class TaskSyncRepository {
  final TaskSyncApi _api;
  final TaskRepository _taskRepository;
  final DatabaseHelper _dbHelper;

  TaskSyncRepository({
    TaskSyncApi? api,
    TaskRepository? taskRepository,
    DatabaseHelper? dbHelper,
  }) : _api = api ?? TaskSyncApi(),
       _taskRepository = taskRepository ?? TaskRepository(),
       _dbHelper = dbHelper ?? DatabaseHelper();

  /// Syncs every task currently assigned to [workerId]. Throws if the
  /// worker themselves hasn't been synced yet — the backend needs their
  /// real worker_id, which only exists once `POST attendance/sync-worker`
  /// has returned one (see DatabaseHelper.getRemoteWorkerId). A failure on
  /// one assignment doesn't stop the rest from being attempted.
  Future<TaskSyncResult> syncWorkerTasks(int workerId) async {
    final realWorkerId = await _dbHelper.getRemoteWorkerId(workerId);
    if (realWorkerId == null) {
      throw StateError('Sync this worker before syncing their tasks');
    }

    final assignments = await _taskRepository.getWorkerTasks(workerId);
    var succeeded = 0;
    final failed = <String>[];

    for (final assignment in assignments) {
      try {
        final realWorkerTaskId = await _api.syncAssignment(
          workerId: realWorkerId,
          taskId: assignment.taskId,
          departmentId: assignment.departmentId,
          status: assignment.status,
        );
        await _dbHelper.markWorkerTaskSynced(
          assignment.workerTaskId,
          realWorkerTaskId,
        );
        succeeded++;
      } catch (_) {
        failed.add(assignment.taskName);
      }
    }

    return TaskSyncResult(
      succeeded: succeeded,
      total: assignments.length,
      failed: failed,
    );
  }
}
