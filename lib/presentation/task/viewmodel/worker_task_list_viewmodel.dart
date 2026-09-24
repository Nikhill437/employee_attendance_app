import '../../../core/base/base_view_model.dart';
import '../../../data/models/worker_task_model.dart';
import '../../../data/repositories/task_repository.dart';

/// Drives the read-only assigned-tasks list — used both from the worker
/// list's "View" action and right after a worker checks in.
class WorkerTaskListViewModel extends BaseViewModel {
  final int workerId;
  final TaskRepository _taskRepository;

  WorkerTaskListViewModel({required this.workerId, TaskRepository? taskRepository})
    : _taskRepository = taskRepository ?? TaskRepository();

  bool _isLoading = true;
  List<WorkerTask> _tasks = const [];

  bool get isLoading => _isLoading;
  List<WorkerTask> get tasks => _tasks;

  Future<void> load() async {
    _isLoading = true;
    safeNotify();
    _tasks = await _taskRepository.getWorkerTasks(workerId);
    _isLoading = false;
    safeNotify();
  }
}
