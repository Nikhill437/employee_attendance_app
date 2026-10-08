import '../../core/utils/app_time.dart';
import '../datasources/database_helper.dart';
import '../datasources/worker_attendance_sync_api.dart';
import '../models/worker_attendance_model.dart';
import 'server_sync_time_store.dart';

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

  /// The dashboard's "Employee Attendance" button. The first call uses
  /// `GET attendance/departmentwise_attendance`. Later calls send the stored
  /// call time to `attendance/departmentwise_attendance_data`. The rows are
  /// stored via DatabaseHelper.upsertRemoteWorkerAttendance, which updates
  /// matching rows and never duplicates them. The call time is saved only
  /// after that succeeds. Errors propagate. Returns how many rows were stored.
  Future<int> importDepartmentAttendance({
    void Function(int fetchedSoFar, int currentPage, int totalPages)?
    onProgress,
  }) async {
    final callTime = DateTime.now().toUtc();
    final storedTime = await lastDepartmentAttendanceCallTime.read();
    final records = storedTime == null
        ? await _syncApi.fetchDepartmentAttendance(onProgress: onProgress)
        : await _syncApi.fetchDepartmentAttendanceData(
            DateTime.parse(storedTime),
            onProgress: onProgress,
          );
    final stored = await _dbHelper.upsertRemoteWorkerAttendance(records);
    await lastDepartmentAttendanceCallTime.save(callTime.toIso8601String());
    return stored;
  }

  /// Whether any local record is still waiting to sync — see
  /// DatabaseHelper.hasUnsyncedLocalData. Read-only.
  Future<bool> hasUnsyncedData() => _dbHelper.hasUnsyncedLocalData();

  /// How many `worker_attendance` rows are cached locally, and how many of
  /// those haven't been pushed to the server yet — the Employee Attendance
  /// card's stat boxes.
  Future<int> getAttendanceCount() => _dbHelper.getWorkerAttendanceCount();
  Future<int> getUnsyncedAttendanceCount() =>
      _dbHelper.getUnsyncedWorkerAttendanceCount();

  /// The last successful [importDepartmentAttendance] call's start time, in
  /// the supervisor's own timezone (see AppTime) — null if none has run
  /// yet.
  Future<DateTime?> lastSyncedAt() async {
    final stored = await lastDepartmentAttendanceCallTime.read();
    final parsed = stored == null ? null : DateTime.tryParse(stored);
    return parsed == null ? null : AppTime.toUserTime(parsed);
  }

  /// The Employee Attendance card's Clear action: wipes every local
  /// `worker_attendance` row — including any check-in/check-out scanned on
  /// this device and not yet synced — and resets the fetch checkpoint, so
  /// the next fetch pulls the full list again.
  Future<void> clearLocal() async {
    await _dbHelper.clearWorkerAttendance();
    await lastDepartmentAttendanceCallTime.clear();
  }

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
