/// A local `task_pricing_change_requests` row — raised when a supervisor
/// reassigns a worker to a task outside their current pricing group (see
/// AssignTaskViewModel.save / TaskChangeRequestRepository). Mirrors the
/// backend's own table of the same name; see DatabaseHelper
/// ._createWorkerTables's doc comment for the offline-first id scheme this
/// follows.
class TaskPricingChangeRequest {
  /// This row's own local id (`task_pricing_change_requests.
  /// offline_worker_id`) — not a worker id at all, despite the column name
  /// (see the class doc comment above); what [TaskChangeRequestRepository.
  /// submit] takes to resubmit this exact draft.
  final int localId;

  /// The backend's own id for this request, once submitted — null until
  /// [isSynced] is true.
  final int? requestId;

  /// The proposed task's id (`tasks.task_id`).
  final int taskId;

  /// The proposed task's name, joined in for display — null unless read
  /// back via a query that joins `tasks` (see DatabaseHelper.
  /// getPendingTaskChangeRequestsByWorker).
  final String? taskName;

  /// The worker's own local id (`workers.offline_worker_id`) — see the
  /// class doc comment above for why this column holds the local id here,
  /// not the backend's.
  final int proposedWorkerId;

  final int? currentPricingGroupId;
  final int proposedPricingGroupId;
  final num? oldRate;
  final num newRate;
  final String? reason;

  /// 'pending' / 'approved' / 'rejected' — the backend's own verdict once
  /// known; always 'pending' while [isSynced] is false (nothing to have a
  /// verdict on yet).
  final String status;

  /// Whether this draft has been submitted to the backend
  /// (`POST attendance/request-task-change`) yet. False means it's still
  /// local-only and the supervisor needs to tap Sync.
  final bool isSynced;

  final int requestedBy;
  final String requestedDate;

  const TaskPricingChangeRequest({
    required this.localId,
    required this.taskId,
    required this.proposedWorkerId,
    required this.proposedPricingGroupId,
    required this.newRate,
    required this.status,
    required this.isSynced,
    required this.requestedBy,
    required this.requestedDate,
    this.requestId,
    this.taskName,
    this.currentPricingGroupId,
    this.oldRate,
    this.reason,
  });

  factory TaskPricingChangeRequest.fromMap(Map<String, dynamic> map) {
    return TaskPricingChangeRequest(
      localId: map['offline_worker_id'] as int,
      requestId: map['request_id'] as int?,
      taskId: map['task_id'] as int,
      taskName: map['task_name'] as String?,
      proposedWorkerId: map['proposed_worker_id'] as int,
      currentPricingGroupId: map['current_pricing_group_id'] as int?,
      proposedPricingGroupId: map['proposed_pricing_group_id'] as int,
      oldRate: map['old_rate'] as num?,
      newRate: map['new_rate'] as num,
      reason: map['reason'] as String?,
      status: map['status'] as String? ?? 'pending',
      isSynced: (map['is_synced'] as int? ?? 0) == 1,
      requestedBy: map['requested_by'] as int,
      requestedDate: map['requested_date'] as String,
    );
  }
}
