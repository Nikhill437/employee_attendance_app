import 'auth_user_model.dart';

/// The app's current authentication state.
///
/// Held in memory only — a face login is valid for the run of the app, and
/// nothing about the session is persisted to disk.
class AuthSession {
  final AuthUser? user;

  const AuthSession.signedOut() : user = null;
  const AuthSession.signedIn(AuthUser this.user);

  bool get isSignedIn => user != null;
}
