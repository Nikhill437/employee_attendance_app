import '../../../core/base/base_view_model.dart';
import '../../../core/utils/app_time.dart';
import '../../../data/models/worker_attendance_model.dart';
import '../../../data/models/worker_task_model.dart';
import '../../../data/repositories/task_repository.dart';
import '../../../data/repositories/worker_attendance_repository.dart';

/// One day's attendance row — what one card in the Daily Activity list, or
/// the Day Details screen it opens, needs.
class WorkerReportDay {
  final WorkerAttendanceRecord attendance;

  /// The worker's task records for this same day (see
  /// TaskRepository.getWorkerTasksForDate) — empty if none were recorded.
  final List<WorkerTask> tasks;

  const WorkerReportDay({required this.attendance, this.tasks = const []});
}

/// Drives the Worker Report screen: a date-range picker over one worker's
/// `worker_attendance` history, and the period totals shown at the top.
class WorkerReportViewModel extends BaseViewModel {
  final int workerId;
  final WorkerAttendanceRepository _workerAttendance;
  final TaskRepository _tasks;

  WorkerReportViewModel({
    required this.workerId,
    WorkerAttendanceRepository? workerAttendance,
    TaskRepository? tasks,
  }) : _workerAttendance = workerAttendance ?? WorkerAttendanceRepository(),
       _tasks = tasks ?? TaskRepository() {
    final today = _dateOnly(AppTime.nowInUserZone());
    _rangeStart = today.subtract(const Duration(days: 4));
    _rangeEnd = today;
  }

  bool _isLoading = true;
  late DateTime _rangeStart;
  late DateTime _rangeEnd;
  List<WorkerReportDay> _days = const [];

  bool get isLoading => _isLoading;
  DateTime get rangeStart => _rangeStart;
  DateTime get rangeEnd => _rangeEnd;

  /// Newest day first — what the Daily Activity list renders.
  List<WorkerReportDay> get days => _days;

  int get totalDaysInRange => _rangeEnd.difference(_rangeStart).inDays + 1;
  int get daysPresent => _days.where((d) => d.attendance.hasCheckedIn).length;
  int get daysSynced => _days.where((d) => d.attendance.isSynced).length;

  Future<void> load() async {
    _isLoading = true;
    safeNotify();

    final history = await _workerAttendance.getAttendanceHistory(workerId);
    final inRange = history.where((record) {
      final date = DateTime.tryParse(record.attendanceDate);
      if (date == null) return false;
      return !date.isBefore(_rangeStart) && !date.isAfter(_rangeEnd);
    }).toList();

    final days = [
      for (final record in inRange)
        WorkerReportDay(
          attendance: record,
          tasks: await _tasks.getWorkerTasksForDate(
            workerId,
            record.attendanceDate,
          ),
        ),
    ];
    days.sort(
      (a, b) =>
          b.attendance.attendanceDate.compareTo(a.attendance.attendanceDate),
    );

    _days = days;
    _isLoading = false;
    safeNotify();
  }

  Future<void> setRange(DateTime start, DateTime end) async {
    _rangeStart = _dateOnly(start);
    _rangeEnd = _dateOnly(end);
    await load();
  }

  static DateTime _dateOnly(DateTime date) =>
      DateTime(date.year, date.month, date.day);
}
