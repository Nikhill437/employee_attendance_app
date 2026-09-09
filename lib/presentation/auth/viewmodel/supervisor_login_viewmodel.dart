import '../../../core/base/base_view_model.dart';
import '../../../data/repositories/supervisor_auth_repository.dart';
import '../../../data/repositories/supervisor_session_repository.dart';

/// Drives the supervisor login screen.
class SupervisorLoginViewModel extends BaseViewModel {
  final SupervisorAuthRepository _authRepository;
  final SupervisorSessionRepository _sessionRepository;

  SupervisorLoginViewModel({
    SupervisorAuthRepository? authRepository,
    SupervisorSessionRepository? sessionRepository,
  }) : _authRepository = authRepository ?? SupervisorAuthRepository(),
       _sessionRepository = sessionRepository ?? SupervisorSessionRepository();

  String? _errorMessage;

  String? get errorMessage => _errorMessage;

  /// Clears a message once the view has shown it, so it isn't re-surfaced on
  /// the next rebuild.
  void consumeError() => _errorMessage = null;

  /// Returns true and persists the session on a match, so the supervisor
  /// stays signed in across app restarts until they explicitly log out;
  /// otherwise sets [errorMessage] and returns false.
  Future<bool> login({required String username, required String password}) async {
    final success = _authRepository.authenticate(
      username: username,
      password: password,
    );

    if (success) {
      await _sessionRepository.markLoggedIn();
    } else {
      _errorMessage = 'Incorrect username or password';
    }
    safeNotify();
    return success;
  }
}
