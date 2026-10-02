import '../datasources/database_helper.dart';
import '../datasources/worker_attendance_sync_api.dart';
import '../models/worker_attendance_model.dart';

/// Check-in/check-out tracking (`worker_attendance`) — separate from, and
/// additive to, the existing `attendance_logs`-based mark-attendance flow.
class WorkerAttendanceRepository {
  final DatabaseHelper _dbHelper;
  final WorkerAttendanceSyncApi _syncApi;

  WorkerAttendanceRepository({
    DatabaseHelper? dbHelper,
    WorkerAttendanceSyncApi? syncApi,
  }) : _dbHelper = dbHelper ?? DatabaseHelper(),
       _syncApi = syncApi ?? WorkerAttendanceSyncApi();

  /// Records a face-scan event for [workerId] — checks them in on the
  /// day's first scan, checks them out on the next.
  Future<WorkerAttendanceRecord> recordScan(int workerId) =>
      _dbHelper.recordWorkerScan(workerId);

  /// Today's check-in/check-out row for [workerId], or null if they haven't
  /// been scanned yet today.
  Future<WorkerAttendanceRecord?> getTodayAttendance(int workerId) =>
      _dbHelper.getTodayAttendance(workerId);

  /// Every worker's today's row, keyed by worker_id — one query for the
  /// whole worker list rather than one per card.
  Future<Map<int, WorkerAttendanceRecord>> getTodayAttendanceByWorker() =>
      _dbHelper.getTodayAttendanceByWorker();

  /// [workerId]'s full check-in/check-out history, newest day first — the
  /// Reports screen.
  Future<List<WorkerAttendanceRecord>> getAttendanceHistory(int workerId) =>
      _dbHelper.getAttendanceHistory(workerId);

  /// Whether [workerId] has any `worker_attendance` day not yet pushed to
  /// the backend — not just today's (see
  /// AttendanceSubmissionRepository.submitAllUnsyncedAttendance).
  Future<bool> hasUnsyncedAttendance(int workerId) async {
    final rows = await _dbHelper.getUnsyncedAttendance(workerId);
    return rows.isNotEmpty;
  }

  /// Pushes [workerId]'s today's attendance record to the backend
  /// (`POST attendance/check-in`) and marks it synced locally. Throws if
  /// there's nothing recorded yet today, if the worker themselves hasn't
  /// been synced yet (the backend needs their real worker_id — see
  /// DatabaseHelper.getRemoteWorkerId), or lets the network call's failure
  /// propagate.
  Future<void> syncToday(int workerId) async {
    final record = await _dbHelper.getTodayAttendance(workerId);
    if (record == null) {
      throw StateError('No attendance recorded today for this worker');
    }
    final realWorkerId = await _dbHelper.getRemoteWorkerId(workerId);
    if (realWorkerId == null) {
      throw StateError('Sync this worker before syncing their attendance');
    }
    final realAttendanceId = await _syncApi.syncAttendance(
      record,
      realWorkerId: realWorkerId,
    );
    await _dbHelper.markWorkerAttendanceSynced(
      record.attendanceId,
      realAttendanceId: realAttendanceId,
    );
  }
}
