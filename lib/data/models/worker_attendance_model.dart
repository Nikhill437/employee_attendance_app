/// What a face-scan event turned out to be against a worker's
/// `worker_attendance` row for today (see DatabaseHelper.recordWorkerScan).
enum WorkerScanOutcome {
  /// First scan of the day — just checked in.
  checkedIn,

  /// Second scan of the day — just checked out.
  checkedOut,

  /// A third-or-later scan on a day already checked in and out; the row is
  /// left as-is.
  alreadyCheckedOut,
}

/// One day's check-in/check-out record for a worker — a `worker_attendance`
/// row.
class WorkerAttendanceRecord {
  final int attendanceId;
  final int workerId;
  final String attendanceDate;
  final String? checkInTime;
  final String? checkOutTime;
  final bool checkInFaceVerified;
  final bool checkOutFaceVerified;
  final String status;

  /// The scan event this record was just produced by, when it was built
  /// from one (see DatabaseHelper.recordWorkerScan) — null for a plain
  /// snapshot read of an existing row (see DatabaseHelper.getTodayAttendance),
  /// where there's no "event" to report.
  final WorkerScanOutcome? outcome;

  /// Whether `POST attendance/check-in` has succeeded for this row yet —
  /// local-only bookkeeping, mirroring `workers.is_synced`.
  final bool isSynced;

  /// The backend's own `attendance_id` for this row, once
  /// `POST attendance/check-in`'s response has returned one (see
  /// DatabaseHelper.markWorkerAttendanceSynced) — null until then. Distinct
  /// from [attendanceId] (always the local `offline_worker_id`); this is
  /// what actually confirms the day made it to the server.
  final int? realAttendanceId;

  const WorkerAttendanceRecord({
    required this.attendanceId,
    required this.workerId,
    required this.attendanceDate,
    required this.checkInTime,
    required this.checkOutTime,
    this.checkInFaceVerified = false,
    this.checkOutFaceVerified = false,
    required this.status,
    this.outcome,
    this.isSynced = false,
    this.realAttendanceId,
  });

  bool get hasCheckedIn => checkInTime != null;
  bool get hasCheckedOut => checkOutTime != null;

  factory WorkerAttendanceRecord.fromMap(
    Map<String, dynamic> map, {
    WorkerScanOutcome? outcome,
  }) {
    return WorkerAttendanceRecord(
      // offline_worker_id, not attendance_id — see the class doc comment
      // above DatabaseHelper._createWorkerTables. This is the local id
      // every local join/screen-param already keys off; attendance_id
      // (the backend's real id once synced) is bookkeeping only, not
      // otherwise read by the app — see WorkerAttendanceRepository.syncToday.
      attendanceId: map['offline_worker_id'] as int,
      workerId: map['worker_id'] as int,
      attendanceDate: map['attendance_date'] as String,
      checkInTime: map['check_in_time'] as String?,
      checkOutTime: map['check_out_time'] as String?,
      checkInFaceVerified: (map['check_in_face_verified'] as int? ?? 0) == 1,
      checkOutFaceVerified: (map['check_out_face_verified'] as int? ?? 0) == 1,
      status: map['status'] as String,
      outcome: outcome,
      isSynced: (map['is_synced'] as int? ?? 0) == 1,
      realAttendanceId: map['attendance_id'] as int?,
    );
  }
}
