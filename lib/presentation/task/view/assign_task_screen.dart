import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/app_time.dart';
import '../../../data/models/department_model.dart';
import '../../../data/models/worker_task_completion_model.dart';
import '../../common/widgets/common_widgets.dart';
import '../viewmodel/assign_task_viewmodel.dart';

/// Supervisor screen for one worker's day: today's attendance and assigned
/// task checklist up top ("Day Details"), then — unchanged from before —
/// picking a department and choosing which of its tasks to assign.
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

  /// Overridable so tests can inject a fake, avoiding the real DatabaseHelper.
  final AssignTaskViewModel? viewModel;

  const AssignTaskScreen({
    super.key,
    required this.workerId,
    required this.workerName,
    this.employeeId,
    this.department,
    this.initialDepartmentId,
    this.viewModel,
  });

  @override
  State<AssignTaskScreen> createState() => _AssignTaskScreenState();
}

class _AssignTaskScreenState extends State<AssignTaskScreen> {
  late final AssignTaskViewModel _viewModel;

  @override
  void initState() {
    super.initState();
    _viewModel =
        widget.viewModel ??
        AssignTaskViewModel(
          workerId: widget.workerId,
          initialDepartmentId: widget.initialDepartmentId,
        );
    _viewModel.loadTasks();
    _viewModel.loadDayDetails();
  }

  @override
  void dispose() {
    _viewModel.dispose();
    super.dispose();
  }

