import 'package:sqflite/sqflite.dart';

import 'database_explorer_config.dart';

/// Metadata about a single table, used by the overview/table list screen.
class DatabaseTableInfo {
  const DatabaseTableInfo({required this.name, required this.rowCount});

  final String name;
  final int rowCount;
}

/// A single column as reported by `PRAGMA table_info`.
class ColumnInfo {
  const ColumnInfo({
    required this.name,
    required this.type,
    required this.notNull,
    required this.primaryKey,
    this.defaultValue,
  });

  final String name;
  final String type;
  final bool notNull;
  final bool primaryKey;
  final Object? defaultValue;

  factory ColumnInfo.fromRow(Map<String, Object?> row) {
    return ColumnInfo(
      name: row['name'] as String,
      type: (row['type'] as String?) ?? '',
      notNull: (row['notnull'] as int? ?? 0) == 1,
      primaryKey: (row['pk'] as int? ?? 0) > 0,
      defaultValue: row['dflt_value'],
    );
  }
}

/// Broad classification of a SQL statement, used to drive UI affordances
/// (read-only badge, destructive-action confirmation, etc).
enum QueryKind { select, write, ddl, other }

/// SQLite's type affinity rules, used to coerce edited text back into a
/// reasonable Dart value for a given column.
enum ColumnAffinity { integer, real, numeric, text, blob }

ColumnAffinity columnAffinityFor(String declaredType) {
  final type = declaredType.toUpperCase();
  if (type.contains('INT')) return ColumnAffinity.integer;
  if (type.contains('CHAR') ||
      type.contains('CLOB') ||
      type.contains('TEXT')) {
    return ColumnAffinity.text;
  }
  if (type.contains('BLOB') || type.isEmpty) return ColumnAffinity.blob;
  if (type.contains('REAL') ||
      type.contains('FLOA') ||
      type.contains('DOUB')) {
    return ColumnAffinity.real;
  }
  return ColumnAffinity.numeric;
}

/// Converts the text entered for [column] back into a value suitable for a
/// parameterized SQLite statement, following [column]'s type affinity. An
/// empty string always means `NULL`. Throws [FormatException] if the text
/// doesn't match the column's affinity (e.g. "abc" for an INTEGER column).
Object? coerceEditedValue(String text, ColumnInfo column) {
  if (text.isEmpty) return null;
  switch (columnAffinityFor(column.type)) {
    case ColumnAffinity.integer:
      final value = int.tryParse(text.trim());
      if (value == null) {
        throw FormatException(
          '"$text" is not a valid integer for "${column.name}"',
        );
      }
      return value;
    case ColumnAffinity.real:
      final value = double.tryParse(text.trim());
      if (value == null) {
        throw FormatException(
          '"$text" is not a valid number for "${column.name}"',
        );
      }
      return value;
    case ColumnAffinity.numeric:
      final trimmed = text.trim();
      return int.tryParse(trimmed) ?? double.tryParse(trimmed) ?? text;
    case ColumnAffinity.text:
    case ColumnAffinity.blob:
      return text;
  }
}

/// The result of executing a single SQL statement through the explorer.
class QueryExecutionResult {
  const QueryExecutionResult({
    required this.success,
    required this.kind,
    required this.columns,
    required this.rows,
    required this.duration,
    required this.rawSql,
    this.affectedRows,
    this.errorMessage,
  });

  final bool success;
  final QueryKind kind;
  final List<String> columns;
  final List<Map<String, Object?>> rows;
  final int? affectedRows;
  final String? errorMessage;
  final Duration duration;
  final String rawSql;

  bool get isSelect => kind == QueryKind.select;
}

/// Inspects and queries whatever [Database] is handed to it by
/// [DatabaseExplorerConfig]. Contains no knowledge of any specific app's
/// tables, models, or repositories.
class DatabaseExplorerService {
  DatabaseExplorerService({DatabaseExplorerConfig? config})
    : _config = config ?? DatabaseExplorerConfig.instance;

  final DatabaseExplorerConfig _config;

  static const _systemTables = {'android_metadata', 'sqlite_sequence'};

  /// Alias under which a row's SQLite `rowid` is fetched by
  /// [getTableRowsEditable]. Used as a stable row identifier for inline
  /// editing — it works for any ordinary table regardless of whether (or
  /// how) it declares a primary key, since every normal SQLite table has an
  /// implicit `rowid` unless created `WITHOUT ROWID`.
  static const rowIdAlias = '__rowid__';

  Future<Database> get _db => _config.databaseProvider();

  String get databaseLabel => _config.databaseLabel;

  /// All user-defined table names in the database, sorted alphabetically.
  Future<List<String>> getTableNames() async {
    final db = await _db;
    final result = await db.rawQuery(
      "SELECT name FROM sqlite_master "
      "WHERE type = 'table' AND name NOT LIKE 'sqlite_%' "
      "ORDER BY name",
    );
    return result
        .map((row) => row['name'] as String)
        .where((name) => !_systemTables.contains(name))
        .toList();
  }

