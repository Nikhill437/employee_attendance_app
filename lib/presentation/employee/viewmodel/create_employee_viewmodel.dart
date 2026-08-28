import '../../../core/base/base_view_model.dart';
import '../../../data/models/employee_model.dart';
import '../../../data/repositories/employee_repository.dart';

/// Drives employee enrollment: holds the captured multi-pose face profile
/// until the form is submitted, then persists the employee.
class CreateEmployeeViewModel extends BaseViewModel {
  final EmployeeRepository _employeeRepository;

  CreateEmployeeViewModel({EmployeeRepository? employeeRepository})
    : _employeeRepository = employeeRepository ?? EmployeeRepository();

  bool _isSaving = false;
  List<List<double>>? _faceEmbeddings;

  bool get isSaving => _isSaving;
  bool get isFaceVerified => _faceEmbeddings != null;

  void setFaceEmbeddings(List<List<double>> embeddings) {
    _faceEmbeddings = embeddings;
    safeNotify();
  }

  /// Persists the employee with the captured face profile, returning the
  /// saved record (with its row id). Returns null when no face has been
  /// captured yet.
  Future<Employee?> save({
    required String name,
    required String number,
    required String employeeId,
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
        attendanceTime: DateTime.now().toIso8601String(),
        faceVerified: true,
        faceEmbeddings: embeddings,
      ),
    );

    _isSaving = false;
    safeNotify();
    return saved;
  }
}
