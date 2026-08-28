/// A single 1:1 login attempt: a claimed [employeeId] plus the live face
/// embedding captured for it.
///
/// Login is verification, not search — the embedding is only ever compared
/// against the profile enrolled for this one employeeId.
class LoginRequest {
  final String employeeId;
  final List<double> faceEmbedding;

  const LoginRequest({required this.employeeId, required this.faceEmbedding});

  LoginRequest copyWith({String? employeeId, List<double>? faceEmbedding}) {
    return LoginRequest(
      employeeId: employeeId ?? this.employeeId,
      faceEmbedding: faceEmbedding ?? this.faceEmbedding,
    );
  }
}