  /// Table names plus their current row counts, for the overview screen.
  Future<List<DatabaseTableInfo>> getTableOverview() async {
    final db = await _db;
    final names = await getTableNames();
    final infos = <DatabaseTableInfo>[];
    for (final name in names) {
      final countResult = await db.rawQuery(
        'SELECT COUNT(*) AS count FROM "$name"',
      );
      infos.add(
        DatabaseTableInfo(
          name: name,
          rowCount: Sqflite.firstIntValue(countResult) ?? 0,
        ),
      );
    }
    return infos;
  }

  /// Column definitions for [table], via `PRAGMA table_info`.
  Future<List<ColumnInfo>> getTableColumns(String table) async {
    final db = await _db;
    final result = await db.rawQuery('PRAGMA table_info("$table")');
    return result.map(ColumnInfo.fromRow).toList();
  }

  Future<int> getRowCount(String table) async {
    final db = await _db;
    final result = await db.rawQuery('SELECT COUNT(*) AS c FROM "$table"');
    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// A page of rows from [table].
  Future<QueryExecutionResult> getTableRows(
    String table, {
    int limit = 100,
    int offset = 0,
  }) {
    return executeQuery('SELECT * FROM "$table" LIMIT $limit OFFSET $offset');
  }

  /// A page of rows from [table], each carrying its SQLite `rowid` under
  /// [rowIdAlias] so the caller can identify a specific row for editing
  /// without relying on the table's own primary key (which may be
  /// composite, or absent entirely). Fails with a "no such column: rowid"
  /// style error for `WITHOUT ROWID` tables — callers should fall back to
  /// [getTableRows] (read-only) in that case.
  Future<QueryExecutionResult> getTableRowsEditable(
    String table, {
    int limit = 100,
    int offset = 0,
  }) {
    return executeQuery(
      'SELECT rowid AS "$rowIdAlias", * FROM "$table" LIMIT $limit OFFSET $offset',
    );
  }

  /// Updates a single row of [table], identified by its SQLite `rowid`
  /// (see [getTableRowsEditable]), setting only the columns present in
  /// [changes]. Uses a parameterized statement, so values are never
  /// interpolated into the SQL text.
  Future<QueryExecutionResult> updateRowByRowId({
    required String table,
    required Object? rowId,
    required Map<String, Object?> changes,
  }) {
    if (changes.isEmpty) {
      return Future.value(
        QueryExecutionResult(
          success: true,
          kind: QueryKind.write,
          columns: const [],
          rows: const [],
          affectedRows: 0,
          duration: Duration.zero,
          rawSql: '-- no changes --',
        ),
      );
    }
    final setClause = changes.keys.map((c) => '"$c" = ?').join(', ');
    final sql = 'UPDATE "$table" SET $setClause WHERE rowid = ?';
    return executeQuery(sql, arguments: [...changes.values, rowId]);
  }

  /// Classifies [sql] by its leading keyword. Used to label results and to
  /// decide which statements require confirmation before running.
  QueryKind classify(String sql) {
    final trimmed = sql.trim();
    if (trimmed.isEmpty) return QueryKind.other;
    final firstWord = trimmed.split(RegExp(r'\s+')).first.toUpperCase();
    switch (firstWord) {
      case 'SELECT':
      case 'PRAGMA':
      case 'EXPLAIN':
        return QueryKind.select;
      case 'INSERT':
      case 'UPDATE':
      case 'DELETE':
      case 'REPLACE':
        return QueryKind.write;
      case 'CREATE':
      case 'ALTER':
      case 'DROP':
        return QueryKind.ddl;
      default:
        return QueryKind.other;
    }
  }

  /// Whether [sql] modifies data or schema and should be confirmed before
  /// running.
  bool isDestructive(String sql) {
    final kind = classify(sql);
    return kind == QueryKind.write || kind == QueryKind.ddl;
  }

  /// Executes a single SQL statement and returns a uniform result, never
  /// throwing — failures are reported via [QueryExecutionResult.success]
  /// and [QueryExecutionResult.errorMessage].
  Future<QueryExecutionResult> executeQuery(
    String sql, {
    List<Object?>? arguments,
  }) async {
    final stopwatch = Stopwatch()..start();
    final kind = classify(sql);
    try {
      final db = await _db;
      if (kind == QueryKind.select) {
        final rows = await db.rawQuery(sql, arguments);
        stopwatch.stop();
        final columns = rows.isNotEmpty ? rows.first.keys.toList() : <String>[];
        return QueryExecutionResult(
          success: true,
          kind: kind,
          columns: columns,
          rows: rows,
          duration: stopwatch.elapsed,
          rawSql: sql,
        );
      }

      await db.execute(sql, arguments);
      int? affected;
      if (kind == QueryKind.write) {
        final changes = await db.rawQuery('SELECT changes() AS c');
        affected = Sqflite.firstIntValue(changes);
      }
      stopwatch.stop();
      return QueryExecutionResult(
        success: true,
        kind: kind,
        columns: const [],
        rows: const [],
        affectedRows: affected,
        duration: stopwatch.elapsed,
        rawSql: sql,
      );
    } catch (e) {
      stopwatch.stop();
      return QueryExecutionResult(
        success: false,
        kind: kind,
        columns: const [],
        rows: const [],
        errorMessage: e.toString(),
        duration: stopwatch.elapsed,
        rawSql: sql,
      );
    }
  }
}
