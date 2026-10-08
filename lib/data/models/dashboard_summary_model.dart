/// The figures shown on the supervisor dashboard.
///
/// Only [totalEmployees], [presentToday] and [checkedIn] are derived from
/// stored data today. The sync and verification counters describe an offline
/// sync pipeline that does not exist yet, so they default to zero rather than
/// showing invented numbers.
class DashboardSummary {
  final int pendingRegistrations;
  final DateTime? lastRegistrationSync;

  final int totalEmployees;

  /// Locally stored employees not yet pushed to the server
  /// (`Employee.isSynced` false) — the Employee List Data card's "offline"
  /// stat.
  final int offlineEmployees;

  /// The last successful employee-list fetch's start time (see
  /// WorkerImportRepository.lastSyncedAt) — null if none has run yet.
  final DateTime? employeesLastFetchedAt;

  /// The dashboard's Departments overview card: local cache size and the
  /// last successful fetch's start time.
  final int departmentsTotal;
  final DateTime? departmentsLastFetchedAt;

  /// The dashboard's Tasks overview card: local task-catalog cache size
  /// and the last successful fetch's start time.
  final int tasksCatalogTotal;
  final DateTime? tasksCatalogLastFetchedAt;

  /// The dashboard's Employee Tasks List overview card: local worker-task
  /// row count, how many of those still await a supervisor verdict, and
  /// the last successful fetch's start time.
  final int workerTasksTotal;
  final int pendingWorkerTasks;
  final DateTime? workerTasksLastFetchedAt;

  /// The dashboard's Employee Attendance overview card: local
  /// `worker_attendance` row count, how many haven't been pushed to the
  /// server yet, and the last successful fetch's start time.
  final int attendanceTotal;
  final int unsyncedAttendance;
  final DateTime? attendanceLastFetchedAt;

  final int presentToday;

  final int checkedIn;
  final int checkedOut;
  final int pendingEntries;
  final int pendingSyncEntries;
  final DateTime? lastEntrySync;

  final int verifiedTasks;
  final int pendingTasks;
  final DateTime? lastVerificationSync;

  const DashboardSummary({
    this.pendingRegistrations = 0,
    this.lastRegistrationSync,
    this.totalEmployees = 0,
    this.offlineEmployees = 0,
    this.employeesLastFetchedAt,
    this.departmentsTotal = 0,
    this.departmentsLastFetchedAt,
    this.tasksCatalogTotal = 0,
    this.tasksCatalogLastFetchedAt,
    this.workerTasksTotal = 0,
    this.pendingWorkerTasks = 0,
    this.workerTasksLastFetchedAt,
    this.attendanceTotal = 0,
    this.unsyncedAttendance = 0,
    this.attendanceLastFetchedAt,
    this.presentToday = 0,
    this.checkedIn = 0,
    this.checkedOut = 0,
    this.pendingEntries = 0,
    this.pendingSyncEntries = 0,
    this.lastEntrySync,
    this.verifiedTasks = 0,
    this.pendingTasks = 0,
    this.lastVerificationSync,
  });

  /// Share of the workforce present today, 0–100. Zero when nobody is
  /// enrolled, so the tile never divides by zero.
  int get presentPercent =>
      totalEmployees == 0 ? 0 : (presentToday * 100 / totalEmployees).round();

  int get totalEntries => checkedIn + checkedOut + pendingEntries;
}
