import 'dart:developer';

import '../../core/network/api_client.dart';
import '../../core/network/api_routes.dart';
import '../models/updated_counts_model.dart';

/// Remote datasource for how many worker/department/task records have
/// changed on the server since [date] — the dashboard's badge counts.
class UpdatedCountsApi {
  final ApiClient _client;

  UpdatedCountsApi({ApiClient? client}) : _client = client ?? ApiClient();

  /// POST attendance/updated-counts. Confirmed response shape:
  /// `{"success": true, "data": {"worker_count": ..., "department_count":
  /// ..., "task_count": ...}}`. Returns [UpdatedCounts.zero] on any failure
  /// or unexpected shape — a badge silently staying at zero is preferable
  /// to surfacing an error for what's just a "what's new" hint.
  Future<UpdatedCounts> fetchUpdatedCounts() async {
    try {
      final currentUtcTime = DateTime.now().toUtc().toIso8601String();
      final data = await _client.post(
        ApiRoutes.count,
        data: {'date': currentUtcTime},
      );
      if (data is! Map || data['data'] is! Map) {
        return UpdatedCounts.zero;
      }
      return UpdatedCounts.fromJson(data['data'] as Map<String, dynamic>);
    } catch (e) {
      log('Error fetching updated counts: $e', name: 'UpdatedCountsApi.fetchUpdatedCounts');
      return UpdatedCounts.zero;
    }
  }
}
