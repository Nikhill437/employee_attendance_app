import '../../../core/base/base_view_model.dart';
import '../../../data/models/employee_model.dart';
import '../../../data/models/worker_attendance_model.dart';
import '../../../data/models/worker_task_model.dart';
import '../../../data/repositories/employee_repository.dart';
import '../../../data/repositories/task_repository.dart';
import '../../../data/repositories/worker_attendance_repository.dart';

/// One worker's history: every check-in/check-out day and every assigned
/// task, for the Reports screen.
class WorkerHistoryEntry {
  final Employee employee;
  final List<WorkerAttendanceRecord> attendanceRecords;
  final List<WorkerTask> tasks;

  const WorkerHistoryEntry({
    required this.employee,
    required this.attendanceRecords,
    required this.tasks,
  });
}

/// Drives the Reports screen: every enrolled worker paired with their full
/// `worker_attendance` check-in/check-out history and assigned task list.
class WorkerHistoryViewModel extends BaseViewModel {
  final EmployeeRepository _employees;
  final WorkerAttendanceRepository _workerAttendance;
  final TaskRepository _tasks;

  WorkerHistoryViewModel({
    EmployeeRepository? employees,
    WorkerAttendanceRepository? workerAttendance,
    TaskRepository? tasks,
  }) : _employees = employees ?? EmployeeRepository(),
       _workerAttendance = workerAttendance ?? WorkerAttendanceRepository(),
       _tasks = tasks ?? TaskRepository();

  bool _isLoading = true;
  List<WorkerHistoryEntry> _entries = const [];

  bool get isLoading => _isLoading;
  List<WorkerHistoryEntry> get entries => _entries;

  Future<void> load() async {
    _isLoading = true;
    safeNotify();

    final workers = await _employees.getUnique();

    final entries = <WorkerHistoryEntry>[];
    for (final worker in workers) {
      final workerId = worker.id;
      entries.add(
        WorkerHistoryEntry(
          employee: worker,
          attendanceRecords: workerId == null
              ? const []
              : await _workerAttendance.getAttendanceHistory(workerId),
          tasks: workerId == null
              ? const []
              : await _tasks.getWorkerTasks(workerId),
        ),
      );
    }

    _entries = entries;
    _isLoading = false;
    safeNotify();
  }
}
