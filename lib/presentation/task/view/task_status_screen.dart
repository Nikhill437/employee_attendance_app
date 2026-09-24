import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/models/worker_task_completion_model.dart';
import '../../common/widgets/common_widgets.dart';
import '../viewmodel/task_status_viewmodel.dart';

/// Checkout-time screen: the worker's assigned tasks for today, each with
/// a Yes/No toggle the supervisor sets to record whether it was completed.
/// Toggles only change what's on screen — Save is what writes them to
/// `worker_task_completion`, all at once.
///
/// [readOnly] switches this to a plain status display, with no toggles and
/// no Save button — for the worker's own self-service checkout (public
/// kiosk flow, mark_attendance_screen.dart with no supervisor involved),
/// which shows whatever Yes/No the supervisor already set but never lets
/// the worker change it themselves.
class TaskStatusScreen extends StatefulWidget {
  final int workerId;
  final String workerName;
  final int attendanceId;
  final bool readOnly;

  /// Overridable so tests can inject a fake, avoiding the real DatabaseHelper.
  final TaskStatusViewModel? viewModel;

  const TaskStatusScreen({
    super.key,
    required this.workerId,
    required this.workerName,
    required this.attendanceId,
    this.readOnly = false,
    this.viewModel,
  });

  @override
  State<TaskStatusScreen> createState() => _TaskStatusScreenState();
}

class _TaskStatusScreenState extends State<TaskStatusScreen> {
  late final TaskStatusViewModel _viewModel;

  @override
  void initState() {
    super.initState();
    _viewModel =
        widget.viewModel ??
        TaskStatusViewModel(
          workerId: widget.workerId,
          attendanceId: widget.attendanceId,
        );
    _viewModel.load();
  }

  @override
  void dispose() {
    _viewModel.dispose();
    super.dispose();
  }

  /// On success, pops this screen — for the checkout flow reached from
  /// worker_list_screen.dart (via MarkAttendanceScreen), that's what lets
  /// its already-built "supervisor-initiated" pop cascade land back on the
  /// worker list, same as it does for the rest of that flow (see
  /// MarkAttendanceScreen._showTaskScreenIfNeeded/_finish). Reached from
  /// elsewhere (e.g. worker_history_screen.dart's "Tasks" button), popping
  /// just returns to wherever this was opened from, which is still correct.
  /// On failure, stays put with an error so the supervisor can retry.
  Future<void> _save() async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final succeeded = await _viewModel.save();
    if (!mounted) return;
    if (succeeded) {
      navigator.pop(true);
      return;
    }
    messenger.showSnackBar(
      const SnackBar(
        content: Text('Could not save some task statuses — try again'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.pageGrey,
      body: Column(
        children: [
          AppScreenHeader(
            title: 'Task Status',
            subtitle: '${widget.workerName} — Checkout',
            showBack: true,
          ),
          Expanded(
            child: ListenableBuilder(
              listenable: _viewModel,
              builder: (context, _) => _buildBody(),
            ),
          ),
          if (!widget.readOnly)
            ListenableBuilder(
              listenable: _viewModel,
              builder: (context, _) =>
                  !_viewModel.isLoading && _viewModel.completions.isNotEmpty
                  ? Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: AppPrimaryButton(
                        label: 'Save',
                        icon: Icons.save_outlined,
                        isBusy: _viewModel.isSaving,
                        onPressed: _save,
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_viewModel.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_viewModel.completions.isEmpty) {
      return const Center(
        child: Text(
          'No tasks assigned yet',
          style: TextStyle(color: AppColors.muted),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        for (final completion in _viewModel.completions) ...[
          _TaskStatusCard(
            completion: completion,
            readOnly: widget.readOnly,
            onChanged: (isCompleted) =>
                _viewModel.setCompletion(completion, isCompleted),
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class _TaskStatusCard extends StatelessWidget {
  final WorkerTaskCompletion completion;
  final bool readOnly;
  final ValueChanged<bool> onChanged;

  const _TaskStatusCard({
    required this.completion,
    required this.readOnly,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Text(
              completion.taskName,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AppColors.ink,
              ),
            ),
          ),
          const SizedBox(width: 12),
          readOnly
              ? _StatusBadge(isCompleted: completion.isCompleted)
              : _YesNoToggle(value: completion.isCompleted, onChanged: onChanged),
        ],
      ),
    );
  }
}

/// The read-only equivalent of [_YesNoToggle] — a single pill showing
/// whatever the supervisor already set, with no way to change it.
class _StatusBadge extends StatelessWidget {
  final bool isCompleted;

  const _StatusBadge({required this.isCompleted});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: isCompleted ? AppColors.deepGreen : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isCompleted ? AppColors.deepGreen : AppColors.cardBorder,
        ),
      ),
      child: Text(
        isCompleted ? 'Yes' : 'No',
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: isCompleted ? Colors.white : AppColors.ink,
        ),
      ),
    );
  }
}

/// A compact two-pill Yes/No toggle for one row — [AppOptionSelector]
/// always renders its own label line above the pills, which leaves an
/// awkward gap when used inline like this.
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
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: isSelected ? Colors.white : AppColors.ink,
          ),
        ),
      ),
    );
  }
}
