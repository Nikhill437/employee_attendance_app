import '../../../core/base/base_view_model.dart';
import '../../../data/models/enrollment_draft_model.dart';
import '../../../data/models/worker_model.dart';

/// Holds the selections on the enrollment form that aren't text fields.
///
/// The text values stay in the view's controllers; this view model owns the
/// choices and assembles the finished [EnrollmentDraft].
class EnrollmentFormViewModel extends BaseViewModel {
  Gender _gender = Gender.male;
  PayType _enrollmentType = PayType.daily;
  DateTime? _dateOfBirth;

  Gender get gender => _gender;
  PayType get enrollmentType => _enrollmentType;
  DateTime? get dateOfBirth => _dateOfBirth;

  void selectGender(Gender gender) {
    _gender = gender;
    safeNotify();
  }

  void selectEnrollmentType(PayType type) {
    _enrollmentType = type;
    safeNotify();
  }

  void selectDateOfBirth(DateTime date) {
    _dateOfBirth = date;
    safeNotify();
  }

  EnrollmentDraft buildDraft({
    required String fullName,
    required String nationalId,
    required String phoneNumber,
    required String address,
    required String department,
  }) {
    return EnrollmentDraft(
      fullName: fullName,
      dateOfBirth: _dateOfBirth,
      gender: _gender,
      nationalId: nationalId,
      phoneNumber: phoneNumber,
      address: address,
      enrollmentType: _enrollmentType,
      department: department,
    );
  }
}
