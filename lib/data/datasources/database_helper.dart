import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../../core/utils/app_time.dart';
import '../models/attendance_log_model.dart';
import '../models/department_model.dart';
import '../models/employee_model.dart';
import '../models/remote_worker_model.dart';
import '../models/remote_worker_task_model.dart';
import '../models/worker_attendance_model.dart';
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
      version: 19,
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
          // `worker_task_completion` used to be recreated here with its
          // 'yes'/'no' status shape; the table (and the whole task-status
          // review feature) has since been removed from the app, so this
          // step now just drops it if a pre-v11 install still has the old
          // one lying around.
          await db.execute('DROP TABLE IF EXISTS worker_task_completion');
        }
        if (oldVersion < 12 && oldVersion >= 7) {
          // `workers.employee_id` — the backend's employee id, distinct
          // from `worker_id` and `national_id` — is what the attendance
          // login flow now matches on instead of national_id (see
          // AuthRepository/DatabaseHelper.getWorkerByEmployeeId). SQLite's
          // ALTER TABLE can't add a UNIQUE column, unlike the CREATE TABLE
          // in _createWorkerTables a fresh install gets it from; nothing
          // here depends on that constraint being DB-enforced, so a plain
          // nullable column is fine for an upgrade.
          await db.execute(
            'ALTER TABLE workers ADD COLUMN employee_id INTEGER',
          );
        }
        if (oldVersion < 13 && oldVersion >= 7) {
          // See the `synced_at` column doc comment in _createWorkerTables.
          await db.execute('ALTER TABLE workers ADD COLUMN synced_at TEXT');
        }
        if (oldVersion < 14 && oldVersion >= 7) {
          // See the `isdefault`/`assignment_type` column doc comments in
          // _createWorkerTables.
          await db.execute(
            "ALTER TABLE tasks ADD COLUMN isdefault TEXT NOT NULL DEFAULT 'no'",
          );
          await db.execute(
            "ALTER TABLE worker_tasks ADD COLUMN assignment_type TEXT NOT NULL DEFAULT 'default'",
          );
        }
        // The old oldVersion < 15 step added worker_task_completion's
        // numeric_value/image_path columns; that table has since been
        // removed entirely (see the oldVersion < 11 step above), so there
        // is nothing left for a v15 upgrade to do.
        if (oldVersion < 16 && oldVersion >= 7) {
          // See the `server_time`/`target`/`rate`/`overtime`/`note`/
          // `completed_target`/`task_id`/`task_status` column doc comments
          // in _createWorkerTables.
          await db.execute(
            'ALTER TABLE departments ADD COLUMN server_time TEXT DEFAULT CURRENT_TIMESTAMP',
          );
          await db.execute(
            'ALTER TABLE tasks ADD COLUMN server_time TEXT DEFAULT CURRENT_TIMESTAMP',
          );
          await db.execute('ALTER TABLE tasks ADD COLUMN target INTEGER');
          await db.execute('ALTER TABLE tasks ADD COLUMN rate INTEGER');
          await db.execute('ALTER TABLE tasks ADD COLUMN overtime INTEGER');
          await db.execute('ALTER TABLE workers ADD COLUMN task_id INTEGER');
          await db.execute(
            'ALTER TABLE worker_tasks ADD COLUMN server_time TEXT DEFAULT CURRENT_TIMESTAMP',
          );
          await db.execute('ALTER TABLE worker_tasks ADD COLUMN note TEXT');
          await db.execute(
            'ALTER TABLE worker_tasks ADD COLUMN overtime INTEGER',
          );
          await db.execute(
            'ALTER TABLE worker_tasks ADD COLUMN completed_target INTEGER',
          );
          await db.execute(
            "ALTER TABLE worker_tasks ADD COLUMN task_status TEXT NOT NULL DEFAULT 'pending'",
          );
        }
        if (oldVersion < 17 && oldVersion >= 7) {
          // See the `employee_target`/`work_photo` column doc comments on
          // WorkerTask — added to _createWorkerTables after the v16 step
          // above had already shipped, so they need their own step rather
          // than folding into it.
          await db.execute(
            'ALTER TABLE worker_tasks ADD COLUMN work_photo VARCHAR(255)',
          );
          await db.execute(
            'ALTER TABLE worker_tasks ADD COLUMN employee_target INTEGER',
          );
        }
        if (oldVersion < 18 && oldVersion >= 7) {
          // `shift_based_type` was added to _createWorkerTables' CREATE
          // TABLE (for the enrollment form's new Shift Based enrollment
          // type) without ever getting its own upgrade step — an install
          // that reached v17 via onUpgrade rather than a fresh onCreate
          // would otherwise be missing this column entirely.
          await db.execute(
            'ALTER TABLE workers ADD COLUMN shift_based_type TEXT',
          );
        }
        if (oldVersion < 19 && oldVersion >= 7) {
          // worker_tasks' daily data (employee_target/work_photo/
          // completed_target/note/task_status/overtime) is now scoped per
          // [task_date] instead of being one standing value per (worker_id,
          // task_id) — see the column's doc comment in _createWorkerTables.
          // SQLite can't alter a UNIQUE constraint in place, so the table
          // is rebuilt: renamed aside, recreated fresh by
          // _createWorkerTables (CREATE TABLE IF NOT EXISTS, so every
          // other table here is a no-op), its rows copied back in with
          // task_date backfilled from each row's own assigned_at date —
          // the closest available stand-in for "which day this was", since
          // the column never existed before now — then the old copy is
          // dropped.
          await db.execute(
            'ALTER TABLE worker_tasks RENAME TO worker_tasks_v18',
          );
          await _createWorkerTables(db);
          await db.execute('''
            INSERT INTO worker_tasks (
              offline_worker_id, worker_task_id, worker_id, attendance_id,
              task_id, target, status, assigned_at, created_at, updated_at,
              assignment_type, note, work_photo, overtime, employee_target,
              completed_target, task_status, server_time, task_date
            )
            SELECT
              offline_worker_id, worker_task_id, worker_id, attendance_id,
              task_id, target, status, assigned_at, created_at, updated_at,
              assignment_type, note, work_photo, overtime, employee_target,
              completed_target, task_status, server_time,
              substr(assigned_at, 1, 10)
            FROM worker_tasks_v18
          ''');
          await db.execute('DROP TABLE worker_tasks_v18');
        }
      },
    );
  }

  /// `departments` / `tasks` / `workers` / `worker_tasks` /
  /// `worker_attendance` mirror the backend's
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
  /// `workers`/`worker_tasks`/`worker_attendance`
  /// each have their own `offline_worker_id` — a local-only autoincrement
  /// PK, always populated the instant a row is inserted, regardless of
  /// whether it's ever reached the backend. Their old PK columns
  /// (`worker_id`/`worker_task_id`/`attendance_id`) are now
  /// plain nullable `UNIQUE` columns holding the backend's own id, once
  /// known — null until that record has actually been synced (or, for
  /// `workers`, until an import via `POST attendance/list` tells us). Every
  /// local FK reference and every one of this app's own "id" concepts
  /// (`Employee.id`, `Worker.workerId`, `WorkerTask.workerTaskId`,
  /// `WorkerAttendanceRecord.attendanceId`) is
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
        created_by INTEGER,
        server_time TEXT DEFAULT CURRENT_TIMESTAMP
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
        -- 'yes'/'no' from the backend's own `POST attendance/list_task`
        -- response (see replaceTasks) — whether this task is one every
        -- worker in its department gets by default, vs one a supervisor
        -- assigns as needed. Drives the Assign Task screen's default
        -- pre-selection for a newly-picked task's assignment_type.
        isdefault TEXT NOT NULL DEFAULT 'no',
        -- A per-task daily quantity goal, hourly/piece rate, and overtime
        -- allowance — all backend-defined, mirrored read-only.
        target INTEGER,
        rate INTEGER,
        overtime INTEGER,
        server_time TEXT DEFAULT CURRENT_TIMESTAMP,
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
        employee_id INTEGER UNIQUE,
        shift_based_type TEXT,
        -- The backend's own task id — set on some worker records
        -- independent of the worker_tasks assignment table; not FK'd
        -- locally since nothing here depends on it being enforced.
        task_id INTEGER,
        created_date TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        modified_date TEXT,
        server_time TEXT DEFAULT CURRENT_TIMESTAMP,
        -- Local-only bookkeeping, not part of the backend's schema: whether
        -- POST attendance/sync-worker has succeeded for this row yet (see
        -- markWorkerSynced) — drives the worker list's "Synced" pill. Set
        -- back to 0 whenever check-in/out or a task assignment changes
        -- this worker's data (see markWorkerUnsynced), so the pill flags
        -- that there's something new to push.
        is_synced INTEGER NOT NULL DEFAULT 0,
        -- When [is_synced] was last set true — null until the first
        -- successful sync. Kept even after a later edit sets is_synced
        -- back to 0, so the worker list can still show "last synced at".
        synced_at TEXT,
        FOREIGN KEY (department_id) REFERENCES departments(department_id)
          ON UPDATE CASCADE
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS worker_tasks(
        offline_worker_id INTEGER PRIMARY KEY AUTOINCREMENT,
        worker_task_id INTEGER UNIQUE,
        worker_id INTEGER NOT NULL,
        attendance_id INTEGER,
        task_id INTEGER NOT NULL,
        target INTEGER,
        status TEXT NOT NULL DEFAULT 'active',
        assigned_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        -- 'default' (available to the worker every day) or 'temporary' —
        -- vestigial today (see assignWorkerTask, which only ever writes
        -- 'default' now); which calendar day this row belongs to is
        -- [task_date]'s job, not this column's.
        assignment_type TEXT NOT NULL DEFAULT 'default',
        -- Free-form text the supervisor attaches to this assignment — see
        -- assign_task_screen.dart's Note field.
        note TEXT,
        -- This assignment's own overtime allowance and progress toward
        -- [target] — distinct from the task catalog's own [Task]-level
        -- target/rate/overtime, which describe the task in general.
        work_photo VARCHAR(255),
        overtime INTEGER,
        employee_target INTEGER,
        completed_target INTEGER,
        -- 'pending'/'approved'/'rejected' — the backend's ENUM for this
        -- assignment's own approval state (plain TEXT locally, no CHECK
        -- constraint — see the schema doc comment above for why).
        task_status TEXT NOT NULL DEFAULT 'pending',
        server_time TEXT DEFAULT CURRENT_TIMESTAMP,
        -- The calendar day (supervisor's own timezone — see AppTime, same
        -- as worker_attendance.attendance_date) this row's *daily* record
        -- belongs to: [employee_target]/[work_photo]/[completed_target]/
        -- [note]/[task_status]/[overtime] are all scoped to this one day,
        -- never carried over or overwritten across days. The task
        -- ASSIGNMENT itself (which task_id a worker is on) stays a
        -- standing fact that spans every day's row — see
        -- DatabaseHelper.getWorkerTasks, which creates each new day's row
        -- automatically (carrying the task_id forward, but with these
        -- fields blank) the first time it's read on a day with no row yet.
        task_date TEXT NOT NULL,
        UNIQUE(worker_id, task_id, task_date),
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
        'isdefault': task.isDefault ? 'yes' : 'no',
        'target': task.target,
        'rate': task.rate,
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
      {
        'is_synced': 1,
        'worker_id': ?realWorkerId,
        'synced_at': AppTime.nowInUserZone().toIso8601String(),
      },
      where: 'national_id = ?',
      whereArgs: [nationalId],
    );
  }

  /// Marks the worker at local id [offlineWorkerId] as synced — same as
  /// [markWorkerSynced] but keyed by the local id already at hand (see
  /// AttendanceSubmissionRepository.submitAttendance) rather than by
  /// National ID.
  Future<void> markWorkerSyncedById(int offlineWorkerId) async {
    final db = await database;
    await db.update(
      'workers',
      {'is_synced': 1, 'synced_at': AppTime.nowInUserZone().toIso8601String()},
      where: 'offline_worker_id = ?',
      whereArgs: [offlineWorkerId],
    );
  }

  /// Flags [offlineWorkerId] as needing a re-sync — call whenever
  /// something the backend cares about for this worker changes locally
  /// (a check-in/out, or a task assignment), so the worker list's "Synced"
  /// pill flips back to "Not synced" until the supervisor pushes again.
  /// [synced_at] (the last successful sync time) is left untouched, so the
  /// worker list can still show when that was.
  Future<void> markWorkerUnsynced(int offlineWorkerId) async {
    final db = await database;
    await db.update(
      'workers',
      {'is_synced': 0},
      where: 'offline_worker_id = ?',
      whereArgs: [offlineWorkerId],
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
  /// [offlineWorkerTaskId], once `POST attendance/assigntask` (or the
  /// sync-data endpoint — see AttendanceSubmissionRepository.
  /// submitAllUnsyncedAttendance) returns one. [realAttendanceId], when
  /// given, is also stored in this same row's own `attendance_id` column —
  /// the sync-data response ties a synced assignment back to the
  /// attendance day it was synced alongside.
  Future<void> markWorkerTaskSynced(
    int offlineWorkerTaskId,
    int? realWorkerTaskId, {
    int? realAttendanceId,
  }) async {
    if (realWorkerTaskId == null && realAttendanceId == null) return;
    final db = await database;
    await db.update(
      'worker_tasks',
      {'worker_task_id': ?realWorkerTaskId, 'attendance_id': ?realAttendanceId},
      where: 'offline_worker_id = ?',
      whereArgs: [offlineWorkerTaskId],
    );
  }

  /// Reassigns [workerId] to [departmentId] — called from the Assign Task
  /// screen when the supervisor picks a different department than the
  /// worker's current one, and from the Edit Worker flow
  /// (EnrollmentFormViewModel.saveDepartmentOnly), so the `workers` table
  /// stays in sync with whichever department their tasks/profile actually
  /// came from. Also flags the worker as needing a re-sync (see
  /// markWorkerUnsynced) — the backend needs to hear about this change too.
  Future<void> updateWorkerDepartment(int workerId, int departmentId) async {
    final db = await database;
    await db.update(
      'workers',
      {'department_id': departmentId},
      where: 'offline_worker_id = ?',
      whereArgs: [workerId],
    );
    await markWorkerUnsynced(workerId);
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

  /// Looks up a single worker by their `employee_id` (the backend's id,
  /// stored via [upsertRemoteWorkers]) — what the attendance login flow
  /// matches on instead of national_id (see AuthRepository). Unlike
  /// national_id, `employee_id` is only ever populated once a worker has
  /// been imported/synced, so a worker enrolled purely offline and never
  /// synced won't be found this way yet.
  Future<Employee?> getWorkerByEmployeeId(int employeeId) async {
    final db = await database;
    final maps = await db.rawQuery(
      '$_workerSelect WHERE workers.employee_id = ? LIMIT 1',
      [employeeId],
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

  /// Every task currently assigned to [workerId] for *today* specifically —
  /// for pre-marking them on the Assign Task screen and for the plain
  /// "view assigned tasks" screens. A worker only ever has one active
  /// assignment at a time (see [assignWorkerTask]), so in practice this
  /// returns at most one row. If that standing assignment doesn't have a
  /// row for today yet (the first read of a new day), one is created
  /// first — carrying the same task_id forward but with every daily field
  /// blank — so a continuing assignment never shows a previous day's
  /// already-completed data (see the `task_date` column doc comment in
  /// _createWorkerTables).
  Future<List<WorkerTask>> getWorkerTasks(int workerId) async {
    final db = await database;
    await _ensureTodaysWorkerTaskRow(db, workerId);
    final maps = await db.rawQuery(
      '''
      SELECT worker_tasks.offline_worker_id AS worker_task_id, worker_tasks.worker_id,
             tasks.task_id, tasks.task_name, tasks.department_id, worker_tasks.status,
             worker_tasks.assignment_type, worker_tasks.employee_target,
             worker_tasks.work_photo, worker_tasks.completed_target, worker_tasks.note,
             worker_tasks.task_status, worker_tasks.task_date,
             worker_tasks.worker_task_id AS real_worker_task_id,
             tasks.target AS task_target, tasks.rate AS task_rate
      FROM worker_tasks
      JOIN tasks ON tasks.task_id = worker_tasks.task_id
      WHERE worker_tasks.worker_id = ? AND worker_tasks.status = 'active'
        AND worker_tasks.task_date = ?
      ORDER BY tasks.task_name COLLATE NOCASE
    ''',
      [workerId, _todayDateKey()],
    );
    return List.generate(maps.length, (i) => WorkerTask.fromMap(maps[i]));
  }

  /// Creates today's `worker_tasks` row for [workerId]'s current standing
  /// assignment (the most recent active row, any day) if one doesn't exist
  /// yet — carrying the task_id/assignment_type forward but leaving every
  /// daily field (employee_target/work_photo/completed_target/note/
  /// task_status/overtime) unset and `worker_task_id` null, so it reads as
  /// a fresh blank record and is picked up by [getUnsyncedWorkerTasks] like
  /// any other not-yet-synced day. A no-op if today's row already exists,
  /// or if the worker has no active assignment at all yet.
  Future<void> _ensureTodaysWorkerTaskRow(Database db, int workerId) async {
    final today = _todayDateKey();
    final todays = await db.query(
      'worker_tasks',
      where: 'worker_id = ? AND status = ? AND task_date = ?',
      whereArgs: [workerId, 'active', today],
      limit: 1,
    );
    if (todays.isNotEmpty) return;

    final latestActive = await db.query(
      'worker_tasks',
      where: 'worker_id = ? AND status = ?',
      whereArgs: [workerId, 'active'],
      orderBy: 'task_date DESC',
      limit: 1,
    );
    if (latestActive.isEmpty) return;

    final previous = latestActive.first;
    final now = AppTime.nowInUserZone().toIso8601String();
    await db.insert('worker_tasks', {
      'worker_id': workerId,
      'task_id': previous['task_id'],
      'assignment_type': previous['assignment_type'],
      'status': 'active',
      'assigned_at': now,
      'created_at': now,
      'updated_at': now,
      'task_date': today,
    });
  }

  /// [workerId]'s active task-assignment days that haven't reached the
  /// backend yet (`worker_tasks.worker_task_id IS NULL`) — one row per
  /// unsynced `task_date`, oldest first, now that each day gets its own
  /// row (see the `task_date` column doc comment). See
  /// AttendanceSubmissionRepository.submitAttendance/
  /// submitAllUnsyncedAttendance, which push these alongside attendance
  /// data rather than resubmitting every assignment on every call the way
  /// [TaskSyncRepository] does. Includes the supervisor's review fields
  /// (completed_target/work_photo/note/task_status/overtime) so the latter
  /// can send them along with the first-time assignment sync.
  Future<List<WorkerTask>> getUnsyncedWorkerTasks(int workerId) async {
    final db = await database;
    final maps = await db.rawQuery(
      '''
      SELECT worker_tasks.offline_worker_id AS worker_task_id, worker_tasks.worker_id,
             tasks.task_id, tasks.task_name, tasks.department_id, worker_tasks.status,
             worker_tasks.assignment_type, worker_tasks.completed_target,
             worker_tasks.work_photo, worker_tasks.note, worker_tasks.task_status,
             worker_tasks.overtime, worker_tasks.created_at, worker_tasks.task_date
      FROM worker_tasks
      JOIN tasks ON tasks.task_id = worker_tasks.task_id
      WHERE worker_tasks.worker_id = ? AND worker_tasks.status = 'active'
        AND worker_tasks.worker_task_id IS NULL
      ORDER BY worker_tasks.task_date ASC, tasks.task_name COLLATE NOCASE
    ''',
      [workerId],
    );
    return List.generate(maps.length, (i) => WorkerTask.fromMap(maps[i]));
  }

  /// Assigns [taskIds] to [workerId]. A task already assigned *today* is
  /// silently skipped via the table's own UNIQUE(worker_id, task_id,
  /// task_date) — callers don't need to filter first. Currently unused by
  /// any screen (the checklist-style multi-task assignment this backed has
  /// since been replaced by [assignWorkerTask]'s one-active-task model).
  Future<void> assignWorkerTasks(int workerId, List<int> taskIds) async {
    final db = await database;
    // Passed explicitly rather than left to the column's own
    // DEFAULT CURRENT_TIMESTAMP — that default is SQLite's own UTC clock,
    // not the supervisor's timezone (see AppTime), and every other
    // recorded timestamp in this file goes through AppTime for the same
    // reason.
    final now = AppTime.nowInUserZone().toIso8601String();
    final today = _todayDateKey();
    final batch = db.batch();
    for (final taskId in taskIds) {
      batch.insert('worker_tasks', {
        'worker_id': workerId,
        'task_id': taskId,
        'assigned_at': now,
        'created_at': now,
        'updated_at': now,
        'task_date': today,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
    await batch.commit(noResult: true);
    await markWorkerUnsynced(workerId);
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
    await markWorkerUnsynced(workerId);
  }

  /// Assigns [taskId] to [workerId] as that worker's one active task for
  /// *today* — an upsert by (worker_id, task_id, task_date) per the
  /// table's own UNIQUE(worker_id, task_id, task_date), always as
  /// `assignment_type = 'default'` (a standing assignment; there is no
  /// more 'temporary'/scheduled-for-today option). A worker has only one
  /// active task at a time: whatever else was active for them (any
  /// task_id, any day) is flipped to `status = 'inactive'` first, so
  /// assigning a new task is really a replacement, not an addition.
  /// Re-activating today's row after it had gone inactive resets
  /// `worker_task_id` to null so [getUnsyncedWorkerTasks] re-picks up the
  /// row for the backend, which needs to hear about the change. A
  /// continuing assignment's *other* days' rows (yesterday's, etc.) are
  /// untouched either way — only today's row is ever written here; see
  /// [getWorkerTasks] for how a new day's row gets created in the first
  /// place.
  ///
  /// [note], when given, is written to the row's own `note` column — used
  /// by the enrollment form's optional Task Note field, which has nowhere
  /// else to land since a freshly-enrolled worker's `worker_tasks` row is
  /// created right here rather than waiting on backend approval (see
  /// CreateEmployeeViewModel.save). Omitted (null) leaves whatever note the
  /// row already has untouched, same as [submitWorkerTaskEntry]'s
  /// [workPhoto] handling — so the supervisor's own re-assignment from
  /// assign_task_screen.dart (which never passes one) never blanks out an
  /// existing note.
  Future<void> assignWorkerTask({
    required int workerId,
    required int taskId,
    String? note,
  }) async {
    final db = await database;
    final now = AppTime.nowInUserZone().toIso8601String();
    final today = _todayDateKey();
    await db.transaction((txn) async {
      await txn.update(
        'worker_tasks',
        {'status': 'inactive', 'updated_at': now},
        where: "worker_id = ? AND task_id != ? AND status = 'active'",
        whereArgs: [workerId, taskId],
      );

      final existing = await txn.query(
        'worker_tasks',
        where: 'worker_id = ? AND task_id = ? AND task_date = ?',
        whereArgs: [workerId, taskId, today],
        limit: 1,
      );
      if (existing.isEmpty) {
        await txn.insert('worker_tasks', {
          'worker_id': workerId,
          'task_id': taskId,
          'assignment_type': 'default',
          'status': 'active',
          'assigned_at': now,
          'created_at': now,
          'updated_at': now,
          'task_date': today,
          'note': note,
        });
      } else {
        final row = existing.first;
        final wasInactive = row['status'] != 'active';
        await txn.update(
          'worker_tasks',
          {
            'assignment_type': 'default',
            'status': 'active',
            'assigned_at': now,
            'updated_at': now,
            if (wasInactive) 'worker_task_id': null,
            'note': ?note,
          },
          where: 'offline_worker_id = ?',
          whereArgs: [row['offline_worker_id']],
        );
      }
    });
    await markWorkerUnsynced(workerId);
  }

  /// The worker's own checkout-time entry for [workerTaskId] (the
  /// `worker_tasks` row's own local id, as read back via
  /// [WorkerTask.workerTaskId]) — the numeric reading and/or photo they
  /// submit on assign_task_screen.dart's Worker Submission card.
  /// [workPhoto] is only written when non-null, so saving just the numeric
  /// value never clears an already-captured photo.
  Future<void> submitWorkerTaskEntry({
    required int workerTaskId,
    required int workerId,
    int? employeeTarget,
    String? workPhoto,
  }) async {
    final db = await database;
    await db.update(
      'worker_tasks',
      {
        'employee_target': employeeTarget,
        'work_photo': ?workPhoto,
        'updated_at': AppTime.nowInUserZone().toIso8601String(),
      },
      where: 'offline_worker_id = ?',
      whereArgs: [workerTaskId],
    );
    await markWorkerUnsynced(workerId);
  }

  /// The supervisor's review of the same assignment — their own numeric
  /// value (`completed_target`, distinct from the worker's own
  /// `employee_target`), note, and [taskStatus] (the assignment's own
  /// approve/reject/pending verdict, `worker_tasks.task_status` — NOT NULL
  /// on the table so always written, unlike [workPhoto]/[note]), plus
  /// [workPhoto] overwriting the worker's own photo only when the
  /// supervisor actually captured/picked a new one (null leaves the
  /// existing `work_photo` untouched).
  Future<void> saveSupervisorTaskReview({
    required int workerTaskId,
    required int workerId,
    int? completedTarget,
    String? workPhoto,
    String? note,
    String taskStatus = 'pending',
  }) async {
    final db = await database;
    await db.update(
      'worker_tasks',
      {
        'completed_target': completedTarget,
        'work_photo': ?workPhoto,
        'note': note,
        'task_status': taskStatus,
        'updated_at': AppTime.nowInUserZone().toIso8601String(),
      },
      where: 'offline_worker_id = ?',
      whereArgs: [workerTaskId],
    );
    await markWorkerUnsynced(workerId);
  }

  /// Every worker_id (local `offline_worker_id`) with at least one active
  /// task assignment, on any day — one query for the whole worker list, so
  /// its "View Tasks" button can disable itself for a worker with nothing
  /// assigned without a query per card. Deliberately not scoped to today's
  /// `task_date`: this is about whether the *standing assignment* exists,
  /// which it does from the moment it's first assigned regardless of
  /// whether anyone's opened a screen today to materialize today's row yet
  /// (see [getWorkerTasks]).
  Future<Set<int>> getWorkerIdsWithAssignedTasks() async {
    final db = await database;
    final rows = await db.rawQuery(
      "SELECT DISTINCT worker_id FROM worker_tasks WHERE status = 'active'",
    );
    return {for (final row in rows) row['worker_id'] as int};
  }

  /// Every worker_id's *today's* active task record's `task_status` — the
  /// worker list's Task Status row, one query for the whole list rather
  /// than a [getWorkerTasks] per card. Scoped to `task_date = today`
  /// (unlike [getWorkerIdsWithAssignedTasks]) so a worker whose standing
  /// assignment hasn't had its row for today created yet simply has no
  /// entry here — [Worker.taskStatus] already reads a missing entry as
  /// 'Pending', which is exactly right for "nothing recorded yet today".
  Future<Map<int, String>> getWorkerTaskStatusByWorker() async {
    final db = await database;
    final rows = await db.rawQuery(
      '''
      SELECT worker_id, task_status FROM worker_tasks
      WHERE status = 'active' AND task_date = ?
    ''',
      [_todayDateKey()],
    );
    return {
      for (final row in rows)
        row['worker_id'] as int: row['task_status'] as String? ?? 'pending',
    };
  }

  // --- Worker attendance (check-in / check-out) methods ---
  //
  // These are additive: they read/write only `worker_attendance` and
  // never touch `attendance_logs` or any of the existing employee-login
  // methods above — the existing attendance-marking flow is unchanged.

  /// `worker_attendance.attendance_date` is a DATE column — a plain
  /// yyyy-MM-dd key, not a full timestamp. Keyed off the supervisor's own
  /// timezone (see AppTime), set from the login response — not the
  /// device's raw system clock, so the attendance-day boundary is
  /// consistent regardless of what timezone a given device happens to be
  /// set to.
  String _todayDateKey() {
    final now = AppTime.nowInUserZone();
    return '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
  }

  /// Records a face-scan event for [workerId] against today's
  /// `worker_attendance` row: the first scan of the day checks them in (once
  /// — a second scan never inserts another check-in row, so a worker can
  /// only check in once per day), and every scan after that updates the
  /// same row's checkout to now, so a worker can check out multiple times a
  /// day and the row always holds the latest one. The `UNIQUE(worker_id,
  /// attendance_date)` constraint is exactly why there's only ever one row
  /// per worker per day to update rather than insert again — and why
  /// syncing this row to the server (see AttendanceSubmissionRepository)
  /// automatically sends that latest checkout rather than an earlier one.
  ///
  /// Deliberately does NOT call [markWorkerUnsynced] (the *worker's own*
  /// `workers.is_synced`/[VerificationStatus] flag) — a worker who's already
  /// Verified stays Verified through check-in/checkout; only an actual
  /// profile/task change (see markWorkerUnsynced's other call sites) should
  /// revert that. Each row's own `worker_attendance.is_synced` (reset to 0
  /// on both check-in and every checkout) is the separate, per-day signal
  /// [WorkerListViewModel]'s sync-button gating actually reads to know this
  /// day's attendance still needs pushing.
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
      final now = AppTime.nowInUserZone().toIso8601String();
      final row = {
        'worker_id': workerId,
        'attendance_date': today,
        'check_in_time': now,
        'check_in_face_verified': 1,
        'status': 'checked_in',
        'is_synced': 0,
      };
      final id = await db.insert('worker_attendance', row);
      return WorkerAttendanceRecord.fromMap({
        ...row,
        'offline_worker_id': id,
      }, outcome: WorkerScanOutcome.checkedIn);
    }

    final row = existing.first;
    final now = AppTime.nowInUserZone().toIso8601String();
    await db.update(
      'worker_attendance',
      {
        'check_out_time': now,
        'check_out_face_verified': 1,
        'status': 'checked_out',
        // A later checkout means this day's attendance needs pushing again,
        // even if an earlier checkout had already been synced.
        'is_synced': 0,
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

  /// [workerId]'s `worker_attendance` rows not yet pushed to the backend
  /// (`is_synced = 0`), oldest first — every day still owed to the server,
  /// not just today's (see AttendanceSubmissionRepository.
  /// submitAllUnsyncedAttendance), since a worker can go several days
  /// without a supervisor syncing them.
  Future<List<WorkerAttendanceRecord>> getUnsyncedAttendance(
    int workerId,
  ) async {
    final db = await database;
    final rows = await db.query(
      'worker_attendance',
      where: 'worker_id = ? AND is_synced = 0',
      whereArgs: [workerId],
      orderBy: 'attendance_date ASC',
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
  ///
  /// [serverTime], when given, is stamped onto every imported/updated
  /// row's `server_time` column — see WorkerImportRepository.
  /// importFromRemote, which passes the UTC instant of that full fetch so
  /// a later [WorkerListApi.fetchServerWorkers] call can ask the server
  /// for changes since exactly that checkpoint (see
  /// [getLatestWorkerServerTime]). Left out of `row` (so an existing row's
  /// own value is untouched) when null — a delta fetch
  /// (WorkerImportRepository.importFromServerTime) doesn't pass one, since
  /// it shouldn't move the checkpoint itself.
  Future<void> upsertRemoteWorkers(
    List<RemoteWorkerRecord> workers, {
    String? serverTime,
  }) async {
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
          // Distinct from worker_id and national_id — this is what the
          // attendance login flow matches on instead of national_id (see
          // AuthRepository/DatabaseHelper.getWorkerByEmployeeId).
          'employee_id': worker.employeeId,
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
              worker.createdDate ?? AppTime.nowInUserZone().toIso8601String(),
          'modified_date': worker.modifiedDate,
          // This row only exists locally because the server already has
          // it, so there's nothing left to push.
          'is_synced': 1,
          'server_time': ?serverTime,
        };

        final existing = await txn.query(
          'workers',
          columns: ['offline_worker_id'],
          where: 'national_id = ?',
          whereArgs: [worker.nationalId],
          limit: 1,
        );

        final int offlineWorkerId;
        if (existing.isEmpty) {
          offlineWorkerId = await txn.insert('workers', {
            ...row,
            'national_id': worker.nationalId,
          });
        } else {
          offlineWorkerId = existing.first['offline_worker_id'] as int;
          await txn.update(
            'workers',
            row,
            where: 'offline_worker_id = ?',
            whereArgs: [offlineWorkerId],
          );
        }

        // Task assignment only happens once the backend confirms this
        // worker as approved (verified) — a rejected (or still-pending)
        // worker gets none of this, regardless of what the response
        // reported, since there's nothing to actually assign them to yet.
        if (worker.status == 'approved') {
          final current = await txn.query(
            'workers',
            columns: ['task_id'],
            where: 'offline_worker_id = ?',
            whereArgs: [offlineWorkerId],
            limit: 1,
          );
          final localTaskId = current.isEmpty
              ? null
              : current.first['task_id'] as int?;

          // Both sources — whatever the response itself reported already
          // assigned server-side, plus whichever task was picked locally
          // at enrollment time (`workers.task_id`, untouched by `row`
          // above, so still whatever it was — see Employee.taskId).
          final taskIdsToAssign = <int>{...worker.taskIds, ?localTaskId};
          if (taskIdsToAssign.isNotEmpty) {
            await _assignMatchingTasks(
              txn,
              offlineWorkerId,
              taskIdsToAssign.toList(),
            );
          }
        }
      }
    });
  }

  /// The most recent `workers.server_time` checkpoint stamped by
  /// [upsertRemoteWorkers]'s `serverTime` param — null if a full fetch
  /// ([WorkerImportRepository.importFromRemote]) has never run. What
  /// [WorkerImportRepository.importFromServerTime] sends as the `date` in
  /// its `POST attendance/worker_data` payload, instead of picking "now"
  /// itself.
  Future<String?> getLatestWorkerServerTime() async {
    final db = await database;
    final rows = await db.rawQuery(
      'SELECT MAX(server_time) AS server_time FROM workers',
    );
    return rows.isEmpty ? null : rows.first['server_time'] as String?;
  }

  /// Assigns [offlineWorkerId] to whichever of [taskIds] (the backend's
  /// `tasks.task_id`) exist in the local `tasks` cache — a task id the
  /// backend sent that hasn't synced into `tasks` locally yet (see
  /// [replaceTasks]) is skipped rather than inserted as a dangling FK.
  /// A task already assigned today is left alone via `worker_tasks`' own
  /// UNIQUE(worker_id, task_id, task_date), same as [assignWorkerTasks].
  Future<void> _assignMatchingTasks(
    DatabaseExecutor txn,
    int offlineWorkerId,
    List<int> taskIds,
  ) async {
    final placeholders = List.filled(taskIds.length, '?').join(',');
    final knownTasks = await txn.query(
      'tasks',
      columns: ['task_id'],
      where: 'task_id IN ($placeholders)',
      whereArgs: taskIds,
    );
    if (knownTasks.isEmpty) return;

    final now = AppTime.nowInUserZone().toIso8601String();
    final today = _todayDateKey();
    final batch = txn.batch();
    for (final task in knownTasks) {
      batch.insert('worker_tasks', {
        'worker_id': offlineWorkerId,
        'task_id': task['task_id'] as int,
        'assigned_at': now,
        'created_at': now,
        'updated_at': now,
        'task_date': today,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
    await batch.commit(noResult: true);
  }

  /// Imports/updates worker-task assignments fetched from the backend
  /// (`POST attendance/worker_task_list` or
  /// `POST attendance/server_time_worker_task_list` — see
  /// WorkerTaskListApi), upserted by (worker, task_id) the same way
  /// [assignWorkerTask] does, so re-running this on a later fetch never
  /// creates a duplicate row.
  ///
  /// [RemoteWorkerTaskRecord.workerId] is the backend's real worker id —
  /// resolved to the local `offline_worker_id` via `workers.worker_id`
  /// first; a record for a worker not yet known locally (not imported/
  /// synced) is skipped rather than inserted as a dangling FK, same as
  /// [_assignMatchingTasks] does for an unknown task.
  Future<void> upsertRemoteWorkerTasks(
    List<RemoteWorkerTaskRecord> records,
  ) async {
    final db = await database;
    final now = AppTime.nowInUserZone().toIso8601String();
    await db.transaction((txn) async {
      for (final record in records) {
        final workerRows = await txn.query(
          'workers',
          columns: ['offline_worker_id'],
          where: 'worker_id = ?',
          whereArgs: [record.workerId],
          limit: 1,
        );
        if (workerRows.isEmpty) continue;
        final offlineWorkerId = workerRows.first['offline_worker_id'] as int;

        final knownTask = await txn.query(
          'tasks',
          columns: ['task_id'],
          where: 'task_id = ?',
          whereArgs: [record.taskId],
          limit: 1,
        );
        if (knownTask.isEmpty) continue;

        final row = {
          'worker_task_id': record.workerTaskId,
          'target': record.target,
          'status': record.status,
          'assignment_type': record.assignmentType,
          'note': record.note,
          'work_photo': record.workPhoto,
          'overtime': record.overtime,
          'employee_target': record.employeeTarget,
          'completed_target': record.completedTarget,
          'task_status': ?record.taskStatus,
          'updated_at': now,
        };

        // Matched against the most recent local row for this (worker,
        // task) regardless of its own task_date — the backend doesn't
        // give this endpoint per-day granularity to match more precisely
        // against, so the latest day's row is the best stand-in for "the
        // current one" when updating an already-known assignment.
        final existing = await txn.query(
          'worker_tasks',
          columns: ['offline_worker_id'],
          where: 'worker_id = ? AND task_id = ?',
          whereArgs: [offlineWorkerId, record.taskId],
          orderBy: 'task_date DESC',
          limit: 1,
        );
        if (existing.isEmpty) {
          final assignedAt = record.assignedAt ?? now;
          await txn.insert('worker_tasks', {
            ...row,
            'worker_id': offlineWorkerId,
            'task_id': record.taskId,
            'assigned_at': assignedAt,
            'created_at': now,
            'task_date': assignedAt.substring(0, 10),
          }, conflictAlgorithm: ConflictAlgorithm.ignore);
        } else {
          await txn.update(
            'worker_tasks',
            row,
            where: 'offline_worker_id = ?',
            whereArgs: [existing.first['offline_worker_id']],
          );
        }
      }
    });
  }
}
