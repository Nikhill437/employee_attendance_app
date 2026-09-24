/// Central place for backend API configuration.
///
/// Single fixed URL for now — there's only one environment today. Split
/// this into per-environment (dev/staging/prod) config if/when that exists.
class ApiConfig {
  const ApiConfig._();

  static const String baseUrl = 'http://192.168.1.107:3001/';

  static const Duration connectTimeout = Duration(seconds: 15);
  static const Duration receiveTimeout = Duration(seconds: 15);
}
