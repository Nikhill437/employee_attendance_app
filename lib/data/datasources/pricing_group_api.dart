import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
import '../../core/network/api_routes.dart';
import '../models/pricing_group_model.dart';

/// Remote datasource for the backend's pricing-group catalog
/// (`GET pricing-groups/list`).
class PricingGroupApi {
  final ApiClient _client;

  PricingGroupApi({ApiClient? client}) : _client = client ?? ApiClient();

  /// Walks `page`/`totalPages` until exhausted — same pattern as
  /// `WorkerListApi.fetchAll`. Confirmed response shape: `{"success": true,
  /// "data": [{"pricing_group_id": ..., "group_name": ..., "min_rate":
  /// ..., "max_rate": ..., ...}], "totalPages": ..., "currentPage": ...}`.
  Future<List<PricingGroup>> fetchAll({int limit = 100}) async {
    final results = <PricingGroup>[];
    var page = 1;

    while (true) {
      final data = await _client.post(
        '${ApiRoutes.pricingGroupsList}?page=$page&limit=$limit'
        '&sortBy=pricing_group_id&order=DESC',
      );
      results.addAll(_rows(data).map(PricingGroup.fromRemote));

      final totalPages = data is Map ? (data['totalPages'] as int? ?? 1) : 1;
      if (page >= totalPages) break;
      page++;
    }

    return results;
  }

  List<Map<String, dynamic>> _rows(dynamic data) {
    if (data is! Map || data['data'] is! List) {
      throw ApiException('Unexpected pricing groups response from the server.');
    }
    return (data['data'] as List).cast<Map<String, dynamic>>();
  }
}
