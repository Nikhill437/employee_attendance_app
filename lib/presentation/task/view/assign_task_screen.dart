import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/app_time.dart';
import '../../../data/models/department_model.dart';
import '../../../data/models/worker_task_model.dart';
import '../../common/widgets/common_widgets.dart';
import '../viewmodel/assign_task_viewmodel.dart';

/// Two modes, same screen. The supervisor's mode (default — reached from
/// worker_list_screen.dart's "Assign Task" action) picks a department,
/// assigns one task to a worker (replacing whatever was assigned before),
/// and — once a task is assigned — shows the worker's own checkout-time
/// submission for it plus the supervisor's review of that submission. The
/// worker's checkout mode ([isCheckoutSubmission], reached from
/// mark_attendance_screen.dart) only shows the already-assigned task's
/// name and the Worker Submission card.
class AssignTaskScreen extends StatefulWidget {
  final int workerId;
  final String workerName;

  /// Shown in the header under the worker's name, alongside their
  /// department once known — null (nothing passed yet from any call site)
  /// shows the department alone.
  final String? employeeId;

  /// The worker's department, shown as a static field — department is not
  /// editable from this screen (see EditWorkerScreen for that).
  final String? department;

  /// The worker's own department id — the task dropdown is filtered to
  /// this department's tasks.
  final int? initialDepartmentId;

  /// True when this screen was opened from the worker's own checkout
  /// (mark_attendance_screen.dart) rather than from worker_list_screen.
  /// dart's "Assign Task" action. Checkout only shows the already-assigned
  /// task's name and the Worker Submission card — no department field, no
  /// task dropdown/reassignment, and no Supervisor Review card, since
  /// none of that is the worker's to do at checkout.
  final bool isCheckoutSubmission;

  /// Overridable so tests can inject a fake, avoiding the real DatabaseHelper.
  final AssignTaskViewModel? viewModel;

  const AssignTaskScreen({
    super.key,
    required this.workerId,
    required this.workerName,
    this.employeeId,
    this.department,
    this.initialDepartmentId,
    this.isCheckoutSubmission = false,
    this.viewModel,
  });

  @override
  State<AssignTaskScreen> createState() => _AssignTaskScreenState();
}

