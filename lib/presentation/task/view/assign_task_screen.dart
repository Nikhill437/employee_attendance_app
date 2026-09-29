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

  /// Pre-selects this department in the dropdown if it's one of the
  /// options — normally the worker's own enrolled department.
  final int? initialDepartmentId;

  /// Overridable so tests can inject a fake, avoiding the real DatabaseHelper.
  final AssignTaskViewModel? viewModel;

  const AssignTaskScreen({
    super.key,
    required this.workerId,
    required this.workerName,
    this.employeeId,
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
    _viewModel.loadDepartments();
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
      SnackBar(
        content: Text(error ?? 'Task status saved successfully'),
      ),
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
    final departmentName = _viewModel.selectedDepartment?.name;
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
    if (_viewModel.isLoadingDepartments) {
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
              AppDropdownField<Department>(
                label: 'Department',
                isRequired: true,
                hint: 'Select department',
                icon: Icons.apartment_outlined,
                value: _viewModel.selectedDepartment,
                items: _viewModel.departments,
                labelBuilder: (department) => department.name,
                onChanged: (department) =>
                    _viewModel.selectDepartment(department),
                validator: (department) =>
                    department == null ? 'Select a department' : null,
              ),
              const SizedBox(height: 18),
              _buildTaskPicker(),
              const SizedBox(height: 20),
              const Divider(height: 1, color: AppColors.cardBorder),
              const SizedBox(height: 18),
              if (!_viewModel.isLoadingDayDetails) ..._buildDayDetails(),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
          child: AppPrimaryButton(
            label: 'Assign Task',
            isBusy: _viewModel.isSaving,
            onPressed: _viewModel.hasSelection ? _save : null,
          ),
        ),
      ],
    );
  }

  /// The Day Details section: today's attendance, sync status, and the
  /// worker's tasks (today's tracked checklist plus whatever's currently
  /// selected above but not yet saved) — always shown, never hidden behind
  /// a data-availability check, so the layout doesn't shift around
  /// depending on what's been recorded yet.
  List<Widget> _buildDayDetails() {
    final attendance = _viewModel.todayAttendance;
    final completions = _viewModel.todayTaskCompletions;
    final completionTaskIds = completions.map((c) => c.taskId).toSet();
    final pendingTasks = _viewModel.selectedTasks
        .where((task) => !completionTaskIds.contains(task.id))
        .toList();

    return [
      // _AttendanceSection(
      //   attendance: attendance,
      //   isSyncingAttendance: _viewModel.isSyncingAttendance,
      //   onRetrySync: _retryAttendanceSync,
      // ),
      // const SizedBox(height: 20),
      _AssignedTasksSection(
        completions: completions,
        pendingTasks: pendingTasks,
        completedCount: _viewModel.completedTaskCount,
        totalCount: _viewModel.totalTaskCount,
        onCompletionChanged: (completion, isCompleted) =>
            _viewModel.setTaskCompletion(completion, isCompleted),
        onRemovePending: _viewModel.removeTask,
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
    if (_viewModel.selectedDepartment == null) {
      return _buildDisabledTaskField('Select Department First');
    }
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
      key: ValueKey(_viewModel.selectedTasks.length),
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

/// Today's check-in/check-out, an "on site" duration, and a status pill.
// class _AttendanceSection extends StatelessWidget {
//   /// Null before the worker has checked in today — every value below falls
//   /// back to a neutral placeholder rather than the whole section
//   /// disappearing.
//   final WorkerAttendanceRecord? attendance;
//   final bool isSyncingAttendance;
//   final VoidCallback onRetrySync;

//   const _AttendanceSection({
//     required this.attendance,
//     required this.isSyncingAttendance,
//     required this.onRetrySync,
//   });

//   @override
//   Widget build(BuildContext context) {
//     final record = attendance;
//     return Column(
//       crossAxisAlignment: CrossAxisAlignment.start,
//       children: [
//         Row(
//           mainAxisAlignment: MainAxisAlignment.spaceBetween,
//           children: [
//             const SectionLabel('ATTENDANCE'),
//             _StatusPill(
//               label: _statusLabel,
//               color: _statusColor,
//               background: _statusBackground,
//             ),
//           ],
//         ),
//         const SizedBox(height: 10),
//         Row(
//           children: [
//             Expanded(
//               child: _AttendanceTile(
//                 icon: Icons.login,
//                 label: 'Check in',
//                 time: record?.checkInTime,
//                 subtitle: record == null
//                     ? 'Not checked in yet'
//                     : record.checkInFaceVerified
//                     ? 'Face verified'
//                     : 'Not verified',
//               ),
//             ),
//             const SizedBox(width: 10),
//             Expanded(
//               child: _AttendanceTile(
//                 icon: Icons.logout,
//                 label: 'Check out',
//                 time: record?.checkOutTime,
//                 subtitle: record == null
//                     ? 'Not checked in yet'
//                     : record.checkOutTime == null
//                     ? 'Shift currently active'
//                     : record.checkOutFaceVerified
//                     ? 'Face verified'
//                     : 'Not verified',
//               ),
//             ),
//           ],
//         ),
//         if (record?.hasCheckedIn ?? false) ...[
//           const SizedBox(height: 10),
//           Row(
//             children: [
//               const Icon(
//                 Icons.timer_outlined,
//                 size: 15,
//                 color: AppColors.muted,
//               ),
//               const SizedBox(width: 6),
//               Text(
//                 _durationLabel,
//                 style: const TextStyle(fontSize: 12.5, color: AppColors.muted),
//               ),
//             ],
//           ),
//         ],
//         const SizedBox(height: 12),
//         _SyncStatusRow(
//           attendance: record,
//           isSyncing: isSyncingAttendance,
//           onRetry: onRetrySync,
//         ),
//       ],
//     );
//   }

//   String get _statusLabel {
//     final record = attendance;
//     if (record == null || !record.hasCheckedIn) return 'Not checked in';
//     if (!record.hasCheckedOut) return 'On site';
//     return 'Checked out';
//   }

//   Color get _statusColor =>
//       attendance != null &&
//           attendance!.hasCheckedIn &&
//           !attendance!.hasCheckedOut
//       ? AppColors.success
//       : AppColors.deepGreen;
//   Color get _statusBackground =>
//       attendance != null &&
//           attendance!.hasCheckedIn &&
//           !attendance!.hasCheckedOut
//       ? const Color(0xFFE7F6EC)
//       : const Color(0xFFEFF6F0);

//   String get _durationLabel {
//     final record = attendance;
//     if (record == null) return '';
//     final checkIn = DateTime.tryParse(record.checkInTime ?? '');
//     if (checkIn == null) return '';
//     final checkOut = DateTime.tryParse(record.checkOutTime ?? '');
//     final end = checkOut ?? AppTime.nowInUserZone();
//     final duration = end.difference(checkIn);
//     final hours = duration.inHours;
//     final minutes = duration.inMinutes.remainder(60);
//     return '${hours}h ${minutes}m on site';
//   }
// }

/// A single always-visible line describing whether today's attendance has
/// reached the backend — replaces a banner that used to appear and
/// disappear depending on sync state, which made the layout feel
/// inconsistent.
// class _SyncStatusRow extends StatelessWidget {
//   final WorkerAttendanceRecord? attendance;
//   final bool isSyncing;
//   final VoidCallback onRetry;

//   const _SyncStatusRow({
//     required this.attendance,
//     required this.isSyncing,
//     required this.onRetry,
//   });

//   @override
//   Widget build(BuildContext context) {
//     final record = attendance;
//     if (record == null) {
//       return const Row(
//         children: [
//           Icon(Icons.cloud_outlined, size: 16, color: AppColors.muted),
//           SizedBox(width: 8),
//           Text(
//             'No attendance to sync yet',
//             style: TextStyle(fontSize: 12.5, color: AppColors.muted),
//           ),
//         ],
//       );
//     }

//     if (record.isSynced) {
//       return const Row(
//         children: [
//           Icon(Icons.cloud_done_outlined, size: 16, color: AppColors.success),
//           SizedBox(width: 8),
//           Text(
//             'Daily data synced',
//             style: TextStyle(
//               fontSize: 12.5,
//               fontWeight: FontWeight.w600,
//               color: AppColors.success,
//             ),
//           ),
//         ],
//       );
//     }

//     return Row(
//       children: [
//         const Icon(
//           Icons.cloud_off_outlined,
//           size: 16,
//           color: AppColors.warning,
//         ),
//         const SizedBox(width: 8),
//         const Expanded(
//           child: Text(
//             'Daily data not synced',
//             style: TextStyle(
//               fontSize: 12.5,
//               fontWeight: FontWeight.w600,
//               color: AppColors.warning,
//             ),
//           ),
//         ),
//         if (isSyncing)
//           const SizedBox(
//             width: 16,
//             height: 16,
//             child: CircularProgressIndicator(strokeWidth: 2),
//           )
//         else
//           GestureDetector(
//             onTap: onRetry,
//             child: const Text(
//               'Retry',
//               style: TextStyle(
//                 fontSize: 12.5,
//                 fontWeight: FontWeight.w700,
//                 color: AppColors.warning,
//                 decoration: TextDecoration.underline,
//               ),
//             ),
//           ),
//       ],
//     );
//   }
// }

// class _AttendanceTile extends StatelessWidget {
//   final IconData icon;
//   final String label;
//   final String? time;
//   final String subtitle;

//   const _AttendanceTile({
//     required this.icon,
//     required this.label,
//     required this.time,
//     required this.subtitle,
//   });

//   @override
//   Widget build(BuildContext context) {
//     return Container(
//       padding: const EdgeInsets.all(12),
//       decoration: BoxDecoration(
//         color: const Color(0xFFE7F6EC),
//         borderRadius: BorderRadius.circular(12),
//       ),
//       child: Column(
//         crossAxisAlignment: CrossAxisAlignment.start,
//         children: [
//           Row(
//             children: [
//               Icon(icon, size: 15, color: AppColors.deepGreen),
//               const SizedBox(width: 6),
//               Text(
//                 label,
//                 style: const TextStyle(
//                   fontSize: 12.5,
//                   fontWeight: FontWeight.w600,
//                   color: AppColors.deepGreen,
//                 ),
//               ),
//             ],
//           ),
//           const SizedBox(height: 8),
//           Text(
//             time == null ? '—' : DateTimeFormatter.clock(DateTime.parse(time!)),
//             style: const TextStyle(
//               fontSize: 16,
//               fontWeight: FontWeight.w700,
//               color: AppColors.ink,
//             ),
//           ),
//           const SizedBox(height: 4),
//           Text(
//             subtitle,
//             overflow: TextOverflow.ellipsis,
//             style: const TextStyle(fontSize: 11.5, color: AppColors.muted),
//           ),
//         ],
//       ),
//     );
//   }
// }

/// Shown when today's attendance row hasn't reached the backend yet — a
/// Retry button that pushes it via `POST attendance/check-in`.
/// Today's assigned tasks with a completion progress bar. Each card's "Is
/// Completed" toggle writes straight to `worker_task_completion` (the same
/// record task_status_screen.dart's own Yes/No toggle sets); "Verify" has
/// no backing field yet, so it's UI-only for now (see
/// _TaskChecklistCardState._isVerified).
class _AssignedTasksSection extends StatelessWidget {
  final List<WorkerTaskCompletion> completions;

  /// Tasks currently selected in the picker above that aren't part of
  /// [completions] yet — either newly picked this visit, or previously
  /// assigned but with nothing recorded for today yet. Shown here too, as
  /// "Pending", so picking a task from the dropdown shows up in this
  /// section immediately instead of only after Save.
  final List<Task> pendingTasks;
  final int completedCount;
  final int totalCount;
  final void Function(WorkerTaskCompletion completion, bool isCompleted)
  onCompletionChanged;
  final ValueChanged<Task> onRemovePending;

  const _AssignedTasksSection({
    required this.completions,
    required this.pendingTasks,
    required this.completedCount,
    required this.totalCount,
    required this.onCompletionChanged,
    required this.onRemovePending,
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
        if (completions.isEmpty && pendingTasks.isEmpty)
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
        for (var i = 0; i < pendingTasks.length; i++) ...[
          _PendingTaskCard(
            index: completions.length + i + 1,
            task: pendingTasks[i],
            onRemove: () => onRemovePending(pendingTasks[i]),
          ),
          if (i != pendingTasks.length - 1) const SizedBox(height: 10),
        ],
      ],
    );
  }
}

/// A task picked in the dropdown above but not saved yet — no completion
/// data exists for it until [AssignTaskViewModel.save] actually assigns
/// it, so it gets a lighter card (no Is Completed/Verify controls) with
/// just a remove action.
class _PendingTaskCard extends StatelessWidget {
  final int index;
  final Task task;
  final VoidCallback onRemove;

  const _PendingTaskCard({
    required this.index,
    required this.task,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Row(
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
                const SizedBox(height: 2),
                const Text(
                  'Pending — tap Assign Task to save',
                  style: TextStyle(fontSize: 11.5, color: AppColors.warning),
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
