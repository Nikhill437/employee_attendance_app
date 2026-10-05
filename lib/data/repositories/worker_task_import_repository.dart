import '../datasources/database_helper.dart';
import '../datasources/worker_task_list_api.dart';

/// Imports the backend's worker-task assignment list into the local
/// `worker_tasks` table, upserted by (worker, task) — mirrors
/// WorkerImportRepository's split between the full roster and the
/// server-time delta.
class WorkerTaskImportRepository {
  final WorkerTaskListApi _api;
  final DatabaseHelper _dbHelper;

  WorkerTaskImportRepository({WorkerTaskListApi? api, DatabaseHelper? dbHelper})
    : _api = api ?? WorkerTaskListApi(),
      _dbHelper = dbHelper ?? DatabaseHelper();

  /// Fetches every worker-task assignment from the backend
  /// (`POST attendance/worker_task_list`) and upserts them locally.
  /// Returns how many were fetched.
  Future<int> importFromRemote() async {
    final records = await _api.workerTaskList();
    await _dbHelper.upsertRemoteWorkerTasks(records);
    return records.length;
  }

  /// Same upsert as [importFromRemote], backed by
  /// [WorkerTaskListApi.serverWorkerTaskList]
  /// (`POST attendance/server_time_worker_task_list`) instead of the full
  /// paginated list.
  Future<int> importFromServerTime() async {
    final records = await _api.serverWorkerTaskList();
    await _dbHelper.upsertRemoteWorkerTasks(records);
    return records.length;
  }
}