class _AssignTaskScreenState extends State<AssignTaskScreen> {
  late final AssignTaskViewModel _viewModel;
  final _pendingNoteController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _viewModel =
        widget.viewModel ??
        AssignTaskViewModel(
          workerId: widget.workerId,
          initialDepartmentId: widget.initialDepartmentId,
        );
    _pendingNoteController.addListener(
      () => _viewModel.setPendingNote(_pendingNoteController.text),
    );
    _viewModel.loadTasks();
  }

  @override
  void dispose() {
    _pendingNoteController.dispose();
    _viewModel.dispose();
    super.dispose();
  }

  /// On success, pops back to worker_list_screen.dart (this screen is only
  /// ever reached from there — see WorkerListScreen._openAssignTask, which
  /// reloads the list on a truthy pop so a department change shows). On
  /// failure, stays put with an error so the supervisor can retry.
  /// Asks before any save runs. "No" closes only the dialog, so nothing is
  /// written and the entered data stays on screen.
  Future<bool> _confirmSave() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => const _SaveConfirmDialog(),
    );
    return confirmed == true;
  }

  Future<void> _save() async {
    if (!await _confirmSave() || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final error = await _viewModel.save();
    if (!mounted) return;
    if (error == null) {
      navigator.pop(true);
      return;
    }
    messenger.showSnackBar(SnackBar(content: Text(error)));
  }

  Future<File?> _capturePhoto() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.camera,
      maxWidth: 1600,
      imageQuality: 85,
    );
    return picked == null ? null : File(picked.path);
  }

  Future<void> _captureEntryPhoto() async {
    final photo = await _capturePhoto();
    if (photo != null) await _viewModel.captureEntryPhoto(photo);
  }

  Future<void> _captureReviewPhoto() async {
    final photo = await _capturePhoto();
    if (photo != null) await _viewModel.captureReviewPhoto(photo);
  }

  /// On success, pops back — same as [_save]/[_saveSupervisorReview]. Just
  /// a plain pop regardless of mode: the worker's own checkout submission
  /// (reached from mark_attendance_screen.dart) used to jump straight to
  /// the login screen from here via `pushNamedAndRemoveUntil`, but that
  /// mutated the shared root navigator's history out from under
  /// MarkAttendanceScreen's own still-pending `await Navigator.push(...)`
  /// for this very route — ripping the route out while an ancestor awaits
  /// it is what caused the "_history.isNotEmpty" crash once that ancestor
  /// resumed and tried to navigate again on an already-collapsed stack.
  /// MarkAttendanceScreen now does that redirect itself, after this pop
  /// has already resolved cleanly (see its _openFollowUpScreen).
  Future<void> _saveWorkerEntry() async {
    if (!await _confirmSave() || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final error = await _viewModel.saveWorkerEntry();
    if (!mounted) return;
    if (error != null) {
      messenger.showSnackBar(SnackBar(content: Text(error)));
      return;
    }
    navigator.pop(true);
  }

  Future<void> _saveSupervisorReview() async {
    if (!await _confirmSave() || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final error = await _viewModel.saveSupervisorReview();
    if (!mounted) return;
    if (error != null) {
      messenger.showSnackBar(SnackBar(content: Text(error)));
      return;
    }
    navigator.pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.pageGrey,
      body: Column(
        children: [
          _buildHeader(),
          Expanded(
            // No bottomNavigationBar on this screen, so (unlike a body that
            // sits above AppBottomNavBar) its own Save/Assign buttons need
            // their own clearance from the system navigation bar/gesture area.
            child: SafeArea(
              top: false,
              child: ListenableBuilder(
                listenable: _viewModel,
                builder: (context, _) => _buildBody(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final now = AppTime.nowInUserZone();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      decoration: const BoxDecoration(
        color: AppColors.gradientTop,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
      ),
      child: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleHeaderAction(
                  icon: Icons.arrow_back,
                  tooltip: 'Back',
                  onPressed: () => Navigator.maybePop(context),
                ),
                Padding(
                  padding: EdgeInsets.only(
                    left: MediaQuery.of(context).size.width * 0.28,
                  ),
                  child: Text(
                    "Task",
                    style: TextStyle(fontSize: 22, color: Colors.white),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _HeaderAvatar(name: widget.workerName),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.workerName,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _headerSubtitle(),
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          color: Colors.white70,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      _shortDate(now),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _weekdayName(now),
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.white70,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _headerSubtitle() {
    final departmentName = widget.department;
    if (widget.employeeId == null) return departmentName ?? 'Unassigned';
    return '${widget.employeeId} • ${departmentName ?? 'Unassigned'}';
  }

  static const _weekdayNames = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];
  static const _monthAbbreviations = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  String _weekdayName(DateTime date) => _weekdayNames[date.weekday - 1];
  String _shortDate(DateTime date) =>
      '${_monthAbbreviations[date.month - 1]} ${date.day}';

  Widget _buildBody() {
    if (_viewModel.isLoadingTasks) {
      return const Center(child: CircularProgressIndicator());
    }

    return widget.isCheckoutSubmission
        ? _buildCheckoutBody()
        : _buildSupervisorBody();
  }

  /// The worker's own checkout-time view: just the assigned task's name
  /// and their Worker Submission card — no department/task picker, no
  /// Supervisor Review.
  Widget _buildCheckoutBody() {
    final assignedTask = _viewModel.assignedTask;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      children: [
        if (assignedTask == null)
          const Padding(
            padding: EdgeInsets.only(top: 24),
            child: Center(
              child: Text(
                'No task assigned yet',
                style: TextStyle(color: AppColors.muted),
              ),
            ),
          )
        else ...[
          // The worker's view doesn't show the rate. The supervisor's view does.
          _CurrentAssignmentBanner(
            taskName: assignedTask.taskName,
            target: assignedTask.taskTarget,
          ),
          const SizedBox(height: 18),
          const SectionLabel('WORKER SUBMISSION'),
          const SizedBox(height: 10),
          _WorkerSubmissionCard(
            numericValue: _viewModel.entryNumericValue,
            photo: _viewModel.entryPhoto,
            isSaving: _viewModel.isSubmittingEntry,
            onNumericChanged: _viewModel.setEntryNumericValue,
            onCapturePhoto: _captureEntryPhoto,
            onSave: _saveWorkerEntry,
          ),
        ],
      ],
    );
  }

  /// The supervisor's full view: pick/assign a task, plus (once one is
  /// assigned) the Worker Submission and Supervisor Review cards.
  Widget _buildSupervisorBody() {
    final assignedTask = _viewModel.assignedTask;
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            children: [
              const SectionLabel('ASSIGN A NEW TASK'),
              const SizedBox(height: 10),
              _buildDepartmentField(),
              const SizedBox(height: 18),
              if (assignedTask != null) ...[
                _CurrentAssignmentBanner(
                  taskName: assignedTask.taskName,
                  target: assignedTask.taskTarget,
                  rate: assignedTask.taskRate,
                ),
                const SizedBox(height: 14),
              ],
              _buildTaskPicker(),
              const SizedBox(height: 12),
              _buildPendingTaskCard(),
              if (assignedTask != null) ...[
                const SizedBox(height: 20),
                const Divider(height: 1, color: AppColors.cardBorder),
                const SizedBox(height: 18),
                if (_hasWorkerSubmission(assignedTask)) ...[
                  const SectionLabel('WORKER SUBMISSION'),
                  const SizedBox(height: 10),
                  _WorkerSubmissionReadOnlyCard(task: assignedTask),
                  const SizedBox(height: 18),
                ],
                const SectionLabel('SUPERVISOR REVIEW'),
                const SizedBox(height: 10),
                if (_viewModel.isReviewLocked)
                  _SupervisorReviewReadOnlyCard(task: assignedTask)
                else
                  _SupervisorReviewCard(
                    numericValue: _viewModel.reviewNumericValue,
                    photo: _viewModel.reviewPhoto,
                    note: _viewModel.reviewNote,
                    taskStatus: _viewModel.reviewTaskStatus,
                    isSaving: _viewModel.isSavingReview,
                    onNumericChanged: _viewModel.setReviewNumericValue,
                    onCapturePhoto: _captureReviewPhoto,
                    onNoteChanged: _viewModel.setReviewNote,
                    onTaskStatusChanged: _viewModel.setReviewTaskStatus,
                    onSave: _saveSupervisorReview,
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  /// Whether [task] carries the worker's own checkout-time entry yet — the
  /// signal for whether the supervisor's Worker Submission card has
  /// anything to show at all (see _buildSupervisorBody).
  bool _hasWorkerSubmission(WorkerTask task) => task.employeeTarget != null;

  Widget _buildDepartmentField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Department',
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w600,
            color: AppColors.slate,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
          decoration: BoxDecoration(
            color: const Color(0xFFF2F3F2),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.cardBorder),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.apartment_outlined,
                size: 20,
                color: AppColors.muted,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  widget.department ?? 'Unassigned',
                  style: const TextStyle(fontSize: 15, color: AppColors.ink),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTaskPicker() {
    if (_viewModel.isLoadingTasks) {
      return _buildDisabledTaskField('Loading tasks...');
    }
    if (!_viewModel.canPickNewTask) {
      // A pick is already pending — see _buildPendingTaskCard, which shows
      // it with its own remove action instead of this field.
      return const SizedBox.shrink();
    }
    if (_viewModel.departmentTasksIsEmpty) {
      return _buildDisabledTaskField('No tasks available for this department');
    }

    // Shared dropdown (bottom sheet). Always shown with no value: picking a
    // task puts it in the pending card below, and the field resets.
    return AppDropdownField<Task>(
      label: 'Task',
      hint: 'Select a task to assign',
      icon: Icons.task_alt_outlined,
      value: null,
      items: _viewModel.availableTasks,
      labelBuilder: (task) => task.name,
      onChanged: (task) {
        if (task != null) _viewModel.addTask(task);
      },
    );
  }

  /// The supervisor's picked-but-not-yet-assigned task, if any — only one
  /// at a time (see AssignTaskViewModel.canPickNewTask), with a remove
  /// action and the Assign button.
  Widget _buildPendingTaskCard() {
    final pending = _viewModel.pendingTask;
    if (pending == null) return const SizedBox.shrink();

    return Column(
      children: [
        _PendingTaskCard(
          task: pending,
          onRemove: () {
            _viewModel.removePendingTask();
            _pendingNoteController.clear();
          },
        ),
        const SizedBox(height: 15),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
          child: AppFormField(
            label: 'Note',
            hint: 'Add an optional note for this task',
            icon: Icons.notes_outlined,
            controller: _pendingNoteController,
            minLines: 2,
            maxLines: 3,
            maxLength: 500,
          ),
        ),
        const SizedBox(height: 15),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
          child: AppPrimaryButton(
            label: 'Assign Task',
            isBusy: _viewModel.isSaving,
            onPressed: _save,
          ),
        ),
      ],
    );
  }

  Widget _buildDisabledTaskField(String hint) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Task',
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w600,
            color: AppColors.slate,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
          decoration: BoxDecoration(
            color: const Color(0xFFF2F3F2),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.cardBorder),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.task_alt_outlined,
                size: 20,
                color: AppColors.muted,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  hint,
                  style: const TextStyle(fontSize: 15, color: AppColors.muted),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _HeaderAvatar extends StatelessWidget {
  final String name;

  const _HeaderAvatar({required this.name});

  String get _initials {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withValues(alpha: 0.16),
      ),
      child: Text(
        _initials,
        style: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
      ),
    );
  }
}

/// Shows which task is currently the worker's one active assignment,
/// right above the dropdown that would replace it.
class _CurrentAssignmentBanner extends StatelessWidget {
  final String taskName;

  /// The task catalog's own daily quantity goal / hourly-piece rate (see
  /// Task.target/Task.rate) — shown alongside the task name when the
  /// backend has set either; a null one is left out rather than shown
  /// blank or as zero.
  final int? target;
  final int? rate;

  const _CurrentAssignmentBanner({
    required this.taskName,
    this.target,
    this.rate,
  });

  @override
  Widget build(BuildContext context) {
    final targetRate = _formatTargetRate(target, rate);
    // A plain Container, not Expanded(Container(...)) — this widget is
    // always placed directly as a ListView item (see _buildCheckoutBody/
    // _buildSupervisorBody), never as a Row/Column child, and Expanded
    // only works as a direct child of a Flex. Wrapping it here threw
    // "Incorrect use of ParentDataWidget" the moment this banner rendered.
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFFE7F6EC),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.task_alt, size: 18, color: AppColors.success),
              const SizedBox(width: 5),
              Text(
                'Currently assigned:',
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.ink,
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Padding(
            padding: const EdgeInsets.only(left: 20.0),
            child: Text(
              taskName,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppColors.ink,
              ),
            ),
          ),
          if (targetRate != null)
            Padding(
              padding: const EdgeInsets.only(left: 20.0, top: 2),
              child: Text(
                targetRate,
                style: const TextStyle(fontSize: 13, color: AppColors.slate),
              ),
            ),
        ],
      ),
    );
  }
}

/// "Target: 50 · Rate: 12" (either half omitted when its own value is
/// null), or null outright when both are — never shown blank or as zero.
/// Shared by [_CurrentAssignmentBanner] and [_PendingTaskCard].
String? _formatTargetRate(int? target, int? rate) {
  final parts = [
    if (target != null) 'Target: $target',
    if (rate != null) 'Rate: $rate',
  ];
  return parts.isEmpty ? null : parts.join(' · ');
}

/// A task picked in the dropdown above but not assigned yet.
class _PendingTaskCard extends StatelessWidget {
  final Task task;
  final VoidCallback onRemove;

  const _PendingTaskCard({required this.task, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    final targetRate = _formatTargetRate(task.target, task.rate);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.task_alt_outlined,
            size: 20,
            color: AppColors.warning,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  task.name,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.ink,
                  ),
                ),
                if (targetRate != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      targetRate,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: AppColors.slate,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18, color: AppColors.muted),
            tooltip: 'Remove',
            onPressed: onRemove,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
        ],
      ),
    );
  }
}

