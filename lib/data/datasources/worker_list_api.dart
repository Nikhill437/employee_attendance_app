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

  /// Fetches every worker, walking `page`/`totalPages` until exhausted.
  /// Confirmed response shape: `{"data": [...], "totalPages": ...,
  /// "currentPage": ...}`.
  Future<List<RemoteWorkerRecord>> fetchAll({int limit = 100}) async {
    final results = <RemoteWorkerRecord>[];
    var page = 1;

    while (true) {
      final data = await _client.post(
        '${ApiRoutes.workerList}?page=$page&limit=$limit',
      );
      if (data is! Map || data['data'] is! List) break;
      log(data.toString(), name: 'WorkerListApi.fetchAll');
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

  /// POST attendance/worker_data — the dashboard's "Fetch Workers" button,
  /// mirroring AttendanceLookupApi.fetchServertimeDepartment/Task. Not
  /// paginated (no `totalPages` in the response), unlike [fetchAll].
  /// [date] is the checkpoint to ask the server for changes since — see
  /// WorkerImportRepository.importFromServerTime, which reads it back from
  /// `workers.server_time` (stamped there by [fetchAll]'s own caller)
  /// rather than this method picking "now" itself.
  Future<List<RemoteWorkerRecord>> fetchServerWorkers({
    required String date,
  }) async {
    final results = <RemoteWorkerRecord>[];
    try {
      final data = await _client.post(
        ApiRoutes.serverTimeWorkers,
        data: {'date': date},
      );
      if (data is! Map || data['data'] is! List) return results;
      log(data.toString(), name: 'WorkerListApi.fetchServerWorkers');
      final rows = data['data'] as List;
      results.addAll(
        rows.map(
          (row) => RemoteWorkerRecord.fromJson(row as Map<String, dynamic>),
        ),
      );
    } catch (e) {
      log('Error fetching server-time workers: $e', name: 'WorkerListApi.fetchServerWorkers');
    }
    return results;
  }
}
