import '../../../core/base/base_view_model.dart';
import '../../../data/models/auth/auth_user_model.dart';
import '../../../data/models/auth/login_request_model.dart';
import '../../../data/repositories/auth_repository.dart';

/// Drives the login screen: employee-ID lookup, then face verification for
/// that one claimed identity.
class LoginViewModel extends BaseViewModel {
  final AuthRepository _authRepository;

  LoginViewModel({AuthRepository? authRepository})
    : _authRepository = authRepository ?? AuthRepository();

  bool _isLookingUp = false;
  String? _errorMessage;
  AuthUser? _authenticatedUser;

  bool get isLookingUp => _isLookingUp;
  String? get errorMessage => _errorMessage;
  AuthUser? get authenticatedUser => _authenticatedUser;
  bool get isAuthenticated => _authenticatedUser != null;

  /// Clears a message once the view has shown it, so it isn't re-surfaced on
  /// the next rebuild.
  void consumeError() => _errorMessage = null;

  /// Checks the entered ID before the camera is opened. Returns true when the
  /// employee exists and has an enrolled face; otherwise sets [errorMessage].
  Future<bool> prepareLogin(String employeeId) async {
    _isLookingUp = true;
    _errorMessage = null;
    safeNotify();

    final rejection = await _authRepository.checkCanLogin(employeeId);

    _isLookingUp = false;
    _errorMessage = rejection?.errorMessage;
    safeNotify();

    return rejection == null;
  }

  /// Verifies a captured embedding against [employeeId]'s enrolled profile
  /// and, on success, marks attendance. Returns the authenticated user, or
  /// null so the scan screen keeps scanning.
  Future<AuthUser?> authenticate(
    String employeeId,
    List<double> embedding,
  ) async {
    final result = await _authRepository.login(
      LoginRequest(employeeId: employeeId, faceEmbedding: embedding),
    );

    if (!result.isSuccess) {
      _errorMessage = result.errorMessage;
      safeNotify();
      return null;
    }

    _authenticatedUser = result.user;
    safeNotify();
    return result.user;
  }

  /// Marks the login as complete once the scan screen has handed the matched
  /// user back, so the view can show its success state.
  void completeLogin(AuthUser user) {
    _authenticatedUser = user;
    safeNotify();
  }
}
