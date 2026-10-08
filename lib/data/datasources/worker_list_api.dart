import 'dart:developer';

import '../../core/network/api_client.dart';
import '../../core/network/api_routes.dart';
import '../models/remote_worker_model.dart';

/// Remote datasource for the backend's full worker roster
/// (`POST attendance/list`), used to import/refresh the local `workers`
/// table from the server.
class WorkerListApi {
  final ApiClient _client;

  WorkerListApi({ApiClient? client}) : _client = client ?? ApiClient();

  /// Fetches every worker from [startPage] onward, walking `page`/
  /// `totalPages` until exhausted. Confirmed response shape: `{"data":
  /// [...], "totalPages": ..., "currentPage": ...}`. Each page's rows are
  /// handed to [onPage] as they arrive — with potentially thousands of
  /// workers across dozens of pages, this lets the caller persist (and
  /// checkpoint) them page by page instead of buffering the whole roster
  /// in memory and losing all progress if the app is killed partway
  /// through (see WorkerImportRepository.importFromRemote, the only
  /// caller, which does exactly that) — rather than this method
  /// collecting and returning one big list itself.
  Future<void> fetchAll({
    int limit = 100,
    int startPage = 1,
    required Future<void> Function(
      List<RemoteWorkerRecord> rows,
      int currentPage,
      int totalPages,
    )
    onPage,
  }) async {
    var page = startPage;

    while (true) {
      final data = await _client.post(
        '${ApiRoutes.workerList}?page=$page&limit=$limit',
      );
      if (data is! Map || data['data'] is! List) break;
      log(data.toString(), name: 'WorkerListApi.fetchAll');
      final rows = (data['data'] as List)
          .map(
            (row) => RemoteWorkerRecord.fromJson(row as Map<String, dynamic>),
          )
          .toList();

      final totalPages = data['totalPages'] as int? ?? 1;
      await onPage(rows, page, totalPages);
      if (page >= totalPages) break;
      page++;
    }
  }

  /// POST attendance/worker_data — the dashboard's "Fetch Workers" button,
  /// mirroring AttendanceLookupApi.fetchServertimeDepartment/Task. Walks
  /// `page`/`totalPages` the same way [fetchAll] does; a response with no
  /// `totalPages` is treated as a single page. [date] is the checkpoint to
  /// ask the server for changes since — see
  /// WorkerImportRepository.importFromServerTime, which reads it back from
  /// `workers.server_time` (stamped there by [fetchAll]'s own caller)
  /// rather than this method picking "now" itself.
  ///
  /// Errors propagate (not swallowed) so the caller can tell a failed fetch
  /// from an empty one — WorkerImportRepository only advances its stored
  /// sync time after this succeeds.
  Future<List<RemoteWorkerRecord>> fetchServerWorkers({
    required String date,
    int limit = 100,
  }) async {
    final results = <RemoteWorkerRecord>[];
    var page = 1;

    while (true) {
      final data = await _client.post(
        '${ApiRoutes.serverTimeWorkers}?page=$page&limit=$limit',
        data: {'date': date},
      );
      if (data is! Map || data['data'] is! List) break;
      log(data.toString(), name: 'WorkerListApi.fetchServerWorkers');
      final rows = data['data'] as List;
      results.addAll(
        rows.map(
          (row) => RemoteWorkerRecord.fromJson(row as Map<String, dynamic>),
        ),
      );

      final totalPages = data['totalPages'] as int? ?? 1;
      if (page >= totalPages) break;
      page++;
    }

    return results;
  }
}