  /// On success, pops back to worker_list_screen.dart (this screen is only
  /// ever reached from there — see WorkerListScreen._openAssignTask, which
  /// reloads the list on a truthy pop so a department change shows). On
  /// failure, stays put with an error so the supervisor can retry.
  Future<void> _save() async {
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

  /// Writes today's Is Completed toggles to `worker_task_completion` and
  /// confirms it with a snackbar, so the supervisor knows the status
  /// change actually landed rather than just changing on screen.
  Future<void> _saveTaskStatus() async {
    final messenger = ScaffoldMessenger.of(context);
    final error = await _viewModel.saveTaskStatus();
    if (!mounted) return;
    messenger.showSnackBar(
      SnackBar(content: Text(error ?? 'Task status saved successfully')),
    );
  }

  /// Retries pushing today's attendance record to the backend — the Retry
  /// button on the "not synced" banner.
  Future<void> _retryAttendanceSync() async {
    final messenger = ScaffoldMessenger.of(context);
    final error = await _viewModel.syncAttendance();
    if (!mounted) return;
    if (error != null) {
      messenger.showSnackBar(
        SnackBar(content: Text('Could not sync attendance: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.pageGrey,
      body: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: ListenableBuilder(
              listenable: _viewModel,
              builder: (context, _) => _buildBody(),
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
              _buildTaskPicker(),
              const SizedBox(height: 12),
              _buildPendingTasksList(),
              const SizedBox(height: 20),
              const Divider(height: 1, color: AppColors.cardBorder),
              const SizedBox(height: 18),
              if (!_viewModel.isLoadingDayDetails) ..._buildDayDetails(),
            ],
          ),
        ),
      ],
    );
  }

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

  /// The Day Details section: today's attendance, sync status, and the
  /// worker's already-assigned tasks tracked checklist for today — always
  /// shown, never hidden behind a data-availability check, so the layout
  /// doesn't shift around depending on what's been recorded yet.
  List<Widget> _buildDayDetails() {
    final completions = _viewModel.todayTaskCompletions;

    return [
      _AssignedTasksSection(
        completions: completions,
        completedCount: _viewModel.completedTaskCount,
        totalCount: _viewModel.totalTaskCount,
        onCompletionChanged: (completion, isCompleted) =>
            _viewModel.setTaskCompletion(completion, isCompleted),
      ),
      if (completions.isNotEmpty) ...[
        const SizedBox(height: 14),
        AppSecondaryButton(
          label: _viewModel.isSavingTaskStatus ? 'Saving...' : 'Save',
          onPressed: _viewModel.isSavingTaskStatus ? null : _saveTaskStatus,
        ),
      ],
      const SizedBox(height: 14),
      const _OfflineNote(),
      const SizedBox(height: 8),
    ];
  }

  Widget _buildTaskPicker() {
    if (_viewModel.isLoadingTasks) {
      return _buildDisabledTaskField('Loading tasks...');
    }
    if (_viewModel.departmentTasksIsEmpty) {
      return _buildDisabledTaskField('No tasks available for this department');
    }

    return AppDropdownField<Task>(
      // DropdownButtonFormField is uncontrolled (it only reads `value` once,
      // as its `initialValue`) — without a key tied to the selection count,
      // it keeps its last pick internally even after that task drops out of
      // `items` below, and then crashes ("exactly one item with value...")
      // on the next rebuild since nothing in `items` matches it anymore.
      // Changing the key on every add/remove forces a fresh widget instance
      // instead, which really does reset to null.
      key: ValueKey(_viewModel.pendingTasks.length),
      label: 'Task',
      hint: 'Select a task to add',
      icon: Icons.task_alt_outlined,
      // Always null: picking a task adds it to the list below and the
      // dropdown resets, rather than retaining the pick as its value.
      value: null,
      items: _viewModel.availableTasks,
      labelBuilder: (task) => task.name,
      onChanged: (task) {
        if (task != null) _viewModel.addTask(task);
      },
    );
  }

  /// The supervisor's picked-but-not-yet-assigned tasks, each with a
  /// Scheduled-for-today toggle and a remove action — shown directly below
  /// the task dropdown, separate from the already-assigned checklist below.
  Widget _buildPendingTasksList() {
    final pending = _viewModel.pendingTasks;
    if (pending.isEmpty) return const SizedBox.shrink();

    return Column(
      children: [
        for (var i = 0; i < pending.length; i++) ...[
          _PendingTaskCard(
            index: i + 1,
            assignment: pending[i],
            onRemove: () => _viewModel.removePendingTask(pending[i]),
            onScheduledTodayChanged: (scheduledToday) =>
                _viewModel.setPendingAssignmentType(
                  pending[i],
                  scheduledToday ? 'temporary' : 'default',
                ),
            onNumericChanged: (value) =>
                _viewModel.setPendingNumericValue(pending[i], value),
            onNoteChanged: (note) =>
                _viewModel.setPendingNote(pending[i], note),
          ),
          if (i != pending.length - 1) const SizedBox(height: 10),
        ],
        if (_viewModel.hasSelection) SizedBox(height: 15),
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

class _AssignedTasksSection extends StatelessWidget {
  final List<WorkerTaskCompletion> completions;
  final int completedCount;
  final int totalCount;
  final void Function(WorkerTaskCompletion completion, bool isCompleted)
  onCompletionChanged;

  const _AssignedTasksSection({
    required this.completions,
    required this.completedCount,
    required this.totalCount,
    required this.onCompletionChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const SectionLabel('ASSIGNED TASKS'),
            Text(
              '$completedCount of $totalCount completed',
              style: const TextStyle(fontSize: 12.5, color: AppColors.muted),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: totalCount == 0 ? 0 : completedCount / totalCount,
            minHeight: 6,
            backgroundColor: const Color(0xFFEFEFEF),
            color: AppColors.deepGreen,
          ),
        ),
        const SizedBox(height: 12),
        if (completions.isEmpty)
          const Text(
            'No tasks assigned yet — pick one above.',
            style: TextStyle(fontSize: 13, color: AppColors.muted),
          ),
        for (var i = 0; i < completions.length; i++) ...[
          _TaskChecklistCard(
            index: i + 1,
            completion: completions[i],
            onCompletionChanged: (isCompleted) =>
                onCompletionChanged(completions[i], isCompleted),
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }
}

/// A task picked in the dropdown above but not assigned yet — no
/// completion data exists for it until [AssignTaskViewModel.save] actually
/// assigns it, so it gets a lighter card (no Is Completed/Verify controls)
/// with just a numeric value field, a note field, a Scheduled-for-today
/// toggle, and a remove action.
class _PendingTaskCard extends StatefulWidget {
  final int index;
  final PendingTaskAssignment assignment;
  final VoidCallback onRemove;
  final ValueChanged<bool> onScheduledTodayChanged;
  final ValueChanged<double?> onNumericChanged;
  final ValueChanged<String> onNoteChanged;

  const _PendingTaskCard({
    required this.index,
    required this.assignment,
    required this.onRemove,
    required this.onScheduledTodayChanged,
    required this.onNumericChanged,
    required this.onNoteChanged,
  });

  @override
  State<_PendingTaskCard> createState() => _PendingTaskCardState();
}

class _PendingTaskCardState extends State<_PendingTaskCard> {
  late final TextEditingController _numericController;
  late final TextEditingController _noteController;

  @override
  void initState() {
    super.initState();
    _numericController = TextEditingController(
      text: widget.assignment.numericValue?.toString() ?? '',
    )..addListener(_onNumericTextChanged);
    _noteController = TextEditingController(text: widget.assignment.note)
      ..addListener(_onNoteTextChanged);
  }

  void _onNumericTextChanged() {
    widget.onNumericChanged(double.tryParse(_numericController.text.trim()));
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
    final index = widget.index;
    final assignment = widget.assignment;
    final onRemove = widget.onRemove;
    final onScheduledTodayChanged = widget.onScheduledTodayChanged;
    final task = assignment.task;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 22,
                height: 22,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0xFFFDF3E3),
                ),
                child: Text(
                  '$index',
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.warning,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  task.name,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.ink,
                  ),
                ),
              ),
              if (assignment.isAlreadyAssigned)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    'Assigned',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppColors.success,
                    ),
                  ),
                )
              else
                IconButton(
                  icon: const Icon(Icons.close, size: 18, color: AppColors.muted),
                  tooltip: 'Remove',
                  onPressed: onRemove,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Scheduled task as',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.slate,
                ),
              ),
              _AssignmentTypeToggle(
                isTemporary: assignment.assignmentType == 'temporary',
                onChanged: onScheduledTodayChanged,
              ),
            ],
          ),
          const SizedBox(height: 10),
          AppFormField(
            label: 'Quantity',
            hint: 'Enter a numeric value',
            icon: Icons.numbers,
            controller: _numericController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
          ),
          const SizedBox(height: 10),
          AppFormField(
            label: 'Note',
            hint: 'Add a note for this task',
            icon: Icons.notes_outlined,
            controller: _noteController,
            minLines: 2,
            maxLines: 3,
          ),
        ],
      ),
    );
  }
}

