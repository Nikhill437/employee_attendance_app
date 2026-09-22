import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
import '../../core/network/api_routes.dart';

/// Remote datasource for supervisor login.
class SupervisorAuthApi {
  final ApiClient _client;

  SupervisorAuthApi({ApiClient? client}) : _client = client ?? ApiClient();

  /// POST /auth/verifyUser. Confirmed response shape:
  /// `{"message": "Login successful", "user": {"id", "email", "name",
  /// "role", "timezone", "district_id"}, "AccessTokenss": "...",
  /// "RefreshToken": "..."}` — yes, "AccessTokenss", that's the actual
  /// field name the backend returns, typo included.
  ///
  /// Wrong credentials are expected to come back as a non-2xx response,
  /// which [ApiClient.post] already turns into an [ApiException] — that
  /// propagates out of here as-is, so the caller doesn't need to special
  /// case it.
  Future<Map<String, dynamic>> login({
    required String username,
    required String password,
  }) async {
    final data = await _client.post(
      ApiRoutes.login,
      data: {'validemail': username, 'validPass': password},
    );
    if (data is! Map<String, dynamic>) {
      throw const ApiException('Unexpected login response shape.');
    }
    return data;
  }
}
