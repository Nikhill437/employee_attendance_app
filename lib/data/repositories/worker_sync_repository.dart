import '../datasources/worker_sync_api.dart';
import 'employee_repository.dart';
import 'worker_edit_queue.dart';

/// Pushes one locally enrolled worker to the backend
/// (`POST attendance/sync-worker`) — the endpoint only takes one worker per
/// call, so this is triggered per-card from the worker list rather than as
/// a single "sync everyone" action.
class WorkerSyncRepository {
  final WorkerSyncApi _api;
  final EmployeeRepository _employees;
  final WorkerEditQueue _editQueue;

  WorkerSyncRepository({
    WorkerSyncApi? api,
    EmployeeRepository? employees,
    WorkerEditQueue? editQueue,
  }) : _api = api ?? WorkerSyncApi(),
       _employees = employees ?? EmployeeRepository(),
       _editQueue = editQueue ?? WorkerEditQueue();

  /// Syncs the worker enrolled under [employeeId] (their National ID), then
  /// marks them synced locally so the worker list can show it. Throws if
  /// that ID isn't enrolled, or lets an [ApiException] from the network
  /// call propagate — the caller decides how to surface either.
  Future<void> syncWorker(String employeeId) async {
    final worker = await _employees.findByEmployeeId(employeeId);
    if (worker == null) {
      throw ArgumentError('No worker enrolled with National ID $employeeId');
    }
    final offlineId = worker.id;
    final realId = offlineId == null
        ? null
        : await _employees.getRemoteWorkerId(offlineId);
    if (offlineId != null && realId != null) {
      // The backend already has this worker — send just the changed fields.
      final changes = await _editQueue.pendingFor(offlineId);
      await _api.updateWorker(realWorkerId: realId, changes: changes);
      await _editQueue.clear(offlineId);
      await _employees.markSynced(employeeId, realWorkerId: realId);
      return;
    }

    // Any failure here, including a 409 Conflict (the backend already has
    // this National ID), propagates as an ApiException before anything local
    // is touched. The worker keeps is_synced = 0 and its local record and
    // edit queue stay as they were, so the sync can be retried. The caller
    // shows the server's message.
    final realWorkerId = await _api.syncWorker(worker);
    if (offlineId != null) await _editQueue.clear(offlineId);
    await _employees.markSynced(employeeId, realWorkerId: realWorkerId);
  }
}
