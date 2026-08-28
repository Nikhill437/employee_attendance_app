import 'auth_user_model.dart';

/// Why a login attempt ended the way it did.
///
/// The failure reasons are kept distinct so the view can explain what to do
/// next (enroll a face, check the ID, rescan) instead of showing one generic
/// error.
enum LoginStatus {
  success,
  employeeNotFound,
  noEnrolledFace,
  faceNotMatched,
  failure,
}

/// Outcome of a [LoginRequest]: either an authenticated [user], or a status
/// explaining the rejection.
class LoginResult {
  final LoginStatus status;
  final AuthUser? user;

  /// Human-readable detail for [LoginStatus.failure]; null otherwise.
  final String? message;

  const LoginResult._({required this.status, this.user, this.message});

  const LoginResult.success(AuthUser user)
    : this._(status: LoginStatus.success, user: user);

  const LoginResult.employeeNotFound()
    : this._(status: LoginStatus.employeeNotFound);

  const LoginResult.noEnrolledFace()
    : this._(status: LoginStatus.noEnrolledFace);

  const LoginResult.faceNotMatched()
    : this._(status: LoginStatus.faceNotMatched);

  const LoginResult.failure(String message)
    : this._(status: LoginStatus.failure, message: message);

  bool get isSuccess => status == LoginStatus.success;

  /// Message to surface to the user for a rejected attempt, or null when the
  /// attempt succeeded.
  String? get errorMessage {
    switch (status) {
      case LoginStatus.success:
        return null;
      case LoginStatus.employeeNotFound:
        return 'No employee found with that ID';
      case LoginStatus.noEnrolledFace:
        return 'This employee has no enrolled face. Enroll first.';
      case LoginStatus.faceNotMatched:
        return 'Face Recognition Failed';
      case LoginStatus.failure:
        return message ?? 'Something went wrong';
    }
  }
}
