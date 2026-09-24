import '../../core/network/api_exception.dart';
import '../datasources/worker_sync_api.dart';
import 'employee_repository.dart';

/// Pushes one locally enrolled worker to the backend
/// (`POST attendance/sync-worker`) — the endpoint only takes one worker per
/// call, so this is triggered per-card from the worker list rather than as
/// a single "sync everyone" action.
class WorkerSyncRepository {
  final WorkerSyncApi _api;
  final EmployeeRepository _employees;

  WorkerSyncRepository({WorkerSyncApi? api, EmployeeRepository? employees})
    : _api = api ?? WorkerSyncApi(),
      _employees = employees ?? EmployeeRepository();

  /// Syncs the worker enrolled under [employeeId] (their National ID), then
  /// marks them synced locally so the worker list can show it. Throws if
  /// that ID isn't enrolled, or lets an [ApiException] from the network
  /// call propagate — the caller decides how to surface either.
  Future<void> syncWorker(String employeeId) async {
    final worker = await _employees.findByEmployeeId(employeeId);
    if (worker == null) {
      throw ArgumentError('No worker enrolled with National ID $employeeId');
    }
    int? realWorkerId;
    try {
      realWorkerId = await _api.syncWorker(worker);
    } on ApiException catch (e) {
      // 409 means the backend already has this National ID — a previous
      // sync succeeded server-side but the local `is_synced` flag never
      // got set (e.g. a reinstalled/reset local DB). That's "already
      // synced", not a failure, so fall through to markSynced below
      // instead of rethrowing.
      if (e.statusCode != 409) rethrow;
    }
    await _employees.markSynced(employeeId, realWorkerId: realWorkerId);
  }
}
