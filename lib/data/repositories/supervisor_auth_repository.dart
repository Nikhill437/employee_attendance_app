/// Fixed-credential supervisor login.
///
/// A single supervisor account, not a table of them — there is no
/// supervisor-management flow in this app yet, so the credentials are
/// constants rather than rows in the database.
class SupervisorAuthRepository {
  static const String _username = 'sanket';
  static const String _password = 'Pass@123';

  bool authenticate({required String username, required String password}) {
    return username.trim() == _username && password == _password;
  }
}
