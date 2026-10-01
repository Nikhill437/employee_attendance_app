import 'dart:developer';

import '../../core/network/api_client.dart';
import '../../core/network/api_routes.dart';
import '../models/remote_worker_task_model.dart';

/// Remote datasource for the backend's worker-task assignment list — two
/// endpoints sharing the same row shape (see RemoteWorkerTaskRecord):
/// [workerTaskList] is the full roster, un-paginated (a single call);
/// [serverWorkerTaskList] is the delta endpoint, keyed off the current UTC
/// time instead.
class WorkerTaskListApi {
  final ApiClient _client;

  WorkerTaskListApi({ApiClient? client}) : _client = client ?? ApiClient();

  /// POST attendance/worker_task_list — the dashboard's "Fetch Worker
  /// Tasks" button. A single call, no pagination: confirmed response
  /// envelope is `{"data": [...]}`.
  Future<List<RemoteWorkerTaskRecord>> workerTaskList() async {
    final results = <RemoteWorkerTaskRecord>[];
    final data = await _client.post(ApiRoutes.workerTaskList);
    if (data is! Map || data['data'] is! List) return results;
    log(data.toString(), name: 'WorkerTaskListApi.workerTaskList');
    final rows = data['data'] as List;
    results.addAll(
      rows.map(
        (row) => RemoteWorkerTaskRecord.fromJson(row as Map<String, dynamic>),
      ),
    );
    return results;
  }

  /// POST attendance/server_time_worker_task_list — same row shape as
  /// [workerTaskList], but keyed off the current UTC time (`{"date":
  /// ...}`) instead of pagination, mirroring
  /// WorkerListApi.fetchServerWorkers.
  Future<List<RemoteWorkerTaskRecord>> serverWorkerTaskList() async {
    final results = <RemoteWorkerTaskRecord>[];
    try {
      final currentUtcTime = DateTime.now().toUtc().toIso8601String();
      final data = await _client.post(
        ApiRoutes.serverWorkerTaskList,
        data: {'date': currentUtcTime},
      );
      if (data is! Map || data['data'] is! List) return results;
      log(data.toString(), name: 'WorkerTaskListApi.serverWorkerTaskList');
      final rows = data['data'] as List;
      results.addAll(
        rows.map(
          (row) =>
              RemoteWorkerTaskRecord.fromJson(row as Map<String, dynamic>),
        ),
      );
    } catch (e) {
      log(
        'Error fetching server-time worker tasks: $e',
        name: 'WorkerTaskListApi.serverWorkerTaskList',
      );
    }
    return results;
  }
}
