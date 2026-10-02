import 'worker_model.dart';

/// The personal details collected on step 1 of enrollment, held until the
/// face capture on step 2 completes and the whole record is persisted.
class EnrollmentDraft {
  final String fullName;
  final DateTime? dateOfBirth;
  final Gender gender;
  final String nationalId;
  final String phoneNumber;
  final String address;
  final PayType enrollmentType;
  final int departmentId;
  final String departmentName;
  final String nationalIdImagePath;

  /// The task picked on the Task dropdown, or null if none was picked.
  final int? taskId;

  /// The optional note entered alongside the picked task, or null if left
  /// blank — stored in `worker_tasks.note` once the task is assigned (see
  /// CreateEmployeeViewModel.save). Meaningless when [taskId] is null.
  final String? taskNote;

  /// Which shift the worker works, when [enrollmentType] is
  /// [PayType.shiftBased] — null for every other enrollment type. Stored in
  /// `workers.shift_based_type`.
  final String? shiftBasedType;

  const EnrollmentDraft({
    required this.fullName,
    required this.dateOfBirth,
    required this.gender,
    required this.nationalId,
    required this.phoneNumber,
    required this.address,
    required this.enrollmentType,
    required this.departmentId,
    required this.departmentName,
    required this.nationalIdImagePath,
    this.taskId,
    this.taskNote,
    this.shiftBasedType,
  });
}
