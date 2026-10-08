import 'package:shared_preferences/shared_preferences.dart';

import '../../core/utils/app_time.dart';
import '../datasources/database_helper.dart';
import '../datasources/worker_list_api.dart';
import 'server_sync_time_store.dart';

/// Where a full employee-list import ([WorkerImportRepository.importFromRemote])
/// got to before it was interrupted (app killed, connection lost, etc.) —
/// read by the dashboard to offer Resume instead of re-fetching every page
/// from the start. [fetchedSoFar] and [syncStartedAt] carry over into the
/// resumed run so its progress display and `server_time` stamping pick up
/// where the interrupted one left off, rather than looking like a second,
/// unrelated sync.
class WorkerImportCheckpoint {
  final int nextPage;
  final int totalPages;
  final int fetchedSoFar;
  final String syncStartedAt;

  const WorkerImportCheckpoint({
    required this.nextPage,
    required this.totalPages,
    required this.fetchedSoFar,
    required this.syncStartedAt,
  });
}

/// Imports the backend's worker roster into the local `workers` table,
/// upserted by National ID.
class WorkerImportRepository {
  static const String _hasFetchedWorkersKey = 'worker_import_has_fetched';

  // --- Interrupted full-import checkpoint (see WorkerImportCheckpoint) ---
  static const String _resumeNextPageKey = 'worker_import_resume_next_page';
  static const String _resumeTotalPagesKey = 'worker_import_resume_total_pages';
  static const String _resumeFetchedKey = 'worker_import_resume_fetched_count';
  static const String _resumeSyncStartedAtKey =
      'worker_import_resume_sync_started_at';

  /// The UTC time the last successful worker fetch started at. Sent as the
  /// `date` of the next server-time fetch, so only changes after it come back.
  static const ServerSyncTimeStore _defaultLastSyncTime = ServerSyncTimeStore(
    'worker_last_server_sync_time',
  );

  /// `_lastUpdatedCountsServerTime`: the dashboard's badge counts send this
  /// as `serverTime`. Every successful worker-list fetch replaces it with
  /// that fetch's start time, and a failed fetch leaves it unchanged. The
  /// counts API only reads it.
  static const ServerSyncTimeStore _defaultLastUpdatedCountsServerTime =
      ServerSyncTimeStore('last_updated_counts_server_time');

  final WorkerListApi _api;
  final DatabaseHelper _dbHelper;
  final ServerSyncTimeStore _lastSyncTime;
  final ServerSyncTimeStore _lastUpdatedCountsServerTime;

  WorkerImportRepository({
    WorkerListApi? api,
    DatabaseHelper? dbHelper,
    ServerSyncTimeStore? lastSyncTime,
    ServerSyncTimeStore? lastUpdatedCountsServerTime,
  }) : _api = api ?? WorkerListApi(),
       _dbHelper = dbHelper ?? DatabaseHelper(),
       _lastSyncTime = lastSyncTime ?? _defaultLastSyncTime,
       _lastUpdatedCountsServerTime =
           lastUpdatedCountsServerTime ?? _defaultLastUpdatedCountsServerTime;

  /// Runs only after a worker fetch and upsert have both succeeded, so a
  /// failed fetch never moves either checkpoint.
  Future<void> _recordSuccessfulFetch(String syncStartedAt) async {
    await _lastSyncTime.save(syncStartedAt);
    await _lastUpdatedCountsServerTime.save(syncStartedAt);
  }

  /// Where a previous [importFromRemote] got interrupted, if it was — the
  /// dashboard checks this before starting a full import so it can offer
  /// Resume instead of silently re-fetching from page 1.
  Future<WorkerImportCheckpoint?> getInterruptedImport() async {
    final prefs = await SharedPreferences.getInstance();
    final nextPage = prefs.getInt(_resumeNextPageKey);
    final totalPages = prefs.getInt(_resumeTotalPagesKey);
    final fetchedSoFar = prefs.getInt(_resumeFetchedKey);
    final syncStartedAt = prefs.getString(_resumeSyncStartedAtKey);
    if (nextPage == null ||
        totalPages == null ||
        fetchedSoFar == null ||
        syncStartedAt == null) {
      return null;
    }
    return WorkerImportCheckpoint(
      nextPage: nextPage,
      totalPages: totalPages,
      fetchedSoFar: fetchedSoFar,
      syncStartedAt: syncStartedAt,
    );
  }

