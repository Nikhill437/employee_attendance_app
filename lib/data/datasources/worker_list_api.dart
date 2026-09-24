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
}
