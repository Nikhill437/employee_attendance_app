import 'package:sqflite/sqflite.dart';

/// A function that returns the [Database] instance the explorer should use.
///
/// This is almost always a reference to the host app's existing database
/// getter (e.g. `() => DatabaseHelper().database`), so the explorer shares
/// the same open connection instead of opening a second one.
typedef DatabaseProvider = Future<Database> Function();

/// Connection configuration for the reusable database explorer.
///
/// The explorer never opens or closes a database on its own — it only reads
/// the [Database] handed to it by [databaseProvider]. Call [configure] once,
/// before navigating to `DatabaseExplorerScreen`, from your own integration
/// code (see the integration instructions provided with this feature).
class DatabaseExplorerConfig {
  DatabaseExplorerConfig._({
    required this.databaseProvider,
    required this.databaseLabel,
  });

  /// Supplies the live [Database] instance to inspect/query.
  final DatabaseProvider databaseProvider;

  /// A human-readable label shown in the explorer UI (e.g. the file name).
  final String databaseLabel;

  static DatabaseExplorerConfig? _instance;

  /// Registers the database the explorer should connect to.
  ///
  /// Call this once during app startup (or lazily, right before opening
  /// `DatabaseExplorerScreen`) with a reference to your app's existing
  /// database provider. Calling it again replaces the previous configuration.
  static void configure({
    required DatabaseProvider databaseProvider,
    String databaseLabel = 'App Database',
  }) {
    _instance = DatabaseExplorerConfig._(
      databaseProvider: databaseProvider,
      databaseLabel: databaseLabel,
    );
  }

  /// The active configuration. Throws a [StateError] if [configure] has not
  /// been called yet.
  static DatabaseExplorerConfig get instance {
    final config = _instance;
    if (config == null) {
      throw StateError(
        'DatabaseExplorerConfig has not been configured. Call '
        'DatabaseExplorerConfig.configure(databaseProvider: ...) before '
        'opening DatabaseExplorerScreen.',
      );
    }
    return config;
  }

  static bool get isConfigured => _instance != null;
}
