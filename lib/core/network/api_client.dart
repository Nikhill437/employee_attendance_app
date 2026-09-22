import 'package:dio/dio.dart';

import 'api_config.dart';
import 'api_exception.dart';
import 'auth_interceptor.dart';
import 'logging_interceptor.dart';

/// Thin Dio wrapper every API-backed repository goes through, so base URL,
/// auth, and error handling only exist in one place.
class ApiClient {
  static final ApiClient _instance = ApiClient._internal();
  factory ApiClient() => _instance;

  final Dio dio;

  ApiClient._internal()
    : dio = Dio(
        BaseOptions(
          baseUrl: ApiConfig.baseUrl,
          connectTimeout: ApiConfig.connectTimeout,
          receiveTimeout: ApiConfig.receiveTimeout,
        ),
      ) {
    // Order matters: onRequest runs Auth then Logging (so logging shows the
    // final request, headers/token included), while onResponse/onError run
    // in reverse — Logging then Auth (so logging shows the raw response or
    // DioException, before Auth rewrites a failure into an ApiException).
    dio.interceptors.addAll([AuthInterceptor(), LoggingInterceptor()]);
  }

  /// POSTs [path] with [data] (a JSON-able `Map`, or `FormData` for a
  /// multipart upload — e.g. syncing a worker's National ID photo),
  /// returning the decoded response body. Always throws [ApiException] on
  /// failure (network, timeout, or a non-2xx response) — callers never need
  /// to touch Dio types.
  Future<dynamic> post(String path, {Object? data}) async {
    try {
      final response = await dio.post(path, data: data);
      return response.data;
    } on DioException catch (e) {
      final error = e.error;
      throw error is ApiException
          ? error
          : ApiException(e.message ?? 'Something went wrong. Please try again.');
    }
  }
}