/// "Default" (assignment_type = 'default' — a standing assignment) vs
/// "Today" (assignment_type = 'temporary' — today only) — each
/// _PendingTaskCard's own toggle, so one task's choice never affects
/// another's.
class _AssignmentTypeToggle extends StatelessWidget {
  final bool isTemporary;
  final ValueChanged<bool> onChanged;

  const _AssignmentTypeToggle({
    required this.isTemporary,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _pill('Default', !isTemporary, () => onChanged(false)),
        const SizedBox(width: 8),
        _pill('Today', isTemporary, () => onChanged(true)),
      ],
    );
  }

  Widget _pill(String label, bool isSelected, VoidCallback onTap) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.deepGreen : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? AppColors.deepGreen : AppColors.cardBorder,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: isSelected ? Colors.white : AppColors.ink,
          ),
        ),
      ),
    );
  }
}

class _TaskChecklistCard extends StatefulWidget {
  final int index;
  final WorkerTaskCompletion completion;
  final ValueChanged<bool> onCompletionChanged;

  const _TaskChecklistCard({
    required this.index,
    required this.completion,
    required this.onCompletionChanged,
  });

  @override
  State<_TaskChecklistCard> createState() => _TaskChecklistCardState();
}

class _TaskChecklistCardState extends State<_TaskChecklistCard> {
  // Not backed by any stored field yet — this app doesn't have a separate
  // "supervisor verified" concept beyond completion + sync, so this toggle
  // is UI-only for now and resets to No (unverified) whenever this card is
  // rebuilt from fresh data (e.g. reopening the screen).
  bool _isVerified = false;

  @override
  Widget build(BuildContext context) {
    final completion = widget.completion;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 22,
                height: 22,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: completion.isCompleted
                      ? const Color(0xFFE7F6EC)
                      : const Color(0xFFF2F3F2),
                ),
                child: Text(
                  '${widget.index}',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: completion.isCompleted
                        ? AppColors.success
                        : AppColors.muted,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  completion.taskName,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.ink,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _YesNoRow(
            label: 'Is Completed',
            value: completion.isCompleted,
            onChanged: widget.onCompletionChanged,
          ),
          const SizedBox(height: 10),
          _YesNoRow(
            label: 'Verify',
            value: _isVerified,
            onChanged: (value) => setState(() => _isVerified = value),
          ),
        ],
      ),
    );
  }
}

/// A label paired with a Yes/No pill toggle — one row of a
/// [_TaskChecklistCard].
class _YesNoRow extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _YesNoRow({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppColors.slate,
          ),
        ),
        _YesNoToggle(value: value, onChanged: onChanged),
      ],
    );
  }
}

/// A compact two-pill Yes/No toggle — same look as
/// task_status_screen.dart's own toggle, kept as a separate copy here since
/// this screen's checklist card layout differs from that screen's row.
class _YesNoToggle extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;

  const _YesNoToggle({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _pill('Yes', value, () => onChanged(true)),
        const SizedBox(width: 8),
        _pill('No', !value, () => onChanged(false)),
      ],
    );
  }

  Widget _pill(String label, bool isSelected, VoidCallback onTap) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.deepGreen : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? AppColors.deepGreen : AppColors.cardBorder,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: isSelected ? Colors.white : AppColors.ink,
          ),
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final String label;
  final Color color;
  final Color background;

  const _StatusPill({
    required this.label,
    required this.color,
    required this.background,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

/// Explains why the Day Details block above it has nothing to show yet,
/// instead of that section just silently disappearing.
/// Describes this app's actual offline-first storage — every section above
/// is a live read of the local database regardless of sync state.
class _OfflineNote extends StatelessWidget {
  const _OfflineNote();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.save_outlined, size: 14, color: AppColors.muted),
        const SizedBox(width: 6),
        const Expanded(
          child: Text(
            'Saved on this device. Changes will upload when a connection '
            'is available.',
            style: TextStyle(fontSize: 11.5, color: AppColors.muted),
          ),
        ),
      ],
    );
  }
}
