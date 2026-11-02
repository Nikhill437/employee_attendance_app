import '../datasources/database_helper.dart';
import '../datasources/pricing_group_api.dart';
import '../models/pricing_group_model.dart';

/// The pricing-group catalog (`GET pricing-groups/list`) — fetched on
/// supervisor login (see SupervisorAuthRepository.authenticate) and cached
/// locally, so AssignTaskViewModel's task-change-request dialog can show
/// group names without a network round trip.
class PricingGroupRepository {
  final PricingGroupApi _api;
  final DatabaseHelper _dbHelper;

  PricingGroupRepository({PricingGroupApi? api, DatabaseHelper? dbHelper})
    : _api = api ?? PricingGroupApi(),
      _dbHelper = dbHelper ?? DatabaseHelper();

  /// Fetches every pricing group and upserts the local cache. Errors
  /// propagate — callers that don't want a failed fetch here to disrupt
  /// anything else (e.g. login) catch it themselves.
  Future<int> importPricingGroups() async {
    final groups = await _api.fetchAll();
    await _dbHelper.upsertPricingGroups(groups);
    return groups.length;
  }

  Future<List<PricingGroup>> getAll() => _dbHelper.getPricingGroups();

  Future<PricingGroup?> getById(int id) => _dbHelper.getPricingGroupById(id);
}
