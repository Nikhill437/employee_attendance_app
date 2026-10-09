import '../../../core/base/base_view_model.dart';
import '../../../core/utils/app_time.dart';
import '../../../data/models/employee_model.dart';
import '../../../data/models/worker_model.dart';
import '../../../data/repositories/employee_repository.dart';
import '../../../data/repositories/task_repository.dart';

/// Drives employee enrollment: holds the captured multi-pose face profile
/// until the form is submitted, then persists the employee.
class CreateEmployeeViewModel extends BaseViewModel {
  final EmployeeRepository _employeeRepository;
  final TaskRepository _taskRepository;

  CreateEmployeeViewModel({
    EmployeeRepository? employeeRepository,
    TaskRepository? taskRepository,
  }) : _employeeRepository = employeeRepository ?? EmployeeRepository(),
       _taskRepository = taskRepository ?? TaskRepository();

  bool _isSaving = false;
  List<List<double>>? _faceEmbeddings;

  bool get isSaving => _isSaving;
  bool get isFaceVerified => _faceEmbeddings != null;

  void setFaceEmbeddings(List<List<double>> embeddings) {
    _faceEmbeddings = embeddings;
    safeNotify();
  }

  /// Checked before capturing a face, so a duplicate National ID is caught
  /// while it's still cheap to fix rather than after the scan.
  Future<bool> isNationalIdTaken(String employeeId) =>
      _employeeRepository.isEmployeeIdTaken(employeeId);

  /// Persists the employee with the captured face profile, returning the
  /// saved record (with its row id). Returns null when no face has been
  /// captured yet.
  ///
  /// When [taskId] is set, also assigns that task to the newly-created
  /// worker right away (rather than waiting for backend approval, like
  /// `workers.task_id` alone does — see DatabaseHelper.upsertRemoteWorkers)
  /// so [taskNote] has a `worker_tasks` row to actually land in.
  Future<Employee?> save({
    required String name,
    required String number,
    required String employeeId,
    String? dateOfBirth,
    Gender gender = Gender.other,
    String? address,
    String? department,
    int? departmentId,
    String? nationalIdImage,
    int? taskId,
    String? taskNote,
  }) async {
    final embeddings = _faceEmbeddings;
    if (embeddings == null) return null;

    _isSaving = true;
    safeNotify();

    final saved = await _employeeRepository.create(
      Employee(
        name: name,
        number: number,
        employeeId: employeeId,
        attendanceTime: AppTime.nowInUserZone().toIso8601String(),
        faceVerified: true,
        faceEmbeddings: embeddings,
        dateOfBirth: dateOfBirth,
        gender: gender,
        address: address,
        department: department,
        departmentId: departmentId,
        nationalIdImage: nationalIdImage,
        taskId: taskId,
      ),
    );

    final workerId = saved.id;
    if (taskId != null && workerId != null) {
      await _taskRepository.assignTask(
        workerId: workerId,
        taskId: taskId,
        note: (taskNote == null || taskNote.trim().isEmpty)
            ? null
            : taskNote.trim(),
      );
    }

    _isSaving = false;
    safeNotify();
    return saved;
  }
}
