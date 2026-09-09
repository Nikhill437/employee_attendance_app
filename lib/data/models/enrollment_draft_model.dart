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
  final String department;

  const EnrollmentDraft({
    required this.fullName,
    required this.dateOfBirth,
    required this.gender,
    required this.nationalId,
    required this.phoneNumber,
    required this.address,
    required this.enrollmentType,
    required this.department,
  });
}
