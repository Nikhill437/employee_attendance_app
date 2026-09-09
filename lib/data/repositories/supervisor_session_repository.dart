import 'package:shared_preferences/shared_preferences.dart';

/// Whether a supervisor is currently signed in, kept on disk so the session
/// survives closing and reopening the app — only an explicit logout (from
/// [SettingsScreen]) or clearing app data ends it.
class SupervisorSessionRepository {
  static const String _loggedInKey = 'supervisor_logged_in';

  Future<bool> isLoggedIn() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_loggedInKey) ?? false;
  }

  Future<void> markLoggedIn() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_loggedInKey, true);
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_loggedInKey, false);
  }
}
