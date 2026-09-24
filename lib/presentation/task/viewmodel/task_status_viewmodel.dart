import '../../../core/base/base_view_model.dart';
import '../../../data/models/worker_task_completion_model.dart';
import '../../../data/repositories/worker_attendance_repository.dart';

/// Drives the checkout-time task status screen: the worker's assigned
/// tasks for today's attendance day, each with a Yes/No completion toggle
/// the supervisor sets.
class TaskStatusViewModel extends BaseViewModel {
  final int workerId;
  final int attendanceId;
  final WorkerAttendanceRepository _attendanceRepository;

  TaskStatusViewModel({
    required this.workerId,
    required this.attendanceId,
    WorkerAttendanceRepository? attendanceRepository,
  }) : _attendanceRepository = attendanceRepository ?? WorkerAttendanceRepository();

  bool _isLoading = true;
  bool _isSaving = false;
  List<WorkerTaskCompletion> _completions = const [];

  bool get isLoading => _isLoading;
  bool get isSaving => _isSaving;
  List<WorkerTaskCompletion> get completions => _completions;

  Future<void> load() async {
    _isLoading = true;
    safeNotify();
    _completions = await _attendanceRepository.getTaskCompletions(
      workerId: workerId,
      attendanceId: attendanceId,
    );
    _isLoading = false;
    safeNotify();
  }

  /// Updates [completion]'s Yes/No choice in memory only — nothing is
  /// written to `worker_task_completion` until [save] is tapped.
  void setCompletion(WorkerTaskCompletion completion, bool isCompleted) {
    _completions = [
      for (final c in _completions)
        c.workerTaskId == completion.workerTaskId
            ? c.copyWith(isCompleted: isCompleted)
            : c,
    ];
    safeNotify();
  }

  /// Persists every task's current Yes/No choice to `worker_task_completion`
  /// — one upsert per task (see DatabaseHelper.setTaskCompletion, which
  /// updates the existing row for this task/attendance-day pair rather than
  /// duplicating it). Returns true only if every write succeeded; a
  /// completion that failed is left as-is so a retry doesn't skip it.
  Future<bool> save() async {
    _isSaving = true;
    safeNotify();

    var allSucceeded = true;
    for (final completion in _completions) {
      try {
        await _attendanceRepository.setTaskCompletion(
          workerTaskId: completion.workerTaskId,
          workerId: workerId,
          attendanceId: attendanceId,
          isCompleted: completion.isCompleted,
        );
      } catch (_) {
        allSucceeded = false;
      }
    }

    _isSaving = false;
    safeNotify();
    return allSucceeded;
  }
}
