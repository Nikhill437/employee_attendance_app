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
