import 'dart:developer';

import '../../core/network/api_client.dart';
import '../../core/network/api_routes.dart';
import '../models/updated_counts_model.dart';
import '../repositories/server_sync_time_store.dart';

/// Remote datasource for how many worker, task, and department records have
/// changed on the server since each one's last successful download — the
/// dashboard's badge counts. Each count has its own endpoint and its own
/// stored server time.
class UpdatedCountsApi {
  /// Worker: written by WorkerImportRepository after each successful worker
  /// fetch. This class only reads it.
  static const ServerSyncTimeStore _defaultWorkerServerTime =
      ServerSyncTimeStore('last_updated_counts_server_time');

  final ApiClient _client;
  final ServerSyncTimeStore _workerServerTime;
  final ServerSyncTimeStore _taskServerTime;
  final ServerSyncTimeStore _departmentServerTime;

  UpdatedCountsApi({
    ApiClient? client,
    ServerSyncTimeStore? lastUpdatedCountsServerTime,
    ServerSyncTimeStore? taskServerTime,
    ServerSyncTimeStore? departmentServerTime,
  }) : _client = client ?? ApiClient(),
       _workerServerTime =
           lastUpdatedCountsServerTime ?? _defaultWorkerServerTime,
       _taskServerTime = taskServerTime ?? lastTaskServerTime,
       _departmentServerTime = departmentServerTime ?? lastDepartmentServerTime;

  /// Fetches all three counts, each from its own endpoint with its own
  /// stored time as `date`. A count that fails shows zero without affecting
  /// the other two. Nothing is stored here, so a count check never moves a
  /// checkpoint.
  Future<UpdatedCounts> fetchUpdatedCounts() async {
    final workers = await _fetchCount(ApiRoutes.workerCount, _workerServerTime);
    final tasks = await _fetchCount(ApiRoutes.taskCount, _taskServerTime);
    final departments = await _fetchCount(
      ApiRoutes.departmentCount,
      _departmentServerTime,
    );
    return UpdatedCounts(
      workerCount: workers.workerCount,
      departmentCount: departments.departmentCount,
      taskCount: tasks.taskCount,
    );
  }

  /// POST [path] with the stored [store] time as `date` (the current UTC
  /// time when nothing is stored yet). Returns [UpdatedCounts.zero] on any
  /// failure or unexpected shape — a badge silently staying at zero is
  /// preferable to surfacing an error for what's just a "what's new" hint.
  Future<UpdatedCounts> _fetchCount(
    String path,
    ServerSyncTimeStore store,
  ) async {
    try {
      final serverTime =
          await store.read() ?? DateTime.now().toUtc().toIso8601String();
      final data = await _client.post(path, data: {'date': serverTime});
      if (data is! Map || data['data'] is! Map) {
        return UpdatedCounts.zero;
      }
      return UpdatedCounts.fromJson(data['data'] as Map<String, dynamic>);
    } catch (e) {
      log(
        'Error fetching updated counts from $path: $e',
        name: 'UpdatedCountsApi',
      );
      return UpdatedCounts.zero;
    }
  }
}
