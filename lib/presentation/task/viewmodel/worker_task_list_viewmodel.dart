import '../../../core/base/base_view_model.dart';
import '../../../data/models/worker_task_model.dart';
import '../../../data/repositories/employee_repository.dart';
import '../../../data/repositories/task_repository.dart';

/// Drives the read-only assigned-tasks list — used both from the worker
/// list's "View" action and right after a worker checks in.
class WorkerTaskListViewModel extends BaseViewModel {
  final int workerId;
  final TaskRepository _taskRepository;
  final EmployeeRepository _employeeRepository;

  WorkerTaskListViewModel({
    required this.workerId,
    TaskRepository? taskRepository,
    EmployeeRepository? employeeRepository,
  }) : _taskRepository = taskRepository ?? TaskRepository(),
       _employeeRepository = employeeRepository ?? EmployeeRepository();

  bool _isLoading = true;
  List<WorkerTask> _tasks = const [];
  String? _workerNote;

  bool get isLoading => _isLoading;
  List<WorkerTask> get tasks => _tasks;

  /// The worker's standing note (`workers.note`) — the current, reliably
  /// up to date source for this, unlike each task row's own
  /// `worker_tasks.task_note`, which is only a snapshot copied in at
  /// check-in time and can lag behind a note changed since (see
  /// DatabaseHelper.assignWorkerTask/_ensureTodaysWorkerTaskRow).
  String? get workerNote => _workerNote;

  Future<void> load() async {
    _isLoading = true;
    safeNotify();
    _tasks = await _taskRepository.getWorkerTasks(workerId);
    _workerNote = await _employeeRepository.getWorkerNote(workerId);
    _isLoading = false;
    safeNotify();
  }
}
