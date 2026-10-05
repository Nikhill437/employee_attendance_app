import '../../core/network/api_exception.dart';
import '../../core/utils/app_time.dart';
import '../datasources/supervisor_auth_api.dart';
import 'api_token_repository.dart';
import 'supervisor_session_repository.dart';

/// Supervisor login — authenticates against the backend
/// (`POST /auth/verifyUser`), stores the returned access token so every
/// other API call picks it up automatically (see AuthInterceptor), and
/// keeps the whole raw response around locally (see
/// SupervisorSessionRepository) so it doesn't need re-fetching.
class SupervisorAuthRepository {
  final SupervisorAuthApi _api;
  final ApiTokenRepository _tokenRepository;
  final SupervisorSessionRepository _sessionRepository;

  SupervisorAuthRepository({
    SupervisorAuthApi? api,
    ApiTokenRepository? tokenRepository,
    SupervisorSessionRepository? sessionRepository,
  }) : _api = api ?? SupervisorAuthApi(),
       _tokenRepository = tokenRepository ?? ApiTokenRepository(),
       _sessionRepository = sessionRepository ?? SupervisorSessionRepository();

  /// Returns null on success (and stores the token + full response), or an
  /// error message to show the supervisor on failure — wrong credentials
  /// and network/server errors both surface here rather than throwing, so
  /// the login screen has one thing to display either way.
  Future<String?> authenticate({
    required String username,
    required String password,
  }) async {
    try {
      final response = await _api.login(
        username: username.trim(),
        password: password,
      );
      if (!_isSupervisor(response)) {
        return 'Only supervisors can log in to this app.';
      }
      final token = _extractToken(response);
      if (token == null || token.isEmpty) {
        return 'Login succeeded but no token was returned.';
      }
      await _tokenRepository.setToken(token);
      await _sessionRepository.saveSession(response);
      // The confirmed login response includes the supervisor's own IANA
      // timezone under user.timezone — activating it here (rather than
      // only when AppTime.init() next runs, on the following app launch)
      // means every timestamp shown for the rest of *this* session is
      // already in their timezone too.
      await AppTime.setTimeZone(_extractTimeZone(response));
      return null;
    } on ApiException catch (e) {
      return e.message;
    }
  }

  /// Only a `supervisor` role may sign in. The role comes back under
  /// `user.role` (see the confirmed response shape in SupervisorAuthApi);
  /// a missing role is treated as not-a-supervisor rather than let through.
  bool _isSupervisor(Map<String, dynamic> response) {
    final user = response['user'];
    final role = user is Map ? user['role'] : response['role'];
    return role is String && role.trim().toLowerCase() == 'supervisor';
  }

  /// The confirmed field is `AccessTokenss` (typo included, that's what the
  /// backend actually returns) — correctly-spelled variants are checked
  /// first in case that gets fixed backend-side later.
  String? _extractToken(Map<String, dynamic> response) {
    for (final key in [
      'accessToken',
      'access_token',
      'AccessToken',
      'AccessTokenss',
    ]) {
      final value = response[key];
      if (value is String && value.isNotEmpty) return value;
    }
    return null;
  }

  /// The confirmed login response sample is `{"message", "user": {"id",
  /// "email", "name", "role", "timezone", "district_id"}, ...}` — same
  /// defensive multi-key-path approach as
  /// SupervisorSessionRepository.getSupervisorDepartmentId, since the
  /// field's exact placement isn't confirmed beyond that one sample.
  String? _extractTimeZone(Map<String, dynamic> response) {
    final user = response['user'];
    final candidates = <Object?>[
      response['timezone'],
      response['time_zone'],
      if (user is Map) user['timezone'],
      if (user is Map) user['time_zone'],
    ];
    for (final candidate in candidates) {
      if (candidate is String && candidate.trim().isNotEmpty) {
        return candidate;
      }
    }
    return null;
  }
}
