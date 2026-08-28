import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'employee_model.dart';
import 'attendance_log_model.dart';

class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  factory DatabaseHelper() => _instance;
  DatabaseHelper._internal();

  static Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final path = join(await getDatabasesPath(), 'attendance.db');
    return openDatabase(
      path,
      version: 4,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE attendance(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            number TEXT NOT NULL,
            employeeId TEXT NOT NULL,
            attendanceTime TEXT NOT NULL,
            faceVerified INTEGER NOT NULL,
            faceEmbedding TEXT
          )
        ''');
        await db.execute('''
          CREATE TABLE attendance_logs(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            employeeId TEXT NOT NULL,
            employeeName TEXT NOT NULL,
            loginTime TEXT NOT NULL
          )
        ''');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS attendance_logs(
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              employeeId TEXT NOT NULL,
              employeeName TEXT NOT NULL,
              loginTime TEXT NOT NULL
            )
          ''');
        }
        if (oldVersion < 3) {
          await db.execute(
            'ALTER TABLE attendance ADD COLUMN faceEmbedding TEXT',
          );
        }
        if (oldVersion < 4) {
          // faceEmbedding now stores a list of embeddings (one per enrolled
          // pose) instead of a single embedding — old rows are in the
          // previous flat-list format and can't be reinterpreted, so
          // existing enrollments need to be recaptured under the new
          // multi-pose flow.
          await db.execute('DELETE FROM attendance');
        }
      },
    );
  }

  // --- Employee (Create Attendance form) methods ---

  Future<int> insertAttendance(Employee employee) async {
    final db = await database;
    return db.insert('attendance', employee.toMap());
  }

  Future<List<Employee>> getAllAttendance() async {
    final db = await database;
    final maps = await db.query('attendance', orderBy: 'id DESC');
    return List.generate(maps.length, (i) => Employee.fromMap(maps[i]));
  }

  Future<List<Employee>> getUniqueEmployees() async {
    final db = await database;
    final maps = await db.rawQuery(
      'SELECT * FROM attendance GROUP BY employeeId ORDER BY name ASC',
    );
    return List.generate(maps.length, (i) => Employee.fromMap(maps[i]));
  }

  /// Looks up a single employee by their employeeId, for 1:1 login
  /// verification. Returns the most recent enrollment record for that ID.
  Future<Employee?> getEmployeeByEmployeeId(String employeeId) async {
    final db = await database;
    final maps = await db.query(
      'attendance',
      where: 'employeeId = ?',
      whereArgs: [employeeId],
      orderBy: 'id DESC',
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return Employee.fromMap(maps.first);
  }

  // --- Attendance log (Login / face scan) methods ---

  Future<int> insertAttendanceLog(AttendanceLog log) async {
    final db = await database;
    return db.insert('attendance_logs', log.toMap());
  }

  Future<List<AttendanceLog>> getAllAttendanceLogs() async {
    final db = await database;
    final maps = await db.query('attendance_logs', orderBy: 'loginTime DESC');
    return List.generate(maps.length, (i) => AttendanceLog.fromMap(maps[i]));
  }
}
