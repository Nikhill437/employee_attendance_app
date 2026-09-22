import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../../core/base/base_view_model.dart';
import '../../../data/models/department_model.dart';
import '../../../data/models/enrollment_draft_model.dart';
import '../../../data/models/worker_model.dart';
import '../../../data/repositories/lookup_repository.dart';

/// Holds the selections on the enrollment form that aren't text fields.
///
/// The text values stay in the view's controllers; this view model owns the
/// choices (including the department, picked from the locally cached list
/// synced at login — see LookupRepository) and assembles the finished
/// [EnrollmentDraft].
class EnrollmentFormViewModel extends BaseViewModel {
  final LookupRepository _lookupRepository;

  EnrollmentFormViewModel({LookupRepository? lookupRepository})
    : _lookupRepository = lookupRepository ?? LookupRepository();

  Gender _gender = Gender.male;
  PayType _enrollmentType = PayType.daily;
  DateTime? _dateOfBirth;
  Department? _department;
  List<Department> _departments = const [];
  bool _isLoadingDepartments = true;
  File? _nationalIdImage;

  Gender get gender => _gender;
  PayType get enrollmentType => _enrollmentType;
  DateTime? get dateOfBirth => _dateOfBirth;
  Department? get department => _department;
  List<Department> get departments => _departments;
  bool get isLoadingDepartments => _isLoadingDepartments;
  File? get nationalIdImage => _nationalIdImage;

  /// Loads the departments cached from the last successful login sync —
  /// call once from the screen's initState.
  Future<void> loadDepartments() async {
    _isLoadingDepartments = true;
    safeNotify();
    _departments = await _lookupRepository.getDepartments();
    _isLoadingDepartments = false;
    safeNotify();
  }

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

  void selectDepartment(Department? department) {
    _department = department;
    safeNotify();
  }

  /// Copies the just-captured photo into permanent app storage (the path
  /// image_picker/the camera return can be a cache/temp location the OS is
  /// free to clear) and keeps it for the form's preview and the final save.
  Future<void> captureNationalIdImage(File pickedFile) async {
    final docsDir = await getApplicationDocumentsDirectory();
    final idDir = Directory('${docsDir.path}/national_id_attachments');
    if (!await idDir.exists()) {
      await idDir.create(recursive: true);
    }
    final extension = pickedFile.path.contains('.')
        ? pickedFile.path.split('.').last
        : 'jpg';
    final destPath =
        '${idDir.path}/${DateTime.now().millisecondsSinceEpoch}.$extension';
    _nationalIdImage = await pickedFile.copy(destPath);
    safeNotify();
  }

  EnrollmentDraft buildDraft({
    required String fullName,
    required String nationalId,
    required String phoneNumber,
    required String address,
  }) {
    final department = _department;
    final nationalIdImage = _nationalIdImage;
    if (department == null) {
      throw StateError('buildDraft called before a department was selected');
    }
    if (nationalIdImage == null) {
      throw StateError(
        'buildDraft called before the National ID was captured',
      );
    }
    return EnrollmentDraft(
      fullName: fullName,
      dateOfBirth: _dateOfBirth,
      gender: _gender,
      nationalId: nationalId,
      phoneNumber: phoneNumber,
      address: address,
      enrollmentType: _enrollmentType,
      departmentId: department.id,
      departmentName: department.name,
      nationalIdImagePath: nationalIdImage.path,
    );
  }
}
