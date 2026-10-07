import '../datasources/database_helper.dart';
import '../datasources/worker_task_list_api.dart';
import 'server_sync_time_store.dart';

/// Imports the backend's worker-task assignment list into the local
/// `worker_tasks` table, upserted by (worker, task).
class WorkerTaskImportRepository {
  final WorkerTaskListApi _api;
  final DatabaseHelper _dbHelper;

  WorkerTaskImportRepository({WorkerTaskListApi? api, DatabaseHelper? dbHelper})
    : _api = api ?? WorkerTaskListApi(),
      _dbHelper = dbHelper ?? DatabaseHelper();

  /// The dashboard's "Worker Tasks" button. With no stored Worker Tasks time
  /// (the first tap ever) it pulls the full list. Every later tap sends the
  /// stored time and pulls only what changed. The new time is saved only
  /// after the rows are stored, and a failed fetch leaves it unchanged. Returns
  /// how many rows were fetched.
  Future<int> importWorkerTasks() async {
    final syncStartedAt = DateTime.now().toUtc().toIso8601String();
    final storedTime = await lastWorkerTaskServerTime.read();
    final records = storedTime == null
        ? await _api.workerTaskList()
        : await _api.serverWorkerTaskList(date: storedTime);
    await _dbHelper.upsertRemoteWorkerTasks(records);
    await lastWorkerTaskServerTime.save(syncStartedAt);
    return records.length;
  }
}
