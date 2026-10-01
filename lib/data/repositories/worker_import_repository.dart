import 'package:shared_preferences/shared_preferences.dart';

import '../datasources/database_helper.dart';
import '../datasources/worker_list_api.dart';

/// Imports the backend's worker roster into the local `workers` table,
/// upserted by National ID.
class WorkerImportRepository {
  static const String _hasFetchedWorkersKey = 'worker_import_has_fetched';

  final WorkerListApi _api;
  final DatabaseHelper _dbHelper;

  WorkerImportRepository({WorkerListApi? api, DatabaseHelper? dbHelper})
    : _api = api ?? WorkerListApi(),
      _dbHelper = dbHelper ?? DatabaseHelper();

  /// Fetches every worker from the backend and upserts them locally,
  /// stamping every row's `server_time` with the UTC instant of this
  /// fetch — the checkpoint [importFromServerTime] later reads back to
  /// ask the server for changes since exactly this call, rather than
  /// picking "now" itself.
  Future<int> importFromRemote() async {
    final currentUtcTime = DateTime.now().toUtc().toIso8601String();
    final workers = await _api.fetchAll();
    await _dbHelper.upsertRemoteWorkers(workers, serverTime: currentUtcTime);
    return workers.length;
  }

  /// The dashboard's "Fetch Workers" button (`POST attendance/worker_data`)
  /// — same upsert-by-National-ID as [importFromRemote], just backed by
  /// [WorkerListApi.fetchServerWorkers] instead of the full paginated
  /// list. Sends whatever [DatabaseHelper.getLatestWorkerServerTime]
  /// returns (the checkpoint [importFromRemote] stamped) as the request's
  /// `date` — falling back to right now only if a full fetch has never
  /// run, so this is still usable on its own.
  Future<int> importFromServerTime() async {
    final serverTime =
        await _dbHelper.getLatestWorkerServerTime() ??
        DateTime.now().toUtc().toIso8601String();
    final workers = await _api.fetchServerWorkers(date: serverTime);
    await _dbHelper.upsertRemoteWorkers(workers);
    return workers.length;
  }

  /// What the "Fetch Workers" button actually calls: the very first tap
  /// ever (on this device install) pulls the full roster
  /// ([importFromRemote], `POST attendance/list`) so there's a complete
  /// local baseline; every tap after that only pulls what changed
  /// ([importFromServerTime], `POST attendance/worker_data`). The "has
  /// fetched before" flag is persisted (survives app restarts), not just
  /// held in memory.
  Future<int> importWorkers() async {
    final prefs = await SharedPreferences.getInstance();
    final hasFetchedBefore = prefs.getBool(_hasFetchedWorkersKey) ?? false;
    final count = hasFetchedBefore
        ? await importFromServerTime()
        : await importFromRemote();
    await prefs.setBool(_hasFetchedWorkersKey, true);
    return count;
  }
}
