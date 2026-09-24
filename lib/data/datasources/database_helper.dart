import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/attendance_log_model.dart';
import '../models/department_model.dart';
import '../models/employee_model.dart';
import '../models/remote_worker_model.dart';
import '../models/task_completion_sync_model.dart';
import '../models/worker_attendance_model.dart';
import '../models/worker_task_completion_model.dart';
import '../models/worker_task_model.dart';

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
      version: 11,
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
          await db.execute(
            'ALTER TABLE attendance ADD COLUMN dateOfBirth TEXT',
          );
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
        if (oldVersion < 10 && oldVersion >= 7) {
          // Same reasoning as the workers.is_synced migration above, for
          // `POST attendance/check-in` — drives the worker list's
          // check-in/check-out sync button.
          await db.execute(
            'ALTER TABLE worker_attendance ADD COLUMN is_synced INTEGER NOT NULL DEFAULT 0',
          );
        }
        if (oldVersion < 11 && oldVersion >= 7) {
          // `worker_task_completion` picks up `supervisor_id`/`worker_id`
          // and a 'yes'/'no' status (instead of `completed_by` and
          // 'completed'/'pending') to match `POST
          // attendance/worker-task-completion`'s payload, plus `is_synced`.
          // Nothing has shipped against the old shape yet, so — same
          // precedent as the v4/v7 migrations above — existing rows are
          // dropped rather than converted in place.
          await db.execute('DROP TABLE IF EXISTS worker_task_completion');
          await _createWorkerTables(db);
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
  ///
  /// `workers`/`worker_tasks`/`worker_attendance`/`worker_task_completion`
  /// each have their own `offline_worker_id` — a local-only autoincrement
  /// PK, always populated the instant a row is inserted, regardless of
  /// whether it's ever reached the backend. Their old PK columns
  /// (`worker_id`/`worker_task_id`/`attendance_id`/`completion_id`) are now
  /// plain nullable `UNIQUE` columns holding the backend's own id, once
  /// known — null until that record has actually been synced (or, for
  /// `workers`, until an import via `POST attendance/list` tells us). Every
  /// local FK reference and every one of this app's own "id" concepts
  /// (`Employee.id`, `Worker.workerId`, `WorkerTask.workerTaskId`,
  /// `WorkerAttendanceRecord.attendanceId`,
  /// `WorkerTaskCompletion.completionId`, `TaskCompletionSyncRecord.*`) is
  /// backed by `offline_worker_id` — via SQL aliasing in the queries below
  /// wherever a raw query selects specific columns, so the Dart model layer
  /// doesn't need to know which physical column it came from.
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
        offline_worker_id INTEGER PRIMARY KEY AUTOINCREMENT,
        worker_id INTEGER UNIQUE,
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
        offline_worker_id INTEGER PRIMARY KEY AUTOINCREMENT,
        worker_task_id INTEGER UNIQUE,
        worker_id INTEGER NOT NULL,
        task_id INTEGER NOT NULL,
        status TEXT NOT NULL DEFAULT 'active',
        assigned_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        UNIQUE(worker_id, task_id),
        FOREIGN KEY (task_id) REFERENCES tasks(task_id) ON UPDATE CASCADE,
        FOREIGN KEY (worker_id) REFERENCES workers(offline_worker_id) ON UPDATE CASCADE
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS worker_attendance(
        offline_worker_id INTEGER PRIMARY KEY AUTOINCREMENT,
        attendance_id INTEGER UNIQUE,
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
        -- Local-only bookkeeping, not part of the backend's schema: whether
        -- POST attendance/check-in has succeeded for this row yet (see
        -- markWorkerAttendanceSynced) — drives the worker list's sync button.
        is_synced INTEGER NOT NULL DEFAULT 0,
        UNIQUE(worker_id, attendance_date),
        FOREIGN KEY (worker_id) REFERENCES workers(offline_worker_id) ON UPDATE CASCADE
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS worker_task_completion(
        offline_worker_id INTEGER PRIMARY KEY AUTOINCREMENT,
        completion_id INTEGER UNIQUE,
        worker_task_id INTEGER NOT NULL,
        supervisor_id INTEGER NOT NULL,
        attendance_id INTEGER NOT NULL,
        status TEXT NOT NULL DEFAULT 'no',
        worker_id INTEGER,
        completed_at TEXT,
        remarks TEXT,
        created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        -- Local-only bookkeeping, not part of the backend's schema: whether
        -- POST attendance/worker-task-completion has succeeded for this row
        -- yet (see markWorkerTaskCompletionSynced) — drives the worker
        -- list's Sync Task Completion button.
        is_synced INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY (worker_task_id) REFERENCES worker_tasks(offline_worker_id)
          ON UPDATE CASCADE,
        FOREIGN KEY (attendance_id) REFERENCES worker_attendance(offline_worker_id)
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
        // 'pending' — the schema's own default. Nothing in the app gates
        // on this value (no approval screen, no attendance/login check
        // reads it), so there's no need to force 'approved' just to keep
        // the worker usable; leaving it honestly 'pending' also avoids it
        // being mistaken for a real backend approval once this worker is
        // later matched against `POST attendance/list` (see
        // upsertRemoteWorkers) or synced (see WorkerSyncRepository, which
        // doesn't return/update a real status either).
        status: 'pending',
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
      batch.insert('departments', {
        'department_id': department.id,
        'department_name': department.name,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
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
      batch.insert('tasks', {
        'task_id': task.id,
        'department_id': task.departmentId,
        'task_name': task.name,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
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
    final maps = await db.rawQuery(
      '$_workerSelect ORDER BY workers.offline_worker_id DESC',
    );
    return List.generate(maps.length, (i) => Employee.fromMap(maps[i]));
  }

  /// Marks [nationalId]'s worker as synced — call after
  /// `POST attendance/sync-worker` succeeds for them (see
  /// WorkerSyncRepository). [realWorkerId] is the backend's own id from
  /// that response (`{"worker_id": ..., "status": true}`); stored once
  /// known, since a later task-assignment/attendance sync needs it.
  Future<void> markWorkerSynced(String nationalId, {int? realWorkerId}) async {
    final db = await database;
    await db.update(
      'workers',
      {'is_synced': 1, 'worker_id': ?realWorkerId},
      where: 'national_id = ?',
      whereArgs: [nationalId],
    );
  }

  /// The backend's real id for the worker at local id [offlineWorkerId], or
  /// null if they haven't been synced or imported yet — every sync call
  /// that needs a worker_id in its outgoing payload resolves it through
  /// here rather than using the local id.
  Future<int?> getRemoteWorkerId(int offlineWorkerId) async {
    final db = await database;
    final rows = await db.query(
      'workers',
      columns: ['worker_id'],
      where: 'offline_worker_id = ?',
      whereArgs: [offlineWorkerId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['worker_id'] as int?;
  }

  /// The backend's real id for the task assignment at local id
  /// [offlineWorkerTaskId], or null if it hasn't been synced yet.
  Future<int?> getRemoteWorkerTaskId(int offlineWorkerTaskId) async {
    final db = await database;
    final rows = await db.query(
      'worker_tasks',
      columns: ['worker_task_id'],
      where: 'offline_worker_id = ?',
      whereArgs: [offlineWorkerTaskId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['worker_task_id'] as int?;
  }

  /// The backend's real id for the attendance day at local id
  /// [offlineAttendanceId], or null if it hasn't been synced yet.
  Future<int?> getRemoteAttendanceId(int offlineAttendanceId) async {
    final db = await database;
    final rows = await db.query(
      'worker_attendance',
      columns: ['attendance_id'],
      where: 'offline_worker_id = ?',
      whereArgs: [offlineAttendanceId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['attendance_id'] as int?;
  }

  /// Stores the backend's real id for the task assignment at local id
  /// [offlineWorkerTaskId], once `POST attendance/assigntask` returns one.
  Future<void> markWorkerTaskSynced(
    int offlineWorkerTaskId,
    int? realWorkerTaskId,
  ) async {
    if (realWorkerTaskId == null) return;
    final db = await database;
    await db.update(
      'worker_tasks',
      {'worker_task_id': realWorkerTaskId},
      where: 'offline_worker_id = ?',
      whereArgs: [offlineWorkerTaskId],
    );
  }

  /// Reassigns [workerId] to [departmentId] — called from the Assign Task
  /// screen when the supervisor picks a different department than the
  /// worker's current one, so the `workers` table stays in sync with
  /// whichever department their tasks actually ended up assigned from.
  Future<void> updateWorkerDepartment(int workerId, int departmentId) async {
    final db = await database;
    await db.update(
      'workers',
      {'department_id': departmentId},
      where: 'offline_worker_id = ?',
      whereArgs: [workerId],
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
            'worker_id IN (SELECT offline_worker_id FROM workers WHERE national_id = ?)',
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

  // --- Task assignment methods ---

  /// Tasks belonging to [departmentId], for the Assign Task screen — a
  /// worker can only be assigned tasks from their own department.
  Future<List<Task>> getTasksByDepartment(int departmentId) async {
    final db = await database;
    final maps = await db.query(
      'tasks',
      where: 'department_id = ?',
      whereArgs: [departmentId],
      orderBy: 'task_name COLLATE NOCASE',
    );
    return List.generate(maps.length, (i) => Task.fromMap(maps[i]));
  }

  /// Every task currently assigned to [workerId] — for pre-marking them on
  /// the Assign Task screen and for the plain "view assigned tasks" screens.
  Future<List<WorkerTask>> getWorkerTasks(int workerId) async {
    final db = await database;
    final maps = await db.rawQuery(
      '''
      SELECT worker_tasks.offline_worker_id AS worker_task_id, worker_tasks.worker_id,
             tasks.task_id, tasks.task_name, tasks.department_id, worker_tasks.status
      FROM worker_tasks
      JOIN tasks ON tasks.task_id = worker_tasks.task_id
      WHERE worker_tasks.worker_id = ? AND worker_tasks.status = 'active'
      ORDER BY tasks.task_name COLLATE NOCASE
    ''',
      [workerId],
    );
    return List.generate(maps.length, (i) => WorkerTask.fromMap(maps[i]));
  }

  /// Assigns [taskIds] to [workerId]. Duplicates (a task already assigned
  /// to this worker) are silently skipped via the table's own
  /// UNIQUE(worker_id, task_id) — callers don't need to filter first.
  Future<void> assignWorkerTasks(int workerId, List<int> taskIds) async {
    final db = await database;
    final batch = db.batch();
    for (final taskId in taskIds) {
      batch.insert('worker_tasks', {
        'worker_id': workerId,
        'task_id': taskId,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
    await batch.commit(noResult: true);
  }

  /// Removes [taskIds] from [workerId]'s assignments — the Assign Task
  /// screen calls this for tasks the supervisor unselected that were
  /// previously assigned.
  Future<void> unassignWorkerTasks(int workerId, List<int> taskIds) async {
    if (taskIds.isEmpty) return;
    final db = await database;
    final placeholders = List.filled(taskIds.length, '?').join(',');
    await db.delete(
      'worker_tasks',
      where: 'worker_id = ? AND task_id IN ($placeholders)',
      whereArgs: [workerId, ...taskIds],
    );
  }

  // --- Worker attendance (check-in / check-out) methods ---
  //
  // These are additive: they read/write only `worker_attendance` and
  // `worker_task_completion` (previously unused, schema-only tables) and
  // never touch `attendance_logs` or any of the existing employee-login
  // methods above — the existing attendance-marking flow is unchanged.

  /// `worker_attendance.attendance_date` is a DATE column — a plain
  /// yyyy-MM-dd key, not a full timestamp.
  String _todayDateKey() {
    final now = DateTime.now();
    return '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
  }

  /// Records a face-scan event for [workerId] against today's
  /// `worker_attendance` row: the first scan of the day checks them in, the
  /// next one checks them out, and any further scan that same day is left
  /// alone (see [WorkerScanOutcome]). The `UNIQUE(worker_id,
  /// attendance_date)` constraint is exactly why there's only ever one row
  /// per worker per day to update rather than insert again.
  ///
  /// Both `_face_verified` flags are always written `true` here — this is
  /// only ever reached after [FaceScanScreen]'s 1:1 match succeeds (see
  /// MarkAttendanceScreen._showTaskScreenIfNeeded), so an unverified scan
  /// never makes it this far.
  Future<WorkerAttendanceRecord> recordWorkerScan(int workerId) async {
    final db = await database;
    final today = _todayDateKey();
    final existing = await db.query(
      'worker_attendance',
      where: 'worker_id = ? AND attendance_date = ?',
      whereArgs: [workerId, today],
      limit: 1,
    );

    if (existing.isEmpty) {
      final now = DateTime.now().toIso8601String();
      final row = {
        'worker_id': workerId,
        'attendance_date': today,
        'check_in_time': now,
        'check_in_face_verified': 1,
        'status': 'checked_in',
      };
      final id = await db.insert('worker_attendance', row);
      return WorkerAttendanceRecord.fromMap({
        ...row,
        'offline_worker_id': id,
      }, outcome: WorkerScanOutcome.checkedIn);
    }

    final row = existing.first;
    if (row['check_out_time'] == null) {
      final now = DateTime.now().toIso8601String();
      await db.update(
        'worker_attendance',
        {
          'check_out_time': now,
          'check_out_face_verified': 1,
          'status': 'checked_out',
        },
        where: 'offline_worker_id = ?',
        whereArgs: [row['offline_worker_id']],
      );
      return WorkerAttendanceRecord.fromMap({
        ...row,
        'check_out_time': now,
        'check_out_face_verified': 1,
        'status': 'checked_out',
      }, outcome: WorkerScanOutcome.checkedOut);
    }

    return WorkerAttendanceRecord.fromMap(
      row,
      outcome: WorkerScanOutcome.alreadyCheckedOut,
    );
  }

  /// Today's `worker_attendance` row for [workerId], or null if they
  /// haven't been scanned yet today.
  Future<WorkerAttendanceRecord?> getTodayAttendance(int workerId) async {
    final db = await database;
    final rows = await db.query(
      'worker_attendance',
      where: 'worker_id = ? AND attendance_date = ?',
      whereArgs: [workerId, _todayDateKey()],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return WorkerAttendanceRecord.fromMap(rows.first);
  }

  /// Every worker's `worker_attendance` row for today, keyed by worker_id —
  /// used to show each card's check-in/check-out state without one query
  /// per worker.
  Future<Map<int, WorkerAttendanceRecord>> getTodayAttendanceByWorker() async {
    final db = await database;
    final rows = await db.query(
      'worker_attendance',
      where: 'attendance_date = ?',
      whereArgs: [_todayDateKey()],
    );
    return {
      for (final row in rows)
        row['worker_id'] as int: WorkerAttendanceRecord.fromMap(row),
    };
  }

  /// Every `worker_attendance` row for [workerId], newest attendance day
  /// first — the Reports screen's per-worker check-in/check-out history.
  Future<List<WorkerAttendanceRecord>> getAttendanceHistory(
    int workerId,
  ) async {
    final db = await database;
    final rows = await db.query(
      'worker_attendance',
      where: 'worker_id = ?',
      whereArgs: [workerId],
      orderBy: 'attendance_date DESC',
    );
    return List.generate(
      rows.length,
      (i) => WorkerAttendanceRecord.fromMap(rows[i]),
    );
  }

  /// Marks [attendanceId]'s row synced after `POST attendance/check-in`
  /// succeeds. [realAttendanceId] is the backend's own id from that
  /// response (`{"attendance_id": ..., "status": true}`), stored once
  /// known — a later task-completion sync needs it.
  Future<void> markWorkerAttendanceSynced(
    int attendanceId, {
    int? realAttendanceId,
  }) async {
    final db = await database;
    await db.update(
      'worker_attendance',
      {'is_synced': 1, 'attendance_id': ?realAttendanceId},
      where: 'offline_worker_id = ?',
      whereArgs: [attendanceId],
    );
  }

  /// Every task assigned to [workerId], with its completion status for
  /// [attendanceId] — a task with no `worker_task_completion` row yet for
  /// this attendance day defaults to "not completed" via the LEFT JOIN,
  /// rather than being left off the list.
  Future<List<WorkerTaskCompletion>> getTaskCompletions({
    required int workerId,
    required int attendanceId,
  }) async {
    final db = await database;
    final maps = await db.rawQuery(
      '''
      SELECT worker_tasks.offline_worker_id AS worker_task_id, tasks.task_id, tasks.task_name,
             worker_task_completion.offline_worker_id AS completion_id, worker_task_completion.status
      FROM worker_tasks
      JOIN tasks ON tasks.task_id = worker_tasks.task_id
      LEFT JOIN worker_task_completion
        ON worker_task_completion.worker_task_id = worker_tasks.offline_worker_id
        AND worker_task_completion.attendance_id = ?
      WHERE worker_tasks.worker_id = ? AND worker_tasks.status = 'active'
      ORDER BY tasks.task_name COLLATE NOCASE
    ''',
      [attendanceId, workerId],
    );
    return List.generate(
      maps.length,
      (i) => WorkerTaskCompletion.fromMap(maps[i], attendanceId: attendanceId),
    );
  }

  /// Sets [workerTaskId]'s completion status for [attendanceId] — updates
  /// the existing `worker_task_completion` row for this (task, attendance
  /// day) pair if one exists (a re-toggle), otherwise inserts one, so
  /// reopening this screen and changing the status again never creates a
  /// duplicate record. Any change (insert or re-toggle) resets `is_synced`
  /// to 0 — a row already pushed to the backend needs pushing again once
  /// its status changes.
  Future<void> setTaskCompletion({
    required int workerTaskId,
    required int workerId,
    required int attendanceId,
    required bool isCompleted,
  }) async {
    final db = await database;
    final status = isCompleted ? 'yes' : 'no';
    final now = DateTime.now().toIso8601String();
    final existing = await db.query(
      'worker_task_completion',
      where: 'worker_task_id = ? AND attendance_id = ?',
      whereArgs: [workerTaskId, attendanceId],
      limit: 1,
    );
    if (existing.isEmpty) {
      await db.insert('worker_task_completion', {
        'worker_task_id': workerTaskId,
        'worker_id': workerId,
        'attendance_id': attendanceId,
        'supervisor_id': _placeholderCreatedBy,
        'status': status,
        'completed_at': isCompleted ? now : null,
        'is_synced': 0,
      });
    } else {
      await db.update(
        'worker_task_completion',
        {
          'status': status,
          'completed_at': isCompleted ? now : null,
          'is_synced': 0,
        },
        where: 'offline_worker_id = ?',
        whereArgs: [existing.first['offline_worker_id']],
      );
    }
  }

  /// Every `worker_task_completion` row for [workerId] — Yes or No — that
  /// hasn't been pushed to `POST attendance/worker-task-completion` yet
  /// (the payload's own `status` field carries which one it is).
  ///
  /// Joined against `worker_tasks` so `worker_task_id` in the result — and
  /// so in the synced payload — is read straight from `worker_tasks`, the
  /// table it's actually the primary key of, rather than trusted from
  /// `worker_task_completion`'s own FK column.
  Future<List<TaskCompletionSyncRecord>> getUnsyncedTaskCompletions(
    int workerId,
  ) async {
    final db = await database;
    final maps = await db.rawQuery(
      '''
      SELECT worker_task_completion.offline_worker_id AS completion_id,
             worker_tasks.offline_worker_id AS worker_task_id,
             worker_task_completion.attendance_id, worker_task_completion.worker_id,
             worker_task_completion.supervisor_id, worker_task_completion.completed_at,
             worker_task_completion.status
      FROM worker_task_completion
      JOIN worker_tasks
        ON worker_tasks.offline_worker_id = worker_task_completion.worker_task_id
      WHERE worker_task_completion.worker_id = ?
        AND worker_task_completion.is_synced = 0
    ''',
      [workerId],
    );
    return List.generate(
      maps.length,
      (i) => TaskCompletionSyncRecord.fromMap(maps[i]),
    );
  }

  /// Marks [completionId]'s row synced after
  /// `POST attendance/worker-task-completion` succeeds. [realCompletionId]
  /// is the backend's own id from that response (`{"completion_id": ...,
  /// "status": true}`), stored once known.
  Future<void> markWorkerTaskCompletionSynced(
    int completionId, {
    int? realCompletionId,
  }) async {
    final db = await database;
    await db.update(
      'worker_task_completion',
      {'is_synced': 1, 'completion_id': ?realCompletionId},
      where: 'offline_worker_id = ?',
      whereArgs: [completionId],
    );
  }

  // --- Worker import (POST attendance/list) ---

  /// Imports/updates workers fetched from the backend's full roster,
  /// upserted by `national_id` — the reliable cross-system key everything
  /// else in this app already keys off (see WorkerSyncRepository,
  /// EmployeeRepository.findByEmployeeId, deleteEmployee).
  ///
  /// An existing local row's own `offline_worker_id` is untouched either
  /// way (it's never part of `row`) — `worker_tasks`/`worker_attendance`
  /// rows already reference it by FK, and overwriting it would orphan
  /// them. `worker_id` (the backend's real id) is safe to set/overwrite
  /// freely on every import, since nothing local keys off it.
  Future<void> upsertRemoteWorkers(List<RemoteWorkerRecord> workers) async {
    final db = await database;
    await db.transaction((txn) async {
      // Departments first, the same way replaceDepartments already does —
      // a worker's department_id FK needs its department row to exist.
      final departmentNamesById = <int, String>{
        for (final worker in workers)
          worker.departmentId: worker.departmentName,
      };
      for (final entry in departmentNamesById.entries) {
        await txn.insert('departments', {
          'department_id': entry.key,
          'department_name': entry.value,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }

      for (final worker in workers) {
        final row = {
          // The backend's real id — safe to store now that `worker_id`
          // is purely bookkeeping (see the class doc comment above
          // _createWorkerTables); nothing local keys off it.
          'worker_id': worker.workerId,
          'full_name': worker.fullName,
          'birth_date': worker.birthDate ?? '',
          'gender': worker.gender,
          'national_id_image': worker.nationalIdImage,
          'phone_number': worker.phoneNumber,
          'department_id': worker.departmentId,
          'address': worker.address,
          'face_detection': worker.faceDetection,
          'status': worker.status,
          'rejection_reason': worker.rejectionReason,
          'created_by': worker.createdBy ?? _placeholderCreatedBy,
          'approved_by': worker.approvedBy,
          'approved_at': worker.approvedAt,
          'created_date':
              worker.createdDate ?? DateTime.now().toIso8601String(),
          'modified_date': worker.modifiedDate,
          // This row only exists locally because the server already has
          // it, so there's nothing left to push.
          'is_synced': 1,
        };

        final existing = await txn.query(
          'workers',
          columns: ['offline_worker_id'],
          where: 'national_id = ?',
          whereArgs: [worker.nationalId],
          limit: 1,
        );

        if (existing.isEmpty) {
          await txn.insert('workers', {
            ...row,
            'national_id': worker.nationalId,
          });
        } else {
          await txn.update(
            'workers',
            row,
            where: 'offline_worker_id = ?',
            whereArgs: [existing.first['offline_worker_id']],
          );
        }
      }
    });
  }
}
