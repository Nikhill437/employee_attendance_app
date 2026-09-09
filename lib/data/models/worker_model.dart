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
  verified('Verified'),
  pending('Pending'),
  notVerified('Not Verified');

  const VerificationStatus(this.label);

  final String label;
}

/// One row of the worker list.
///
/// [payType] and [department] come from the employee's stored enrollment
/// record. [role], [workStatus] and [verification] describe a job-tracking
/// workflow the database does not model yet, so they fall back to neutral
/// defaults rather than being invented per worker.
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
