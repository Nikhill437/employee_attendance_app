import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'api_token_repository.dart';

/// Whether a supervisor is currently signed in, kept on disk so the session
/// survives closing and reopening the app — only an explicit logout (from
/// [SettingsScreen]) or clearing app data ends it. Also holds the whole raw
/// login response (see SupervisorAuthApi.login) — profile fields, refresh
/// token, whatever else the backend sends — so it's available locally
/// without another network round trip.
class SupervisorSessionRepository {
  static const String _loggedInKey = 'supervisor_logged_in';
  static const String _sessionKey = 'supervisor_session';

  final ApiTokenRepository _tokenRepository;

  SupervisorSessionRepository({ApiTokenRepository? tokenRepository})
    : _tokenRepository = tokenRepository ?? ApiTokenRepository();

  Future<bool> isLoggedIn() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_loggedInKey) ?? false;
  }

  Future<void> markLoggedIn() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_loggedInKey, true);
  }

  /// Ends the session and clears the stored access token — otherwise the
  /// next unauthenticated screen would still be sending a valid bearer
  /// token on any request that happened to fire.
  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_loggedInKey, false);
    await prefs.remove(_sessionKey);
    await _tokenRepository.clearToken();
  }

  /// Persists the whole login response as-is, so it's available later
  /// (e.g. the supervisor's name/email/role) without hitting the network
  /// again.
  Future<void> saveSession(Map<String, dynamic> loginResponse) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_sessionKey, jsonEncode(loginResponse));
  }

  /// The raw login response saved by [saveSession], or null if there isn't
  /// one (never logged in, or it was cleared by [logout]).
  Future<Map<String, dynamic>?> getSession() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_sessionKey);
    if (raw == null) return null;
    return jsonDecode(raw) as Map<String, dynamic>;
  }
}
