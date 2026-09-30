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

  /// The text to show a user for [error] — [ApiException.message] itself
  /// (already a friendly, network-aware message; see AuthInterceptor) when
  /// that's what failed, or a generic fallback for anything else, so a
  /// snackbar never has to display a raw Dart/platform exception dump.
  static String messageFor(Object error) =>
      error is ApiException ? error.message : 'Something went wrong. Please try again.';
}
