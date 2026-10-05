/// One day's check-in/check-out row from `GET attendance/departmentwise_attendance`
/// (see WorkerAttendanceSyncApi.fetchDepartmentAttendance). [workerId] is the
/// backend's worker id, not the local one.
class RemoteWorkerAttendance {
  final int attendanceId;
  final int workerId;

  /// `yyyy-MM-dd`, from the response's UTC date (`2026-10-05T00:00:00.000Z`).
  final String attendanceDate;

  /// UTC ISO timestamps, as the backend sends them. Null when not recorded.
  final String? checkInTime;
  final String? checkOutTime;

  final int? checkInBy;
  final int? checkOutBy;
  final int checkInFaceVerified;
  final int checkOutFaceVerified;

  const RemoteWorkerAttendance({
    required this.attendanceId,
    required this.workerId,
    required this.attendanceDate,
    required this.checkInTime,
    required this.checkOutTime,
    required this.checkInBy,
    required this.checkOutBy,
    required this.checkInFaceVerified,
    required this.checkOutFaceVerified,
  });

  factory RemoteWorkerAttendance.fromJson(Map<String, dynamic> json) {
    final date = json['attendance_date'] as String;
    return RemoteWorkerAttendance(
      attendanceId: (json['attendance_id'] as num).toInt(),
      workerId: (json['worker_id'] as num).toInt(),
      attendanceDate: date.substring(0, 10),
      checkInTime: json['check_in_time'] as String?,
      checkOutTime: json['check_out_time'] as String?,
      checkInBy: (json['check_in_by'] as num?)?.toInt(),
      checkOutBy: (json['check_out_by'] as num?)?.toInt(),
      checkInFaceVerified:
          (json['check_in_face_verified'] as num?)?.toInt() ?? 0,
      checkOutFaceVerified:
          (json['check_out_face_verified'] as num?)?.toInt() ?? 0,
    );
  }
}
