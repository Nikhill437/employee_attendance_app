import '../../../core/base/base_view_model.dart';
import '../../../data/repositories/supervisor_session_repository.dart';

/// Drives the settings screen.
class SettingsViewModel extends BaseViewModel {
  final SupervisorSessionRepository _sessionRepository;

  SettingsViewModel({SupervisorSessionRepository? sessionRepository})
    : _sessionRepository = sessionRepository ?? SupervisorSessionRepository();

  bool _isLoggingOut = false;

  bool get isLoggingOut => _isLoggingOut;

  /// Ends the persisted supervisor session. The next app launch — and any
  /// navigation from here — needs a fresh login.
  Future<void> logout() async {
    _isLoggingOut = true;
    safeNotify();

    await _sessionRepository.logout();

    _isLoggingOut = false;
    safeNotify();
  }
}
