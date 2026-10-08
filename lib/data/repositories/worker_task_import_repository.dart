import '../../core/utils/app_time.dart';
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
  Future<int> importWorkerTasks({
    void Function(int fetchedSoFar, int currentPage, int totalPages)?
    onProgress,
  }) async {
    final syncStartedAt = DateTime.now().toUtc().toIso8601String();
    final storedTime = await lastWorkerTaskServerTime.read();
    final records = storedTime == null
        ? await _api.workerTaskList(onProgress: onProgress)
        : await _api.serverWorkerTaskList(
            date: storedTime,
            onProgress: onProgress,
          );
    await _dbHelper.upsertRemoteWorkerTasks(records);
    await lastWorkerTaskServerTime.save(syncStartedAt);
    return records.length;
  }

  /// How many worker-task rows are cached locally, and how many of those
  /// still await a supervisor verdict — the Employee Tasks List card's
  /// stat boxes.
  Future<int> getWorkerTaskCount() => _dbHelper.getWorkerTaskCount();
  Future<int> getPendingWorkerTaskCount() =>
      _dbHelper.getPendingWorkerTaskCount();

  /// The last successful [importWorkerTasks] fetch's start time, in the
  /// supervisor's own timezone (see AppTime) — null if none has run yet.
  Future<DateTime?> lastSyncedAt() async {
    final stored = await lastWorkerTaskServerTime.read();
    final parsed = stored == null ? null : DateTime.tryParse(stored);
    return parsed == null ? null : AppTime.toUserTime(parsed);
  }

  /// The Employee Tasks List card's Clear action: wipes every local
  /// worker-task row — including any reassignment or review made on this
  /// device and not yet synced — and resets the fetch checkpoint, so the
  /// next fetch pulls the full list again.
  Future<void> clearLocal() async {
    await _dbHelper.clearWorkerTasks();
    await lastWorkerTaskServerTime.clear();
  }
}
