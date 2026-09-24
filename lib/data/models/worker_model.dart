/// A worker's gender, as recorded on the enrollment form.
enum Gender {
  male('Male'),
  female('Female'),
  other('Other');

  const Gender(this.label);

  final String label;
}

/// How a worker is paid, shown as the chip under their name.
enum PayType {
  daily('Daily'),
  monthly('Monthly'),
  taskBased('Task Based');

  const PayType(this.label);

  final String label;
}

/// Whether the worker has marked attendance today.
enum AttendanceStatus {
  present('Present'),
  absent('Absent');

  const AttendanceStatus(this.label);

  final String label;
}

/// Progress on the worker's assignment for the day.
enum WorkStatus {
  completed('Completed'),
  inProgress('In Progress'),
  notStarted('Not Started');

  const WorkStatus(this.label);

  final String label;
}

/// Whether a supervisor has signed the day's work off.
enum VerificationStatus {
  verified('Approved'),
  pending('Pending'),
  rejected('Rejected'),
  notVerified('Not Verified');

  const VerificationStatus(this.label);

  final String label;
}

/// One row of the worker list.
///
/// [payType] and [department] come from the employee's stored enrollment
/// record. [verification] reflects the backend's real approval status
/// (`Employee.status`) once this worker has been synced or imported —
/// 'Not Verified' until then, since there's nothing from the server to
/// show yet. [role] and [workStatus] describe a job-tracking workflow the
/// database does not model yet, so they fall back to neutral defaults
/// rather than being invented per worker.
class Worker {
  final String name;
  final String employeeId;
  final String role;
  final PayType payType;
  final AttendanceStatus attendance;

  /// The department entered on the enrollment form, or null for records
  /// enrolled before that field existed.
  final String? department;

  /// Time of the first attendance log today, or null when absent.
  final DateTime? checkInAt;

  final WorkStatus workStatus;
  final VerificationStatus verification;

  /// Whether `POST attendance/sync-worker` has succeeded for this worker —
  /// drives the "Synced" pill on the worker card.
  final bool isSynced;

  /// The local `workers.offline_worker_id` — the FK task assignment/
  /// completion rows key off, distinct from [employeeId] (their National
  /// ID). Null only for a `Worker` built without a persisted record behind
  /// it.
  final int? workerId;

  /// FK into `departments` — which tasks this worker can be assigned (see
  /// AssignTaskScreen), distinct from [department]'s display name.
  final int? departmentId;

  /// The backend's raw approval status ('approved' / 'pending' /
  /// 'rejected') — what task-action gating actually checks, as opposed to
  /// [verification] which is the derived display label.
  final String status;

  /// Today's `worker_attendance` row, if the Mark Attendance face-scan flow
  /// has been run for this worker today — drives that button's Check
  /// In/Check Out label and the attendance sync button.
  final bool hasCheckedInToday;
  final bool hasCheckedOutToday;
  final bool isAttendanceSynced;

  /// Whether today's `worker_attendance` row has the backend's real
  /// `attendance_id` yet (from `POST attendance/check-in`'s response) —
  /// while this is false, the Mark Attendance button stays enabled even
  /// after check-in/check-out are both done, so it can be retried.
  final bool hasRealAttendanceIdToday;

  const Worker({
    required this.name,
    required this.employeeId,
    this.role = 'Worker',
    this.payType = PayType.daily,
    this.attendance = AttendanceStatus.absent,
    this.department,
    this.checkInAt,
    this.workStatus = WorkStatus.notStarted,
    this.verification = VerificationStatus.notVerified,
    this.isSynced = false,
    this.workerId,
    this.departmentId,
    this.status = 'pending',
    this.hasCheckedInToday = false,
    this.hasCheckedOutToday = false,
    this.isAttendanceSynced = false,
    this.hasRealAttendanceIdToday = false,
  });

  bool get isPresent => attendance == AttendanceStatus.present;

  /// Up to two letters for the avatar, taken from the worker's name.
  String get initials {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }
}