/// The supervisor's read-only view of the worker's own checkout-time
/// submission — shown once the worker has actually entered something (see
/// _AssignTaskScreenState._hasWorkerSubmission), never editable here and
/// with no Save button of its own.
class _WorkerSubmissionReadOnlyCard extends StatelessWidget {
  final WorkerTask task;

  const _WorkerSubmissionReadOnlyCard({required this.task});

  @override
  Widget build(BuildContext context) {
    final photoPath = task.workPhoto;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ReadOnlyValueField(
            label: 'Target',
            icon: Icons.numbers,
            value: task.employeeTarget?.toString() ?? 'Not provided',
          ),
          const SizedBox(height: 14),
          AppImageCaptureField(
            label: 'Task Photo',
            hint: 'No photo submitted',
            image: photoPath == null ? null : File(photoPath),
            enabled: false,
            onCapture: () {},
          ),
        ],
      ),
    );
  }
}

/// The supervisor's own read-only view of *today's* review, once it's
/// already synced to the backend (see AssignTaskViewModel.isReviewLocked)
/// — there's nothing left to edit for today, so no Save button either.
/// Becomes editable again on its own the moment a new day's row exists.
class _SupervisorReviewReadOnlyCard extends StatelessWidget {
  final WorkerTask task;

  const _SupervisorReviewReadOnlyCard({required this.task});

