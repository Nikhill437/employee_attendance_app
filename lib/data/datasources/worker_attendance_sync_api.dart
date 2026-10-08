import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
import '../../core/network/api_routes.dart';
import '../../core/utils/app_time.dart';
import '../models/remote_worker_attendance_model.dart';
import '../models/worker_attendance_model.dart';

/// Remote datasource for pushing one day's check-in/check-out record to the
/// backend.
class WorkerAttendanceSyncApi {
  final ApiClient _client;

  WorkerAttendanceSyncApi({ApiClient? client})
    : _client = client ?? ApiClient();

  /// GET attendance/departmentwise_attendance — the check-ins and check-outs
  /// the server holds for the supervisor's department. Used for the first
  /// Employee Attendance fetch. Response:
  /// `{"success", "message", "department_id", "total", "data": [...]}`.
  /// Walks `page`/`totalPages` until exhausted, same pattern as
  /// `WorkerListApi.fetchAll` — a response with no `totalPages` is treated
  /// as a single page. [onProgress], when given, is called after each
  /// page with how many rows have been fetched so far and the
  /// current/total page numbers — the dashboard's sync bottom sheet's
  /// source of real download progress for the Employee Attendance card.
  /// Errors propagate.
  Future<List<RemoteWorkerAttendance>> fetchDepartmentAttendance({
    int limit = 100,
    void Function(int fetchedSoFar, int currentPage, int totalPages)?
    onProgress,
  }) async {
    final results = <RemoteWorkerAttendance>[];
    var page = 1;

    while (true) {
      final data = await _client.get(
        '${ApiRoutes.departmentwiseAttendance}?page=$page&limit=$limit',
      );
      results.addAll(_parseDepartmentAttendance(data));

      final totalPages = data is Map ? (data['totalPages'] as int? ?? 1) : 1;
      onProgress?.call(results.length, page, totalPages);
      if (page >= totalPages) break;
      page++;
    }

    return results;
  }

  /// POST attendance/departmentwise_attendance_data with `{"date": ...}` (UTC
  /// ISO), the time of the last successful Employee Attendance call. Returns
  /// the same response structure (and walks pages/reports [onProgress] the
  /// same way) as [fetchDepartmentAttendance]. Errors propagate, so a
  /// failed call never moves the stored time.
  Future<List<RemoteWorkerAttendance>> fetchDepartmentAttendanceData(
    DateTime date, {
    int limit = 100,
    void Function(int fetchedSoFar, int currentPage, int totalPages)?
    onProgress,
  }) async {
    final results = <RemoteWorkerAttendance>[];
    var page = 1;

    while (true) {
      final data = await _client.post(
        '${ApiRoutes.departmentwiseAttendanceData}?page=$page&limit=$limit',
        data: {'date': date.toUtc().toIso8601String()},
      );
      results.addAll(_parseDepartmentAttendance(data));

      final totalPages = data is Map ? (data['totalPages'] as int? ?? 1) : 1;
      onProgress?.call(results.length, page, totalPages);
      if (page >= totalPages) break;
      page++;
    }

    return results;
  }

  List<RemoteWorkerAttendance> _parseDepartmentAttendance(dynamic data) {
    if (data is! Map || data['data'] is! List) {
      throw ApiException('Unexpected attendance response from the server.');
    }
    return (data['data'] as List)
        .map(
          (row) => RemoteWorkerAttendance.fromJson(row as Map<String, dynamic>),
        )
        .toList();
  }

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

  /// The backend wants a real ISO-8601 UTC timestamp.
  /// `check_in_time`/`check_out_time` are stored
  /// locally as `AppTime.nowInUserZone().toIso8601String()` — a naive
  /// string whose calendar fields are the supervisor's own timezone (from
  /// their login response), not the device's. Parsing it and calling
  /// plain `.toUtc()` would convert using the *device's* timezone instead
  /// — wrong whenever that differs from the supervisor's — so this goes
  /// through `AppTime.userWallTimeToUtc`, the actual inverse of
  /// `nowInUserZone`, instead. Null (no check-out yet) stays null.
  String? _formatTimestamp(String? isoString) {
    if (isoString == null) return null;
    return AppTime.userWallTimeToUtc(
      DateTime.parse(isoString),
    ).toIso8601String();
  }
}
