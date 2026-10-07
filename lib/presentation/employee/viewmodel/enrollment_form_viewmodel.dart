import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../../core/base/base_view_model.dart';
import '../../../core/utils/app_time.dart';
import '../../../data/models/department_model.dart';
import '../../../data/models/employee_model.dart';
import '../../../data/models/enrollment_draft_model.dart';
import '../../../data/models/worker_model.dart';
import '../../../data/repositories/employee_repository.dart';
import '../../../data/repositories/worker_edit_queue.dart';
import '../../../data/repositories/lookup_repository.dart';
import '../../../data/repositories/supervisor_session_repository.dart';
import '../../../data/repositories/task_repository.dart';
import '../../../data/repositories/worker_attendance_repository.dart';

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
  final WorkerEditQueue _editQueue;
  final SupervisorSessionRepository _session;
  final WorkerAttendanceRepository _workerAttendance;
  final int? initialDepartmentId;

  /// Edit mode only: the task saved on the worker (`workers.task_id`), selected
  /// once the department's tasks have loaded.
  final int? initialTaskId;

  EnrollmentFormViewModel({
    LookupRepository? lookupRepository,
    EmployeeRepository? employeeRepository,
    TaskRepository? taskRepository,
    WorkerEditQueue? editQueue,
    SupervisorSessionRepository? session,
    WorkerAttendanceRepository? workerAttendance,
    this.initialDepartmentId,
    this.initialTaskId,
  }) : _lookupRepository = lookupRepository ?? LookupRepository(),
       _employeeRepository = employeeRepository ?? EmployeeRepository(),
       _taskRepository = taskRepository ?? TaskRepository(),
       _editQueue = editQueue ?? WorkerEditQueue(),
       _session = session ?? SupervisorSessionRepository(),
       _workerAttendance = workerAttendance ?? WorkerAttendanceRepository();

  Gender _gender = Gender.male;
  PayType _enrollmentType = PayType.daily;
  DateTime? _dateOfBirth;
  Department? _department;
  List<Department> _departments = const [];
  bool _isLoadingDepartments = true;
  bool _isSavingDepartment = false;
  File? _nationalIdImage;
  String? _remoteNationalIdImage;
  Task? _task;
  List<Task> _tasks = const [];
  bool _isLoadingTasks = false;
  String _taskNote = '';
  ShiftType? _shiftType;
  String? _workerStatus;

  /// The worker's status as last read from the `workers` table (see
  /// [loadWorkerStatus]); null until that read finishes.
  String? get workerStatus => _workerStatus;
  Gender get gender => _gender;
  PayType get enrollmentType => _enrollmentType;
  DateTime? get dateOfBirth => _dateOfBirth;
  Department? get department => _department;
  List<Department> get departments => _departments;
  bool get isLoadingDepartments => _isLoadingDepartments;
  bool get isSavingDepartment => _isSavingDepartment;
  File? get nationalIdImage => _nationalIdImage;

  /// The stored attachment when it's a server file (a worker fetched from
  /// the backend has a relative URL here), not a local copy. Null once a
  /// local image is captured or when there's no attachment.
  String? get remoteNationalIdImage => _remoteNationalIdImage;
  Task? get task => _task;
  List<Task> get tasks => _tasks;
  bool get isLoadingTasks => _isLoadingTasks;
  String get taskNote => _taskNote;
  ShiftType? get shiftType => _shiftType;

  /// Loads the departments cached from the last successful login sync —
  /// call once from the screen's initState. Pre-selects
  /// [initialDepartmentId] once loaded, for edit mode.
  Future<void> loadDepartments() async {
    _isLoadingDepartments = true;
    safeNotify();
    _departments = await _lookupRepository.getDepartments();

    // A new enrollment starts on the supervisor's own department. Edit mode
    // passes the worker's department, which takes precedence.
    final initialId =
        initialDepartmentId ?? await _session.getSupervisorDepartmentId();
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
      final savedTaskId = initialTaskId;
      if (savedTaskId != null) {
        for (final task in _tasks) {
          if (task.id == savedTaskId) {
            _task = task;
            break;
          }
        }
        safeNotify();
      }
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
    // A note only makes sense alongside the task it was written for.
    _taskNote = '';
    safeNotify();
  }

  void setTaskNote(String note) {
    _taskNote = note;
    safeNotify();
  }

  void selectShiftType(ShiftType? type) {
    _shiftType = type;
    safeNotify();
  }

  bool _departmentLocked = false;

  /// True while today's attendance has a check-in but no check-out. The
  /// department can't change until that day is checked out. Yesterday's
  /// attendance never counts here.
  bool get departmentLocked => _departmentLocked;

  /// Reads today's `worker_attendance` for [offlineWorkerId] and sets
  /// [departmentLocked]. Only today's date is checked.
  Future<void> loadDepartmentLock(int offlineWorkerId) async {
    final today = await _workerAttendance.getTodayAttendance(offlineWorkerId);
    _departmentLocked =
        today != null && today.hasCheckedIn && !today.hasCheckedOut;
    safeNotify();
  }

  /// Reads the worker's current status from the local `workers` table. Edit
  /// mode locks its fields once that status is approved or rejected.
  Future<void> loadWorkerStatus(int offlineWorkerId) async {
    _workerStatus = await _employeeRepository.getWorkerStatus(offlineWorkerId);
    safeNotify();
  }

  /// Edit mode only: sets the display-only Gender/Enrollment Type (and, for
  /// a Shift Based worker, their shift) fields to the worker's actual
  /// values — they're disabled in edit mode, but should still show the
  /// truth rather than these fields' plain defaults.
  void presetForEditing({
    required Gender gender,
    required PayType enrollmentType,
    String? shiftBasedType,
    DateTime? dateOfBirth,
    String? nationalIdImagePath,
  }) {
    _gender = gender;
    _enrollmentType = enrollmentType;
    _shiftType = _enumOrNull(ShiftType.values, shiftBasedType);
    _dateOfBirth = dateOfBirth;
    // A stored path is either a local copy (exists on this device) or a
    // server file URL, which can't be opened as a File.
    final localFile = nationalIdImagePath == null
        ? null
        : File(nationalIdImagePath);
    final isLocal = localFile != null && localFile.existsSync();
    _nationalIdImage = isLocal ? localFile : null;
    _remoteNationalIdImage = isLocal ? null : nationalIdImagePath;
    safeNotify();
  }

  static T? _enumOrNull<T extends Enum>(List<T> values, String? storedName) {
    if (storedName == null) return null;
    for (final value in values) {
      if (value.name == storedName) return value;
    }
    return null;
  }

  void selectGender(Gender gender) {
    _gender = gender;
    safeNotify();
  }

  void selectEnrollmentType(PayType type) {
    _enrollmentType = type;
    // Only meaningful for Shift Based — picking any other type drops
    // whatever shift was selected so a stale one can't be saved under it.
    if (type != PayType.shiftBased) _shiftType = null;
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
    _remoteNationalIdImage = null;
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
      throw StateError('buildDraft called before the National ID was captured');
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
      taskNote: _task == null || _taskNote.trim().isEmpty
          ? null
          : _taskNote.trim(),
      shiftBasedType: _enrollmentType == PayType.shiftBased
          ? _shiftType?.name
          : null,
      nationalIdImagePath: nationalIdImage.path,
    );
  }

  /// Edit mode's save. Writes each field the supervisor changed to the
  /// worker's existing `workers` row (never a new one) and queues the
  /// matching backend fields. updateWorkerEnrollment then marks the worker
  /// NOT SYNCED. The status is not touched, so a Pending worker stays Pending.
  /// The ID photo is saved locally only: the backend update sends text
  /// fields, not files.
  ///
  /// Returns an error message, or null on success or when nothing changed.
  Future<String?> saveEdits(
    int workerId,
    Employee original, {
    required String fullName,
    required String nationalId,
    required String phoneNumber,
    required String address,
  }) async {
    final department = _department;
    if (department == null) return 'Select the department';
    if (_enrollmentType == PayType.shiftBased && _shiftType == null) {
      return 'Select the shift';
    }
    if (_isSavingDepartment) return null;

    final trimmedName = fullName.trim();
    final trimmedNationalId = nationalId.trim();
    final trimmedPhone = phoneNumber.trim();
    final trimmedAddress = address.trim();

    final nationalIdChanged = trimmedNationalId != original.employeeId;
    if (nationalIdChanged) {
      final clash = await _employeeRepository.findByEmployeeId(
        trimmedNationalId,
      );
      if (clash != null && clash.id != workerId) {
        return 'National ID $trimmedNationalId is already enrolled';
      }
    }

    final isShiftBased = _enrollmentType == PayType.shiftBased;
    final newShift = isShiftBased ? _shiftType?.name : null;
    final newDob = _dateOfBirth?.toIso8601String();
    final newGender = _gender.name;
    // Keeps the stored attachment unless a new one was captured, so saving
    // doesn't clear a server-side attachment.
    final newImage = _nationalIdImage?.path ?? original.nationalIdImage;

    final departmentChanged = department.id != original.departmentId;
    if (departmentChanged && _departmentLocked) {
      return 'Check out for today before changing the department';
    }
    final typeChanged = _enrollmentType != original.payType;
    final shiftChanged = newShift != original.shiftBasedType;
    final nameChanged = trimmedName != original.name;
    final phoneChanged = trimmedPhone != original.number;
    final addressChanged = trimmedAddress != (original.address ?? '');
    final dobChanged = !_sameDay(
      _dateOfBirth,
      DateTime.tryParse(original.dateOfBirth ?? ''),
    );
    final genderChanged = _gender != original.gender;
    final imageChanged = newImage != original.nationalIdImage;

    final anyChange =
        departmentChanged ||
        typeChanged ||
        shiftChanged ||
        nameChanged ||
        nationalIdChanged ||
        phoneChanged ||
        addressChanged ||
        dobChanged ||
        genderChanged ||
        imageChanged;
    if (!anyChange) return null;
    // A Rejected worker that's edited goes back to Pending, so it can be
    // reviewed and synced again. The row is updated, not duplicated.
    final resubmitting = original.status == 'rejected';
    // Only modified_date moves on an edit — created_date is never rewritten.
    final editedAt = AppTime.nowInUserZone().toIso8601String();

    final localColumns = <String, Object?>{
      if (resubmitting) 'status': 'pending',
      if (nameChanged) 'full_name': trimmedName,
      if (nationalIdChanged) 'national_id': trimmedNationalId,
      if (phoneChanged) 'phone_number': trimmedPhone,
      if (addressChanged) 'address': trimmedAddress,
      if (dobChanged) 'birth_date': newDob,
      if (genderChanged) 'gender': newGender,
      if (imageChanged) 'national_id_image': newImage,
      if (departmentChanged) 'department_id': department.id,
      if (typeChanged) 'enrollment_type': _enrollmentType.name,
      // Local copy always mirrors the type: null whenever it isn't Shift Based.
      if (typeChanged || shiftChanged) 'shift_based_type': newShift,
      'modified_date': editedAt,
    };
    // Shift is only sent when Shift Based is selected or its shift changed —
    // switching away from Shift Based clears it locally but sends nothing.
    final remoteChanges = <String, String>{
      if (resubmitting) 'status': 'pending',
      if (nameChanged) 'full_name': trimmedName,
      if (nationalIdChanged) 'national_id': trimmedNationalId,
      if (phoneChanged) 'phone_number': trimmedPhone,
      if (addressChanged) 'address': trimmedAddress,
      if (dobChanged && newDob != null) 'birth_date': newDob,
      if (genderChanged) 'gender': newGender,
      if (departmentChanged) 'department_id': department.id.toString(),
      if (typeChanged) 'enrollment_type': _enrollmentType.name,
      if (isShiftBased && (typeChanged || shiftChanged))
        'shift_based_type': newShift!,
    };

    _isSavingDepartment = true;
    safeNotify();
    try {
      await _employeeRepository.updateEnrollment(
        workerId: workerId,
        columns: localColumns,
        departmentChanged: departmentChanged,
      );
      await _editQueue.record(workerId, remoteChanges);
      return null;
    } catch (e) {
      return e.toString();
    } finally {
      _isSavingDepartment = false;
      safeNotify();
    }
  }

  static bool _sameDay(DateTime? a, DateTime? b) {
    if (a == null || b == null) return a == b;
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }
}
