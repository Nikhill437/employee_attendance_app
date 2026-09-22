import 'package:shared_preferences/shared_preferences.dart';

/// Holds the bearer token used to authenticate API requests.
///
/// There's no login/token-issuing flow in the app yet — supervisor login
/// (`SupervisorAuthRepository`) is a single hardcoded credential checked
/// on-device, not a server call. This exists so [AuthInterceptor] has
/// somewhere to read a token from once a real login call starts issuing one
/// (call [setToken] with whatever it returns).
class ApiTokenRepository {
  static const String _tokenKey = 'api_bearer_token';

  Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_tokenKey);
  }

  Future<void> setToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token);
  }

  Future<void> clearToken() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
  }
}