  static String _taskStatusLabel(String status) => switch (status) {
    'approved' => 'Approve',
    'rejected' => 'Reject',
    _ => 'Pending',
  };

  @override
  Widget build(BuildContext context) {
    final photoPath = task.workPhoto;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ReadOnlyValueField(
            label: 'Target',
            icon: Icons.numbers,
            value: task.completedTarget?.toString() ?? 'Not provided',
          ),
          const SizedBox(height: 14),
          _ReadOnlyValueField(
            label: 'Employee Task Status',
            icon: Icons.task_alt,
            value: _taskStatusLabel(task.taskStatus),
          ),
          const SizedBox(height: 14),
          AppImageCaptureField(
            label: 'Task Photo',
            hint: 'No photo submitted',
            image: photoPath == null ? null : File(photoPath),
            enabled: false,
            onCapture: () {},
          ),
          const SizedBox(height: 14),
          _ReadOnlyValueField(
            label: 'Note',
            icon: Icons.notes_outlined,
            value:
                (task.supervisorNote == null ||
                    task.supervisorNote!.trim().isEmpty)
                ? 'No note added'
                : task.supervisorNote!,
          ),
        ],
      ),
    );
  }
}

/// A labelled, non-interactive value display matching [AppFormField]'s
/// look — used where a field needs the same visual weight as an editable
/// one but must never accept input (e.g. the supervisor's read-only view
/// of the worker's own submission).
class _ReadOnlyValueField extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _ReadOnlyValueField({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w600,
            color: AppColors.slate,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.cardBorder),
          ),
          child: Row(
            children: [
              Icon(icon, size: 20, color: AppColors.muted),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  value,
                  style: const TextStyle(fontSize: 15, color: AppColors.ink),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The worker's checkout-time entry for the currently assigned task —
/// a numeric reading and a photo, saved into `worker_tasks.employee_target`/
/// `work_photo`.
class _WorkerSubmissionCard extends StatefulWidget {
  final int? numericValue;
  final File? photo;
  final bool isSaving;
  final ValueChanged<int?> onNumericChanged;
  final VoidCallback onCapturePhoto;
  final VoidCallback onSave;

  const _WorkerSubmissionCard({
    required this.numericValue,
    required this.photo,
    required this.isSaving,
    required this.onNumericChanged,
    required this.onCapturePhoto,
    required this.onSave,
  });

  @override
  State<_WorkerSubmissionCard> createState() => _WorkerSubmissionCardState();
}

class _WorkerSubmissionCardState extends State<_WorkerSubmissionCard> {
  late final TextEditingController _numericController;

  @override
  void initState() {
    super.initState();
    _numericController = TextEditingController(
      text: widget.numericValue?.toString() ?? '',
    )..addListener(_onNumericTextChanged);
  }

  void _onNumericTextChanged() {
    widget.onNumericChanged(int.tryParse(_numericController.text.trim()));
  }

  @override
  void dispose() {
    _numericController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppFormField(
            label: 'Target',
            hint: 'Enter a numeric value',
            icon: Icons.numbers,
            controller: _numericController,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            isRequired: true,
          ),
          const SizedBox(height: 14),
          AppImageCaptureField(
            label: 'Task Photo',
            hint: 'Tap to capture a photo for this task',
            image: widget.photo,
            onCapture: widget.onCapturePhoto,
          ),
          const SizedBox(height: 14),
          AppSecondaryButton(
            label: widget.isSaving ? 'Saving...' : 'Save',
            onPressed: (widget.isSaving || widget.numericValue == null)
                ? null
                : widget.onSave,
          ),
        ],
      ),
    );
  }
}

