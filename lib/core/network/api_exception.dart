/// Uniform error shape every API call fails with — callers catch this
/// instead of Dio's `DioException`, so network, timeout, and server-error
/// handling look the same everywhere the app talks to the backend.
class ApiException implements Exception {
  final String message;
  final int? statusCode;
  final dynamic data;

  const ApiException(this.message, {this.statusCode, this.data});

  @override
  String toString() => 'ApiException($statusCode): $message';
}
