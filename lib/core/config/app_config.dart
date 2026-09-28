enum AppEnvironment { testing, production }

class AppConfig {
  static const String _env = String.fromEnvironment(
    'APP_ENV',
    defaultValue: 'testing',
  );

  static AppEnvironment get environment =>
      _env == 'testing' ? AppEnvironment.testing : AppEnvironment.production;

  static bool get isTesting => environment == AppEnvironment.testing;
  static bool get isProduction => environment == AppEnvironment.production;

  /// Prefix for all SharedPreferences keys so test and prod never collide.
  static String get envPrefix => isTesting ? 'test_' : 'prod_';
}