/// The supervisor's review of the worker's submission — the same numeric
/// value/photo fields (defaulting to what the worker entered) plus a note,
/// saved into `worker_tasks.completed_target`/`work_photo`/`note`.
class _SupervisorReviewCard extends StatefulWidget {
  final int? numericValue;
  final File? photo;
  final String note;

  /// The assignment's own approve/reject/pending verdict
  /// (`worker_tasks.task_status`) — always one of [_taskStatusOptions].
  final String taskStatus;
  final bool isSaving;
  final ValueChanged<int?> onNumericChanged;
  final VoidCallback onCapturePhoto;
  final ValueChanged<String> onNoteChanged;
  final ValueChanged<String> onTaskStatusChanged;
  final VoidCallback onSave;

  const _SupervisorReviewCard({
    required this.numericValue,
    required this.photo,
    required this.note,
    required this.taskStatus,
    required this.isSaving,
    required this.onNumericChanged,
    required this.onCapturePhoto,
    required this.onNoteChanged,
    required this.onTaskStatusChanged,
    required this.onSave,
  });

  @override
  State<_SupervisorReviewCard> createState() => _SupervisorReviewCardState();
}

class _SupervisorReviewCardState extends State<_SupervisorReviewCard> {
  // The three verdicts a supervisor can record against an assignment —
  // stored in `worker_tasks.task_status` under their raw (backend-ENUM-
  // matching) names; [_taskStatusLabel] is what the picker actually shows.
  static const List<String> _taskStatusOptions = [
    'approved',
    'rejected',
    'pending',
  ];

