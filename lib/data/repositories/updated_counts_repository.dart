import '../datasources/updated_counts_api.dart';
import '../models/updated_counts_model.dart';

/// How many worker/department/task records the server reports as changed —
/// purely a read-through to [UpdatedCountsApi], no local caching, since
/// it's only ever shown live on the dashboard.
class UpdatedCountsRepository {
  final UpdatedCountsApi _api;

  UpdatedCountsRepository({UpdatedCountsApi? api})
    : _api = api ?? UpdatedCountsApi();

  Future<UpdatedCounts> fetchUpdatedCounts() => _api.fetchUpdatedCounts();
}