  Future<void> _saveCheckpoint(WorkerImportCheckpoint checkpoint) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_resumeNextPageKey, checkpoint.nextPage);
    await prefs.setInt(_resumeTotalPagesKey, checkpoint.totalPages);
    await prefs.setInt(_resumeFetchedKey, checkpoint.fetchedSoFar);
    await prefs.setString(_resumeSyncStartedAtKey, checkpoint.syncStartedAt);
  }

  /// Discards a stale/finished checkpoint — call before starting over from
  /// page 1 (the dashboard's "Start From Beginning" choice) or once an
  /// import finishes every page.
  Future<void> clearInterruptedImport() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_resumeNextPageKey);
    await prefs.remove(_resumeTotalPagesKey);
    await prefs.remove(_resumeFetchedKey);
    await prefs.remove(_resumeSyncStartedAtKey);
  }

  /// Fetches every worker from the backend and upserts them locally, page
  /// by page, stamping every row's `server_time` with [resumeFrom]'s
  /// original start time when resuming, or the current UTC instant
  /// otherwise. Each page is upserted and checkpointed as soon as it
  /// arrives — not buffered until the whole roster is in — so an
  /// interruption (app killed, connection lost) loses at most one page's
  /// worth of progress, not the whole import; [getInterruptedImport] is
  /// how the dashboard finds that checkpoint again afterwards. The
  /// checkpoint (and the stored last-sync time) is only advanced/cleared
  /// once every page has succeeded.
  Future<int> importFromRemote({
    WorkerImportCheckpoint? resumeFrom,
    void Function(int fetchedSoFar, int currentPage, int totalPages)?
    onProgress,
  }) async {
    final syncStartedAt =
        resumeFrom?.syncStartedAt ?? DateTime.now().toUtc().toIso8601String();
    var fetchedSoFar = resumeFrom?.fetchedSoFar ?? 0;

    await _api.fetchAll(
      startPage: resumeFrom?.nextPage ?? 1,
      onPage: (rows, currentPage, totalPages) async {
        await _dbHelper.upsertRemoteWorkers(rows, serverTime: syncStartedAt);
        fetchedSoFar += rows.length;
        await _saveCheckpoint(
          WorkerImportCheckpoint(
            nextPage: currentPage + 1,
            totalPages: totalPages,
            fetchedSoFar: fetchedSoFar,
            syncStartedAt: syncStartedAt,
          ),
        );
        onProgress?.call(fetchedSoFar, currentPage, totalPages);
      },
    );

    await clearInterruptedImport();
    await _recordSuccessfulFetch(syncStartedAt);
    return fetchedSoFar;
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
    await _recordSuccessfulFetch(syncStartedAt);
    return workers.length;
  }

  /// What the "Fetch Workers" button actually calls: the very first tap
  /// ever (on this device install) pulls the full roster
  /// ([importFromRemote], `POST attendance/list`) so there's a complete
  /// local baseline; every tap after that only pulls what changed
  /// ([importFromServerTime], `POST attendance/worker_data`). The "has
  /// fetched before" flag is persisted (survives app restarts), not just
  /// held in memory.
  /// [onProgress]/[resumeFrom] only ever apply to the first-ever (full)
  /// fetch — [importFromServerTime] is a single call with nothing
  /// incremental to report or resume.
  Future<int> importWorkers({
    WorkerImportCheckpoint? resumeFrom,
    void Function(int fetchedSoFar, int currentPage, int totalPages)?
    onProgress,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final hasFetchedBefore = prefs.getBool(_hasFetchedWorkersKey) ?? false;
    final count = hasFetchedBefore
        ? await importFromServerTime()
        : await importFromRemote(
            resumeFrom: resumeFrom,
            onProgress: onProgress,
          );
    await prefs.setBool(_hasFetchedWorkersKey, true);
    return count;
  }

  /// The last successful [importWorkers] fetch's start time, in the
  /// supervisor's own timezone (see AppTime) — null if none has run yet.
  /// Shown on the dashboard's Employee List Data card.
  Future<DateTime?> lastSyncedAt() async {
    final stored = await _lastSyncTime.read();
    final parsed = stored == null ? null : DateTime.tryParse(stored);
    return parsed == null ? null : AppTime.toUserTime(parsed);
  }

  /// The Employee List Data card's Clear action: wipes the local worker
  /// roster (and their task assignments/attendance logs) and resets the
  /// "has fetched before" checkpoint, so the next [importWorkers] pulls the
  /// full roster again instead of only what changed since the old one.
  Future<void> clearLocal() async {
    await _dbHelper.clearAllWorkers();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_hasFetchedWorkersKey);
    await _lastSyncTime.clear();
    await clearInterruptedImport();
  }
}
