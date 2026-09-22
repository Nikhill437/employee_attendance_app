import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/attendance_log_model.dart';
import '../models/department_model.dart';
import '../models/employee_model.dart';

class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  factory DatabaseHelper() => _instance;
  DatabaseHelper._internal();

  static Database? _database;

  /// Until the app has real admin/supervisor accounts, every local
  /// enrollment is attributed to this fixed id — SupervisorAuthRepository is
  /// a single hardcoded credential today, not a table with ids. Replace this
  /// once admin accounts (and their ids) exist for real.
  static const int _placeholderCreatedBy = 1;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final path = join(await getDatabasesPath(), 'attendance.db');
    return openDatabase(
      path,
      version: 9,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE attendance_logs(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            employeeId TEXT NOT NULL,
            employeeName TEXT NOT NULL,
            loginTime TEXT NOT NULL
          )
        ''');
        await _createWorkerTables(db);
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
        if (oldVersion < 5) {
          // The enrollment form now collects these directly; existing rows
          // get them as null and Employee.fromMap falls back to neutral
          // defaults for gender/payType rather than treating this as a
          // breaking change requiring re-enrollment.
          await db.execute('ALTER TABLE attendance ADD COLUMN dateOfBirth TEXT');
          await db.execute('ALTER TABLE attendance ADD COLUMN gender TEXT');
          await db.execute('ALTER TABLE attendance ADD COLUMN address TEXT');
          await db.execute('ALTER TABLE attendance ADD COLUMN payType TEXT');
        }
        if (oldVersion < 6) {
          await db.execute('ALTER TABLE attendance ADD COLUMN department TEXT');
        }
        if (oldVersion < 7) {
          // Enrolled-worker storage moves from `attendance` to `workers`
          // (mirroring the backend's schema) in this version — same
          // precedent as the v4 migration: existing local enrollments are
          // not carried over, re-enroll after updating.
          await _createWorkerTables(db);
          await db.execute('DROP TABLE IF EXISTS attendance');
        }
        if (oldVersion < 8) {
          // _createWorkerTables uses CREATE TABLE IF NOT EXISTS throughout,
          // so re-running it here is a no-op for the tables an install
          // already has and only adds the two new ones.
          await _createWorkerTables(db);
        }
        if (oldVersion < 9 && oldVersion >= 7) {
          // Only needed for installs that already have a `workers` table
          // without this column — an oldVersion < 7 upgrade already gets it
          // for free from the CREATE TABLE in _createWorkerTables above.
          await db.execute(
            'ALTER TABLE workers ADD COLUMN is_synced INTEGER NOT NULL DEFAULT 0',
          );
        }
      },
    );
  }

  /// `departments` / `tasks` / `workers` / `worker_tasks` /
  /// `worker_attendance` / `worker_task_completion` mirror the backend's
  /// MySQL schema as closely as SQLite allows: ENUM columns become plain
  /// TEXT (no CHECK constraint, to avoid brittle casing failures),
  /// AUTO_INCREMENT/BIGINT become INTEGER PRIMARY KEY AUTOINCREMENT, the
  /// backend's `ab_admin` (admin users) FK on created_by/modified_by/
  /// check_in_by/check_out_by/completed_by isn't mirrored locally (no local
  /// admin-accounts table yet), and MySQL's `ON UPDATE CURRENT_TIMESTAMP`
  /// isn't reproduced (SQLite has no equivalent column default; would need
  /// an UPDATE trigger, not added since nothing writes to these two tables
  /// yet — schema only, same as `tasks`/`worker_tasks` were before them).
  Future<void> _createWorkerTables(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS departments(
        department_id INTEGER PRIMARY KEY AUTOINCREMENT,
        department_name TEXT NOT NULL COLLATE NOCASE UNIQUE,
        status TEXT NOT NULL DEFAULT 'active',
        created_date TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        modified_date TEXT,
        modified_by INTEGER,
        created_by INTEGER
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS tasks(
        task_id INTEGER PRIMARY KEY AUTOINCREMENT,
        department_id INTEGER NOT NULL,
        task_name TEXT NOT NULL,
        status TEXT DEFAULT 'active',
        created_date TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        modified_date TEXT,
        modified_by INTEGER,
        created_by INTEGER,
        UNIQUE(department_id, task_name),
        FOREIGN KEY (department_id) REFERENCES departments(department_id)
          ON UPDATE CASCADE
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS workers(
        worker_id INTEGER PRIMARY KEY AUTOINCREMENT,
        full_name TEXT NOT NULL,
        birth_date TEXT NOT NULL,
        gender TEXT NOT NULL,
        national_id TEXT NOT NULL UNIQUE,
        national_id_image TEXT,
        phone_number TEXT,
        department_id INTEGER NOT NULL,
        address TEXT,
        enrollment_type TEXT,
        face_detection TEXT,
        status TEXT NOT NULL DEFAULT 'pending',
        rejection_reason TEXT,
        created_by INTEGER NOT NULL,
        approved_by INTEGER,
        approved_at TEXT,
        created_date TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        modified_date TEXT,
        server_time TEXT DEFAULT CURRENT_TIMESTAMP,
        -- Local-only bookkeeping, not part of the backend's schema: whether
        -- POST attendance/sync-worker has succeeded for this row yet (see
        -- markWorkerSynced) — drives the worker list's "Synced" pill.
        is_synced INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY (department_id) REFERENCES departments(department_id)
          ON UPDATE CASCADE
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS worker_tasks(
        worker_task_id INTEGER PRIMARY KEY AUTOINCREMENT,
        worker_id INTEGER NOT NULL,
        task_id INTEGER NOT NULL,
        status TEXT NOT NULL DEFAULT 'active',
        assigned_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        UNIQUE(worker_id, task_id),
        FOREIGN KEY (task_id) REFERENCES tasks(task_id) ON UPDATE CASCADE,
        FOREIGN KEY (worker_id) REFERENCES workers(worker_id) ON UPDATE CASCADE
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS worker_attendance(
        attendance_id INTEGER PRIMARY KEY AUTOINCREMENT,
        worker_id INTEGER NOT NULL,
        attendance_date TEXT NOT NULL,
        check_in_time TEXT,
        check_out_time TEXT,
        check_in_by INTEGER,
        check_out_by INTEGER,
        check_in_face_verified INTEGER NOT NULL DEFAULT 0,
        check_out_face_verified INTEGER NOT NULL DEFAULT 0,
        status TEXT NOT NULL DEFAULT 'checked_in',
        created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        UNIQUE(worker_id, attendance_date),
        FOREIGN KEY (worker_id) REFERENCES workers(worker_id) ON UPDATE CASCADE
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS worker_task_completion(
        completion_id INTEGER PRIMARY KEY AUTOINCREMENT,
        worker_task_id INTEGER NOT NULL,
        attendance_id INTEGER NOT NULL,
        status TEXT NOT NULL DEFAULT 'pending',
        completed_by INTEGER,
        completed_at TEXT,
        remarks TEXT,
        created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY (worker_task_id) REFERENCES worker_tasks(worker_task_id)
          ON UPDATE CASCADE,
        FOREIGN KEY (attendance_id) REFERENCES worker_attendance(attendance_id)
          ON UPDATE CASCADE
      )
    ''');
  }

  // --- Worker (enrollment) methods ---

  static const String _workerSelect = '''
    SELECT workers.*, departments.department_name AS department_name
    FROM workers
    LEFT JOIN departments ON departments.department_id = workers.department_id
  ''';

  /// Inserts [employee] into `workers`. Its `departmentId` must already be
  /// set — the enrollment form's department dropdown (populated from the
  /// local `departments` cache, see [getDepartments]) is what guarantees
  /// that, not this method.
  Future<int> insertWorkerRecord(Employee employee) async {
    final db = await database;
    return db.insert(
      'workers',
      employee.toWorkerRow(
        createdBy: _placeholderCreatedBy,
        // No approval screen exists yet, so a worker is usable right after
        // enrollment rather than stuck at the schema's default 'pending'
        // state.
        status: 'approved',
      ),
    );
  }

  /// Replaces the local `departments` cache with the backend's current
  /// list (see LookupRepository.syncFromRemote, called after supervisor
  /// login) — rows are upserted by the backend's own `department_id`, so
  /// `workers.department_id` values stay valid across a re-sync.
  Future<void> replaceDepartments(List<Department> departments) async {
    final db = await database;
    final batch = db.batch();
    for (final department in departments) {
      batch.insert(
        'departments',
        {'department_id': department.id, 'department_name': department.name},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  /// Replaces the local `tasks` cache the same way [replaceDepartments]
  /// does. Call after `replaceDepartments` in the same sync, since each
  /// task's `department_id` FK needs its department row to already exist.
  Future<void> replaceTasks(List<Task> tasks) async {
    final db = await database;
    final batch = db.batch();
    for (final task in tasks) {
      batch.insert(
        'tasks',
        {
          'task_id': task.id,
          'department_id': task.departmentId,
          'task_name': task.name,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  /// The cached departments, alphabetical — for the enrollment form's
  /// dropdown.
  Future<List<Department>> getDepartments() async {
    final db = await database;
    final maps = await db.query(
      'departments',
      orderBy: 'department_name COLLATE NOCASE',
    );
    return List.generate(maps.length, (i) => Department.fromMap(maps[i]));
  }

  /// Every worker, newest enrollment first. `national_id` is unique on the
  /// table, so — unlike the old `attendance` table — there's no re-enrolled
  /// history to dedupe.
  Future<List<Employee>> getAllWorkers() async {
    final db = await database;
    final maps = await db.rawQuery('$_workerSelect ORDER BY workers.worker_id DESC');
    return List.generate(maps.length, (i) => Employee.fromMap(maps[i]));
  }

  /// Marks [nationalId]'s worker as synced — call after
  /// `POST attendance/sync-worker` succeeds for them (see
  /// WorkerSyncRepository).
  Future<void> markWorkerSynced(String nationalId) async {
    final db = await database;
    await db.update(
      'workers',
      {'is_synced': 1},
      where: 'national_id = ?',
      whereArgs: [nationalId],
    );
  }

  /// Looks up a single worker by their National ID, for 1:1 login
  /// verification.
  Future<Employee?> getWorkerByNationalId(String nationalId) async {
    final db = await database;
    final maps = await db.rawQuery(
      '$_workerSelect WHERE workers.national_id = ? LIMIT 1',
      [nationalId],
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

  /// Removes the worker (and their task assignments) and attendance log for
  /// [employeeId] (their National ID) — a full removal (not a soft-delete),
  /// so a deleted worker also drops out of attendance history and summary
  /// counts rather than leaving orphaned logs behind.
  Future<void> deleteEmployee(String employeeId) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete(
        'worker_tasks',
        where:
            'worker_id IN (SELECT worker_id FROM workers WHERE national_id = ?)',
        whereArgs: [employeeId],
      );
      await txn.delete(
        'workers',
        where: 'national_id = ?',
        whereArgs: [employeeId],
      );
      await txn.delete(
        'attendance_logs',
        where: 'employeeId = ?',
        whereArgs: [employeeId],
      );
    });
  }
}
