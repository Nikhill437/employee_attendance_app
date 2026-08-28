import '../employee_model.dart';

/// The identity of an employee who has successfully authenticated by face.
///
/// Deliberately narrower than [Employee]: it carries only what the signed-in
/// session needs to display and log, never the enrolled face embeddings, so
/// biometric data isn't passed around the presentation layer.
class AuthUser {
  final int? id;
  final String employeeId;
  final String name;
  final String number;

  /// When this session was established (ISO-8601).
  final String authenticatedAt;

  const AuthUser({
    this.id,
    required this.employeeId,
    required this.name,
    required this.number,
    required this.authenticatedAt,
  });

  factory AuthUser.fromEmployee(Employee employee, {DateTime? at}) {
    return AuthUser(
      id: employee.id,
      employeeId: employee.employeeId,
      name: employee.name,
      number: employee.number,
      authenticatedAt: (at ?? DateTime.now()).toIso8601String(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'employeeId': employeeId,
      'name': name,
      'number': number,
      'authenticatedAt': authenticatedAt,
    };
  }

  factory AuthUser.fromMap(Map<String, dynamic> map) {
    return AuthUser(
      id: map['id'] as int?,
      employeeId: map['employeeId'] as String,
      name: map['name'] as String,
      number: map['number'] as String,
      authenticatedAt: map['authenticatedAt'] as String,
    );
  }
}
