import 'dart:developer';

import '../../core/network/api_client.dart';
import '../../core/network/api_routes.dart';
import '../models/updated_counts_model.dart';
import '../repositories/server_sync_time_store.dart';

/// Remote datasource for how many worker/department/task records have
/// changed on the server since the previous count check — the dashboard's
/// badge counts.
class UpdatedCountsApi {
  /// The server time of the last successful count check. Sent as `date` on
  /// the next call, so each call only reports what changed since the one
  /// before it.
  static const ServerSyncTimeStore _defaultLastUpdatedCountsServerTime =
      ServerSyncTimeStore('last_updated_counts_server_time');

  final ApiClient _client;
  final ServerSyncTimeStore _lastUpdatedCountsServerTime;

  UpdatedCountsApi({
    ApiClient? client,
    ServerSyncTimeStore? lastUpdatedCountsServerTime,
  }) : _client = client ?? ApiClient(),
       _lastUpdatedCountsServerTime =
           lastUpdatedCountsServerTime ?? _defaultLastUpdatedCountsServerTime;

  /// POST attendance/updated-counts. Sends the previous call's server time
  /// as `date` (the current UTC time on the first call, when nothing is
  /// stored yet). After a successful response, that call's own server time
  /// is saved as the next `date`. The response has no server time of its
  /// own, so the time captured just before the request is what gets saved.
  /// A failed call stores nothing, so the next call repeats the same window.
  /// Confirmed response shape:
  /// `{"success": true, "data": {"worker_count": ..., "department_count":
  /// ..., "task_count": ...}}`. Returns [UpdatedCounts.zero] on any failure
  /// or unexpected shape — a badge silently staying at zero is preferable
  /// to surfacing an error for what's just a "what's new" hint.
  Future<UpdatedCounts> fetchUpdatedCounts() async {
    try {
      final currentServerTime = DateTime.now().toUtc().toIso8601String();
      final previousServerTime =
          await _lastUpdatedCountsServerTime.read() ?? currentServerTime;
      final data = await _client.post(
        ApiRoutes.count,
        data: {'date': previousServerTime},
      );
      if (data is! Map || data['data'] is! Map) {
        return UpdatedCounts.zero;
      }
      await _lastUpdatedCountsServerTime.save(currentServerTime);
      return UpdatedCounts.fromJson(data['data'] as Map<String, dynamic>);
    } catch (e) {
      log(
        'Error fetching updated counts: $e',
        name: 'UpdatedCountsApi.fetchUpdatedCounts',
      );
      return UpdatedCounts.zero;
    }
  }
}
