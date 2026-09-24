import '../../core/network/api_client.dart';
import '../../core/network/api_routes.dart';
import '../models/worker_attendance_model.dart';

/// Remote datasource for pushing one day's check-in/check-out record to the
/// backend.
class WorkerAttendanceSyncApi {
  final ApiClient _client;

  WorkerAttendanceSyncApi({ApiClient? client}) : _client = client ?? ApiClient();

  /// POST attendance/check-in. Confirmed request body: `{"worker_id": ...,
  /// "attendance_date": ..., "check_in_time": ..., "check_out_time": ...,
  /// "check_in_face_verified": 0|1, "check_out_face_verified": 0|1}`.
  /// [realWorkerId] must be the backend's real worker_id, not the local
  /// one — the caller resolves that first (see
  /// WorkerAttendanceRepository.syncToday).
  ///
  /// Confirmed response on success: `{"message": ..., "attendance_id":
  /// ..., "status": true}` — returns that `attendance_id`, or null if the
  /// response doesn't have the expected shape.
  Future<int?> syncAttendance(
    WorkerAttendanceRecord record, {
    required int realWorkerId,
  }) async {
    final response = await _client.post(
      ApiRoutes.checkIn,
      data: {
        'worker_id': realWorkerId,
        'attendance_date': record.attendanceDate,
        'check_in_time': _formatTimestamp(record.checkInTime),
        'check_out_time': _formatTimestamp(record.checkOutTime),
        'check_in_face_verified': record.checkInFaceVerified ? 1 : 0,
        'check_out_face_verified': record.checkOutFaceVerified ? 1 : 0,
      },
    );
    return _extractId(response, 'attendance_id');
  }

  int? _extractId(dynamic response, String key) {
    if (response is! Map) return null;
    final value = response[key];
    return value is int ? value : int.tryParse(value.toString());
  }

  /// The backend wants a real ISO-8601 UTC timestamp (same fix as
  /// `completed_date` on the worker-task-completion sync — see
  /// TaskCompletionSyncApi). `check_in_time`/`check_out_time` are stored
  /// locally as `DateTime.now().toIso8601String()` (no offset, so it parses
  /// as local time); converting to UTC before formatting is what makes it
  /// unambiguous for the backend. Null (no check-out yet) stays null.
  String? _formatTimestamp(String? isoString) {
    if (isoString == null) return null;
    return DateTime.parse(isoString).toUtc().toIso8601String();
  }
}
