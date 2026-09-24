import '../datasources/database_helper.dart';
import '../datasources/worker_list_api.dart';

/// Imports the backend's full worker roster (`POST attendance/list`) into
/// the local `workers` table, upserted by National ID.
class WorkerImportRepository {
  final WorkerListApi _api;
  final DatabaseHelper _dbHelper;

  WorkerImportRepository({WorkerListApi? api, DatabaseHelper? dbHelper})
    : _api = api ?? WorkerListApi(),
      _dbHelper = dbHelper ?? DatabaseHelper();

  /// Fetches every worker from the backend and upserts them locally.
  /// Returns how many were fetched.
  Future<int> importFromRemote() async {
    final workers = await _api.fetchAll();
    await _dbHelper.upsertRemoteWorkers(workers);
    return workers.length;
  }
}
