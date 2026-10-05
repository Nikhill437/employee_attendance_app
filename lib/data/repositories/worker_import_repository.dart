import 'package:shared_preferences/shared_preferences.dart';

import '../datasources/database_helper.dart';
import '../datasources/worker_list_api.dart';
import 'server_sync_time_store.dart';

/// Imports the backend's worker roster into the local `workers` table,
/// upserted by National ID.
class WorkerImportRepository {
  static const String _hasFetchedWorkersKey = 'worker_import_has_fetched';

  /// The UTC time the last successful worker fetch started at. Sent as the
  /// `date` of the next server-time fetch, so only changes after it come back.
  static const ServerSyncTimeStore _defaultLastSyncTime = ServerSyncTimeStore(
    'worker_last_server_sync_time',
  );

  final WorkerListApi _api;
  final DatabaseHelper _dbHelper;
  final ServerSyncTimeStore _lastSyncTime;

  WorkerImportRepository({
    WorkerListApi? api,
    DatabaseHelper? dbHelper,
    ServerSyncTimeStore? lastSyncTime,
  }) : _api = api ?? WorkerListApi(),
       _dbHelper = dbHelper ?? DatabaseHelper(),
       _lastSyncTime = lastSyncTime ?? _defaultLastSyncTime;

  /// Fetches every worker from the backend and upserts them locally,
  /// stamping every row's `server_time` with the UTC instant of this
  /// fetch. That instant also becomes the stored last worker sync time, so
  /// the next [importFromServerTime] asks only for changes after it.
  Future<int> importFromRemote() async {
    final syncStartedAt = DateTime.now().toUtc().toIso8601String();
    final workers = await _api.fetchAll();
    await _dbHelper.upsertRemoteWorkers(workers, serverTime: syncStartedAt);
    await _lastSyncTime.save(syncStartedAt);
    return workers.length;
  }

  /// The dashboard's "Fetch Workers" button (`POST attendance/worker_data`)
  /// — same upsert-by-National-ID as [importFromRemote], just backed by
  /// [WorkerListApi.fetchServerWorkers] instead of the full paginated
  /// list.
  ///
  /// The request's `date` is the stored last worker sync time. With none
  /// stored yet it falls back to the newest `workers.server_time`, and to
  /// right now only if no full fetch has ever run.
  ///
  /// The stored time is only advanced after the fetch and upsert both
  /// succeed, and it's the time this fetch started, not the time it
  /// finished. A change saved on the server mid-fetch is then picked up by
  /// the next fetch rather than missed. A failed fetch leaves the stored
  /// time unchanged, so the next attempt asks for the same changes again.
  Future<int> importFromServerTime() async {
    final syncStartedAt = DateTime.now().toUtc().toIso8601String();
    final serverTime =
        await _lastSyncTime.read() ??
        await _dbHelper.getLatestWorkerServerTime() ??
        syncStartedAt;
    final workers = await _api.fetchServerWorkers(date: serverTime);
    await _dbHelper.upsertRemoteWorkers(workers);
    await _lastSyncTime.save(syncStartedAt);
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
