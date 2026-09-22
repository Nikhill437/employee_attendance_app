import '../../core/network/api_exception.dart';
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
      final token = _extractToken(response);
      if (token == null || token.isEmpty) {
        return 'Login succeeded but no token was returned.';
      }
      await _tokenRepository.setToken(token);
      await _sessionRepository.saveSession(response);
      return null;
    } on ApiException catch (e) {
      return e.message;
    }
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
}
