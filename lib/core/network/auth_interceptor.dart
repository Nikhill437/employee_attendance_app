import 'package:dio/dio.dart';

import '../../data/repositories/api_token_repository.dart';
import 'api_exception.dart';

/// One interceptor covering everything every request needs:
/// - attaches the bearer token (when one is stored) and common headers
/// - normalizes every failure into an [ApiException], attached as the
///   DioException's `error` — [ApiClient] unwraps it so callers never touch
///   Dio types directly.
class AuthInterceptor extends Interceptor {
  final ApiTokenRepository _tokenRepository;

  AuthInterceptor({ApiTokenRepository? tokenRepository})
    : _tokenRepository = tokenRepository ?? ApiTokenRepository();

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    options.headers['Accept'] = 'application/json';
    // FormData (a multipart upload, e.g. syncing a worker's National ID
    // photo) needs its own content-type with a boundary — Dio sets that
    // itself from options.contentType; forcing JSON here would break it.
    if (options.data is! FormData) {
      options.headers['Content-Type'] = 'application/json';
    }

    final token = await _tokenRepository.getToken();
    if (token != null && token.isNotEmpty) {
      options.headers['Authorization'] = 'Bearer $token';
    }

    handler.next(options);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    handler.next(
      err.copyWith(
        error: ApiException(
          _messageFor(err),
          statusCode: err.response?.statusCode,
          data: err.response?.data,
        ),
      ),
    );
  }

  String _messageFor(DioException err) {
    switch (err.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return 'The request timed out. Check your connection and try again.';
      case DioExceptionType.connectionError:
        return 'Could not reach the server. Check your connection and try again.';
      case DioExceptionType.badResponse:
        return _messageForResponse(err.response?.statusCode, err.response?.data);
      case DioExceptionType.cancel:
        return 'Request cancelled.';
      case DioExceptionType.badCertificate:
        return 'Could not verify the server\'s certificate.';
      case DioExceptionType.unknown:
      default:
        return err.message ?? 'Something went wrong. Please try again.';
    }
  }

  /// Servers here typically respond with a `message` field on failure —
  /// surface that when present, so the UI shows the backend's own reason
  /// instead of a generic one.
  String _messageForResponse(int? statusCode, dynamic data) {
    if (data is Map && data['message'] is String) {
      return data['message'] as String;
    }
    switch (statusCode) {
      case 401:
        return 'Session expired. Please log in again.';
      case 403:
        return 'You do not have permission to do that.';
      case 404:
        return 'Not found.';
      case 500:
        return 'Server error. Please try again later.';
      default:
        return 'Request failed${statusCode != null ? ' ($statusCode)' : ''}.';
    }
  }
}
