import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../../core/base/base_view_model.dart';
import '../../../data/models/department_model.dart';
import '../../../data/models/enrollment_draft_model.dart';
import '../../../data/models/worker_model.dart';
import '../../../data/repositories/employee_repository.dart';
import '../../../data/repositories/lookup_repository.dart';
import '../../../data/repositories/task_repository.dart';

/// Holds the selections on the enrollment form that aren't text fields.
///
/// The text values stay in the view's controllers; this view model owns the
/// choices (including the department, picked from the locally cached list
/// synced at login — see LookupRepository) and assembles the finished
/// [EnrollmentDraft]. Also drives edit mode (see EnrollmentFormScreen):
/// [initialDepartmentId] pre-selects a department once loaded, and
/// [saveDepartmentOnly] updates just that on an existing worker.
class EnrollmentFormViewModel extends BaseViewModel {
  final LookupRepository _lookupRepository;
  final EmployeeRepository _employeeRepository;
  final TaskRepository _taskRepository;
  final int? initialDepartmentId;

  EnrollmentFormViewModel({
    LookupRepository? lookupRepository,
    EmployeeRepository? employeeRepository,
    TaskRepository? taskRepository,
    this.initialDepartmentId,
  }) : _lookupRepository = lookupRepository ?? LookupRepository(),
       _employeeRepository = employeeRepository ?? EmployeeRepository(),
       _taskRepository = taskRepository ?? TaskRepository();

  Gender _gender = Gender.male;
  PayType _enrollmentType = PayType.daily;
  DateTime? _dateOfBirth;
  Department? _department;
  List<Department> _departments = const [];
  bool _isLoadingDepartments = true;
  bool _isSavingDepartment = false;
  File? _nationalIdImage;
  Task? _task;
  List<Task> _tasks = const [];
  bool _isLoadingTasks = false;

  Gender get gender => _gender;
  PayType get enrollmentType => _enrollmentType;
  DateTime? get dateOfBirth => _dateOfBirth;
  Department? get department => _department;
  List<Department> get departments => _departments;
  bool get isLoadingDepartments => _isLoadingDepartments;
  bool get isSavingDepartment => _isSavingDepartment;
  File? get nationalIdImage => _nationalIdImage;
  Task? get task => _task;
  List<Task> get tasks => _tasks;
  bool get isLoadingTasks => _isLoadingTasks;

  /// Loads the departments cached from the last successful login sync —
  /// call once from the screen's initState. Pre-selects
  /// [initialDepartmentId] once loaded, for edit mode.
  Future<void> loadDepartments() async {
    _isLoadingDepartments = true;
    safeNotify();
    _departments = await _lookupRepository.getDepartments();

    final initialId = initialDepartmentId;
    if (initialId != null) {
      for (final department in _departments) {
        if (department.id == initialId) {
          _department = department;
          break;
        }
      }
    }

    _isLoadingDepartments = false;
    safeNotify();

    final selectedDepartment = _department;
    if (selectedDepartment != null) {
      await loadTasksForDepartment(selectedDepartment.id);
    }
  }

  /// Loads the tasks available for [departmentId] — called whenever the
  /// department changes, since a worker can only be given a task from
  /// their own department. Resets the current task selection.
  Future<void> loadTasksForDepartment(int departmentId) async {
    _isLoadingTasks = true;
    _task = null;
    safeNotify();
    _tasks = await _taskRepository.getTasksByDepartment(departmentId);
    _isLoadingTasks = false;
    safeNotify();
  }

  void selectTask(Task? task) {
    _task = task;
    safeNotify();
  }

  /// Edit mode only: sets the display-only Gender/Enrollment Type pills to
  /// the worker's actual values — they're disabled in edit mode, but
  /// should still show the truth rather than these fields' plain defaults.
  void presetForEditing({required Gender gender, required PayType enrollmentType}) {
    _gender = gender;
    _enrollmentType = enrollmentType;
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
    if (department != null) {
      loadTasksForDepartment(department.id);
    }
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
      taskId: _task?.id,
      nationalIdImagePath: nationalIdImage.path,
    );
  }

  /// Edit mode only: updates just [workerId]'s department — the only field
  /// editing a worker is allowed to change. Returns an error message on
  /// failure, or null on success.
  Future<String?> saveDepartmentOnly(int workerId) async {
    final department = _department;
    if (department == null) return 'Select the department';
    if (_isSavingDepartment) return null;

    _isSavingDepartment = true;
    safeNotify();
    try {
      await _employeeRepository.updateDepartment(workerId, department.id);
      return null;
    } catch (e) {
      return e.toString();
    } finally {
      _isSavingDepartment = false;
      safeNotify();
    }
  }
}
