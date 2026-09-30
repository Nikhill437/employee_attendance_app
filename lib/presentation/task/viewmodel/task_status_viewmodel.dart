import 'dart:io';

import '../../../core/base/base_view_model.dart';
import '../../../data/models/worker_task_completion_model.dart';
import '../../../data/repositories/worker_attendance_repository.dart';

/// One task's worker-submitted numeric reading/photo and the supervisor's
/// review of them.
///
/// [numericValue]/[photo] are session-only (see the class doc comment on
/// [TaskStatusViewModel]) — [supervisorApproved]/[remark] are backed by the
/// real, already-existing `worker_task_completion.status`/`remarks`
/// columns (see [TaskStatusViewModel.saveReview]), so a task's review
/// survives reopening this screen even though its numeric value/photo
/// don't yet.
class TaskSubmission {
  final WorkerTaskCompletion completion;
  final double? numericValue;
  final File? photo;

  /// True once the worker taps this task's own Save — switches the card
  /// from the worker's entry form to the supervisor's review. Also true on
  /// load for a task the supervisor already reviewed on a previous visit.
  final bool isSubmitted;

  /// Null until the supervisor picks Yes or No.
  final bool? supervisorApproved;
  final String remark;

  /// True once [supervisorApproved]/[remark] match what's actually saved in
  /// `worker_task_completion` — false again the moment either is changed
  /// after a save, so the card can show there's something new to save.
  final bool reviewSaved;

  const TaskSubmission({
    required this.completion,
    this.numericValue,
    this.photo,
    this.isSubmitted = false,
    this.supervisorApproved,
    this.remark = '',
    this.reviewSaved = false,
  });

  TaskSubmission copyWith({
    double? numericValue,
    File? photo,
    bool? isSubmitted,
    bool? reviewSaved,
  }) {
    return TaskSubmission(
      completion: completion,
      numericValue: numericValue ?? this.numericValue,
      photo: photo ?? this.photo,
      isSubmitted: isSubmitted ?? this.isSubmitted,
      supervisorApproved: supervisorApproved,
      remark: remark,
      reviewSaved: reviewSaved ?? this.reviewSaved,
    );
  }

  /// Changing the decision or remark always un-saves the review — unlike
  /// [copyWith], this can actually set [supervisorApproved] back to null or
  /// [remark] back to empty, which a `??`-merging copyWith can't express.
  TaskSubmission withReview({bool? supervisorApproved, String? remark}) {
    return TaskSubmission(
      completion: completion,
      numericValue: numericValue,
      photo: photo,
      isSubmitted: isSubmitted,
      supervisorApproved: supervisorApproved ?? this.supervisorApproved,
      remark: remark ?? this.remark,
      reviewSaved: false,
    );
  }
}

/// Drives the checkout-time task status screen.
///
/// Two phases share the same screen, per task. Phase 1 (worker): each task
/// starts with [TaskSubmission.isSubmitted] false — the worker enters a
/// numeric value and captures a photo (session-only; nothing here is
/// written to `worker_task_completion` for either — that's demonstration-
/// only state until the database work for them is scoped separately), then
/// taps that task's own Save ([submitEntry]), which flips it to phase 2.
/// Phase 2 (supervisor): the same card shows the worker's numeric
/// value/photo read-only, plus a Yes/No decision and a remark the
/// supervisor sets and explicitly saves ([saveReview]) — into the already-
/// existing `worker_task_completion.status`/`remarks` columns, the same
/// ones assign_task_screen.dart's own Is Completed toggle uses, so a task
/// only counts as reviewed once that row actually exists (see
/// DatabaseHelper.getWorkerIdsWithPendingTaskReview, which
/// worker_list_screen.dart's sync-button gating reads).
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
  List<TaskSubmission> _submissions = const [];

  bool get isLoading => _isLoading;
  List<TaskSubmission> get submissions => _submissions;

  Future<void> load() async {
    _isLoading = true;
    safeNotify();
    final completions = await _attendanceRepository.getTaskCompletions(
      workerId: workerId,
      attendanceId: attendanceId,
    );
    _submissions = [
      for (final completion in completions)
        TaskSubmission(
          completion: completion,
          isSubmitted: completion.completionId != null,
          supervisorApproved:
              completion.completionId != null ? completion.isCompleted : null,
          remark: completion.remarks ?? '',
          reviewSaved: completion.completionId != null,
        ),
    ];
    _isLoading = false;
    safeNotify();
  }

  void setNumericValue(TaskSubmission submission, double? numericValue) {
    _replace(submission.copyWith(numericValue: numericValue));
  }

  void setPhoto(TaskSubmission submission, File photo) {
    _replace(submission.copyWith(photo: photo));
  }

  /// The worker's per-task Save — the numeric value/photo aren't persisted
  /// (see the class doc comment), so this just flips the card into the
  /// supervisor's review view for this one task.
  void submitEntry(TaskSubmission submission) {
    _replace(submission.copyWith(isSubmitted: true));
  }

  void setSupervisorDecision(TaskSubmission submission, bool approved) {
    _replace(submission.withReview(supervisorApproved: approved));
  }

  void setRemark(TaskSubmission submission, String remark) {
    _replace(submission.withReview(remark: remark));
  }

  /// Persists [submission]'s Yes/No decision and remark — a no-op if no
  /// decision has been picked yet. An upsert per task (see
  /// DatabaseHelper.setTaskCompletion), so re-saving an already-reviewed
  /// task updates that same row rather than duplicating it.
  Future<void> saveReview(TaskSubmission submission) async {
    final approved = submission.supervisorApproved;
    if (approved == null) return;
    await _attendanceRepository.setTaskCompletion(
      workerTaskId: submission.completion.workerTaskId,
      workerId: workerId,
      attendanceId: attendanceId,
      isCompleted: approved,
      remarks: submission.remark.trim().isEmpty ? null : submission.remark.trim(),
    );
    _replace(submission.copyWith(reviewSaved: true));
  }

  void _replace(TaskSubmission updated) {
    _submissions = [
      for (final s in _submissions)
        s.completion.workerTaskId == updated.completion.workerTaskId ? updated : s,
    ];
    safeNotify();
  }
}
