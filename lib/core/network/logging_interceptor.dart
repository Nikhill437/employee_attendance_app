import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

/// Logs every API call's URL, the body sent to the server, and the body (or
/// error) that came back — debug builds only, since request/response bodies
/// here can carry PII (National IDs, phone numbers) and the auth token.
class LoggingInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (kDebugMode) {
      debugPrint('[API] → ${options.method} ${options.uri}');
      if (options.data != null) {
        debugPrint('[API] → body: ${_describeBody(options.data)}');
      }
    }
    handler.next(options);
  }

  /// `FormData.toString()` just shows the object's type/hash, not what's
  /// actually in it — spell out its fields and file names instead, so a
  /// multipart request (e.g. syncing a worker with their National ID
  /// photo) logs something useful.
  String _describeBody(dynamic data) {
    if (data is FormData) {
      final fields = {for (final e in data.fields) e.key: e.value};
      final files = [
        for (final e in data.files)
          '${e.key}: ${e.value.filename} (${e.value.length} bytes)',
      ];
      return 'FormData fields=$fields files=$files';
    }
    return data.toString();
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    if (kDebugMode) {
      final options = response.requestOptions;
      debugPrint(
        '[API] ← ${options.method} ${options.uri} (${response.statusCode})',
      );
      debugPrint('[API] ← body: ${response.data}');
    }
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    if (kDebugMode) {
      final options = err.requestOptions;
      debugPrint(
        '[API] ✗ ${options.method} ${options.uri} '
        '(${err.response?.statusCode ?? err.type})',
      );
      if (err.response?.data != null) {
        debugPrint('[API] ✗ body: ${err.response?.data}');
      }
    }
    handler.next(err);
  }
}
