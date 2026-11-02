import '../../core/network/api_exception.dart';
import '../datasources/database_helper.dart';
import '../datasources/task_change_request_api.dart';
import '../models/task_change_request_result_model.dart';
import '../models/task_pricing_change_request_model.dart';

/// Local-draft-then-submit task-change requests — raised when
/// AssignTaskViewModel.save finds the newly picked task outside the
/// worker's current pricing group, stored locally first, and only sent to
/// the backend (`POST attendance/request-task-change`) once the supervisor
/// taps Sync on the worker list (see WorkerListViewModel.
/// syncTaskChangeRequest). Same offline-first shape as TaskSyncRepository.
class TaskChangeRequestRepository {
  final TaskChangeRequestApi _api;
  final DatabaseHelper _dbHelper;

  TaskChangeRequestRepository({
    TaskChangeRequestApi? api,
    DatabaseHelper? dbHelper,
  }) : _api = api ?? TaskChangeRequestApi(),
       _dbHelper = dbHelper ?? DatabaseHelper();

  /// Every worker's still-pending request, keyed by local worker id — see
  /// DatabaseHelper.getPendingTaskChangeRequestsByWorker.
  Future<Map<int, TaskPricingChangeRequest>> getPendingRequestsByWorker() =>
      _dbHelper.getPendingTaskChangeRequestsByWorker();

  /// Stores a new draft locally — not submitted yet (see [submit]).
  /// Returns its local id.
  Future<int> createLocalRequest({
    required int workerId,
    required int taskId,
    int? currentPricingGroupId,
    required int proposedPricingGroupId,
    num? oldRate,
    required num newRate,
    String? reason,
    required int requestedBy,
  }) => _dbHelper.createTaskChangeRequest(
    workerId: workerId,
    taskId: taskId,
    currentPricingGroupId: currentPricingGroupId,
    proposedPricingGroupId: proposedPricingGroupId,
    oldRate: oldRate,
    newRate: newRate,
    reason: reason,
    requestedBy: requestedBy,
  );

  /// Submits the draft at local id [localId]. Throws a [StateError] if the
  /// worker themselves hasn't been synced yet (the backend needs their
  /// real worker_id — same precondition as
  /// TaskSyncRepository.syncWorkerTasks) or if the draft itself can't be
  /// found. Leaves the draft as-is (still `is_synced = 0`) on any failure,
  /// so the supervisor can retry — only a successful response marks it
  /// synced.
  Future<void> submit(int localId) async {
    final request = await _dbHelper.getTaskChangeRequestById(localId);
    if (request == null) {
      throw StateError('This task change request no longer exists');
    }

    final realWorkerId = await _dbHelper.getRemoteWorkerId(
      request.proposedWorkerId,
    );
    if (realWorkerId == null) {
      throw StateError(
        'Sync this worker before submitting a task change request',
      );
    }

    final task = await _dbHelper.getTaskById(request.taskId);
    final divisionId = await _dbHelper.getWorkerDivisionId(
      request.proposedWorkerId,
    );

    TaskChangeRequestResult result;
    try {
      result = await _api.assignTask(
        workerId: realWorkerId,
        taskId: request.taskId,
        departmentId: task?.departmentId ?? 0,
        divisionId: divisionId ?? 0,
        note: request.reason,
      );
    } on ApiException catch (e) {
      // A 409 here means the backend already applied this exact change
      // (confirmed against a real response: "Task ... is already assigned
      // to employee ... for today") — almost always because an earlier
      // submit attempt DID succeed server-side but then failed to record
      // that locally (e.g. the UNIQUE-constraint bug this guards against
      // above). Treating it as resolved rather than rethrowing is what
      // stops a stuck draft from failing the exact same way forever.
      if (e.statusCode == 409) {
        await _dbHelper.markTaskChangeRequestSynced(
          localId: localId,
          status: 'approved',
        );
        return;
      }
      rethrow;
    }

    await _dbHelper.markTaskChangeRequestSynced(
      localId: localId,
      // Left null (never a made-up placeholder like 0) when the backend
      // didn't send one — `request_id` is UNIQUE, and 0 isn't a real id,
      // so reusing it across rows blew up the very next submit with a
      // UNIQUE-constraint failure (SQLite allows any number of NULLs in
      // a UNIQUE column, which is what this is for).
      requestId: result.requestId,
      status: _localStatusFor(result.status),
      requestedDate: result.requestedDate,
    );
  }

  /// Maps the backend's own status string to this table's three-value
  /// status column. Confirmed backend values: 'pending_approval' (needs
  /// HR/Admin review) and 'applied' (the backend decided no approval was
  /// actually needed and applied the change immediately, returning a
  /// `worker_task_id` instead of a `request_id` — still never written to
  /// local `worker_tasks` here; that only happens via the existing
  /// server-sync fetch, same as every other approved change). An
  /// unrecognized value defaults to 'pending' rather than silently
  /// treating it as resolved.
  String _localStatusFor(String backendStatus) {
    switch (backendStatus) {
      case 'applied':
      case 'approved':
        return 'approved';
      case 'rejected':
        return 'rejected';
      default:
        return 'pending';
    }
  }
}
