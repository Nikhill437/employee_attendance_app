/// The backend's response to `POST attendance/request-task-change`. Confirmed
/// shape: `{"success": true, "approval_required": true, "status":
/// "pending_approval", "message": ..., "data": {"request_id": ...,
/// "worker_id": ..., "current_task": {...}, "proposed_task": {...},
/// "reason": ..., "requested_by": ..., "requested_date": ...}}`.
class TaskChangeRequestResult {
  final bool success;
  final String status;
  final String message;

  /// The backend's own id for the newly created request
  /// (`data.request_id`) — null if the response didn't include one.
  final int? requestId;

  /// `data.requested_date`, in whatever format the backend sends — stored
  /// as-is locally (see DatabaseHelper.markTaskChangeRequestSynced)
  /// rather than reparsed, the same way other confirmed-but-unvalidated
  /// backend date strings are handled elsewhere in this app.
  final String? requestedDate;

  const TaskChangeRequestResult({
    required this.success,
    required this.status,
    required this.message,
    this.requestId,
    this.requestedDate,
  });

  factory TaskChangeRequestResult.fromJson(Map<String, dynamic> json) {
    final data = json['data'];
    return TaskChangeRequestResult(
      success: json['success'] == true,
      status: json['status'] as String? ?? 'pending_approval',
      message: json['message'] as String? ?? '',
      requestId: data is Map ? _asIntOrNull(data['request_id']) : null,
      requestedDate: data is Map ? data['requested_date'] as String? : null,
    );
  }
}

int? _asIntOrNull(dynamic value) {
  if (value is int) return value;
  if (value is String) return int.tryParse(value);
  return null;
}