  static String _taskStatusLabel(String status) => switch (status) {
    'approved' => 'Approve',
    'rejected' => 'Reject',
    _ => 'Pending',
  };

  late final TextEditingController _numericController;
  late final TextEditingController _noteController;

  @override
  void initState() {
    super.initState();
    _numericController = TextEditingController(
      text: widget.numericValue?.toString() ?? '',
    )..addListener(_onNumericTextChanged);
    _noteController = TextEditingController(text: widget.note)
      ..addListener(_onNoteTextChanged);
  }

  void _onNumericTextChanged() {
    widget.onNumericChanged(int.tryParse(_numericController.text.trim()));
  }

  void _onNoteTextChanged() {
    widget.onNoteChanged(_noteController.text);
  }

  @override
  void dispose() {
    _numericController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppFormField(
            label: 'Completion count/hours',
            hint: 'Enter a numeric value',
            icon: Icons.numbers,
            controller: _numericController,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            isRequired: true,
          ),
          const SizedBox(height: 14),
          AppOptionSelector<String>(
            label: 'Employee Task Status',
            options: _taskStatusOptions,
            selected: widget.taskStatus,
            onSelected: widget.onTaskStatusChanged,
            labelBuilder: _taskStatusLabel,
          ),
          const SizedBox(height: 14),
          AppImageCaptureField(
            label: 'Task Photo',
            hint: 'Tap to capture a photo for this task',
            image: widget.photo,
            onCapture: widget.onCapturePhoto,
          ),
          const SizedBox(height: 14),
          AppFormField(
            label: 'Note',
            hint: 'Add a note for this task',
            icon: Icons.notes_outlined,
            controller: _noteController,
            minLines: 2,
            maxLines: 3,
          ),
          const SizedBox(height: 14),
          AppSecondaryButton(
            label: widget.isSaving ? 'Saving...' : 'Save',
            onPressed: (widget.isSaving || widget.numericValue == null)
                ? null
                : widget.onSave,
          ),
        ],
      ),
    );
  }
}

/// The "Do you want to save the information?" prompt, styled like the rest
/// of the app: a rounded card, a green icon badge, and deep green Yes.
/// Yes resolves true, No resolves false, and dismissing the dialog counts
/// as No, so nothing is saved unless the supervisor taps Yes.
class _SaveConfirmDialog extends StatelessWidget {
  const _SaveConfirmDialog();

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 26, 22, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: AppColors.deepGreen.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.save_outlined,
                size: 28,
                color: AppColors.deepGreen,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Save information',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.ink,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Do you want to save the information?',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                height: 1.4,
                color: AppColors.muted,
              ),
            ),
            const SizedBox(height: 22),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context, false),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.slate,
                      side: const BorderSide(color: AppColors.cardBorder),
                      minimumSize: const Size(0, 46),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'No',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context, true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.deepGreen,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      minimumSize: const Size(0, 46),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Yes',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
