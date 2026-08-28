import '../../core/services/face_recognition_service.dart';
import '../models/attendance_log_model.dart';
import '../models/auth/auth_session_model.dart';
import '../models/auth/auth_user_model.dart';
import '../models/auth/login_request_model.dart';
import '../models/auth/login_result_model.dart';
import 'attendance_repository.dart';
import 'employee_repository.dart';

/// Face-based authentication: 1:1 verification of a claimed employeeId, and
/// the attendance log written when it succeeds.
class AuthRepository {
  final EmployeeRepository _employees;
  final AttendanceRepository _attendance;
  final FaceRecognitionService _faceService;

  AuthRepository({
    EmployeeRepository? employees,
    AttendanceRepository? attendance,
    FaceRecognitionService? faceService,
  }) : _employees = employees ?? EmployeeRepository(),
       _attendance = attendance ?? AttendanceRepository(),
       _faceService = faceService ?? FaceRecognitionService();

  AuthSession _session = const AuthSession.signedOut();

  AuthSession get session => _session;

  void signOut() => _session = const AuthSession.signedOut();

  /// Pre-scan check: confirms [employeeId] is enrolled and has a face profile,
  /// so the camera isn't opened for an attempt that can't possibly succeed.
  /// Returns the rejecting [LoginResult], or null when the ID is ready to
  /// scan.
  Future<LoginResult?> checkCanLogin(String employeeId) async {
    final employee = await _employees.findByEmployeeId(employeeId);
    if (employee == null) return const LoginResult.employeeNotFound();
    if (employee.faceEmbeddings.isEmpty) {
      return const LoginResult.noEnrolledFace();
    }
    return null;
  }

  /// Verifies the captured embedding against the enrolled profile for the
  /// claimed employeeId only (1:1), and on a match records the attendance log
  /// and opens the session.
  Future<LoginResult> login(LoginRequest request) async {
    final employee = await _employees.findByEmployeeId(request.employeeId);
    if (employee == null) return const LoginResult.employeeNotFound();
    if (employee.faceEmbeddings.isEmpty) {
      return const LoginResult.noEnrolledFace();
    }

    final matched = _faceService.verify(
      request.faceEmbedding,
      employee.faceEmbeddings,
    );
    if (!matched) return const LoginResult.faceNotMatched();

    final user = AuthUser.fromEmployee(employee);
    await _attendance.log(
      AttendanceLog(
        employeeId: user.employeeId,
        employeeName: user.name,
        loginTime: user.authenticatedAt,
      ),
    );

    _session = AuthSession.signedIn(user);
    return LoginResult.success(user);
  }
}
