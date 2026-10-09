import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/models/department_model.dart';
import '../../../data/models/worker_task_model.dart';
import '../../common/widgets/common_widgets.dart';
import '../viewmodel/worker_task_list_viewmodel.dart';

/// Read-only list of a worker's assigned tasks — reached from the worker
/// list's "View" action, and shown right after that worker checks in.
class WorkerTaskListScreen extends StatefulWidget {
  final int workerId;
  final String workerName;

  /// Overridable so tests can inject a fake, avoiding the real DatabaseHelper.
  final WorkerTaskListViewModel? viewModel;

  const WorkerTaskListScreen({
    super.key,
    required this.workerId,
    required this.workerName,
    this.viewModel,
  });

  @override
  State<WorkerTaskListScreen> createState() => _WorkerTaskListScreenState();
}

class _WorkerTaskListScreenState extends State<WorkerTaskListScreen> {
  late final WorkerTaskListViewModel _viewModel;

  @override
  void initState() {
    super.initState();
    _viewModel =
        widget.viewModel ?? WorkerTaskListViewModel(workerId: widget.workerId);
    _viewModel.load();
  }

  @override
  void dispose() {
    _viewModel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.pageGrey,
      body: Column(
        children: [
          AppScreenHeader(
            title: 'Assigned Tasks',
            subtitle: widget.workerName,
            showBack: true,
          ),
          Expanded(
            child: ListenableBuilder(
              listenable: _viewModel,
              builder: (context, _) => _buildBody(),
            ),
          ),
          // Same as the header's back arrow: pops this screen if it can. No
          // bottomNavigationBar here, so this button — unlike one that sits
          // above AppBottomNavBar — needs its own clearance from the system
          // navigation bar/gesture area.
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: AppSecondaryButton(
                label: 'Go Back',
                onPressed: () => Navigator.maybePop(context),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_viewModel.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_viewModel.tasks.isEmpty) {
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
        AppCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (final task in _viewModel.tasks) ...[
                ListTile(
                  leading: const Icon(
                    Icons.task_alt_outlined,
                    color: AppColors.deepGreen,
                  ),
                  title: Text(task.taskName),
                  subtitle: _taskSubtitle(task),
                ),
                if (task != _viewModel.tasks.last)
                  const Divider(height: 1, color: AppColors.cardBorder),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// The target/rate line, then the saved note if there is one.
Widget? _taskSubtitle(WorkerTask task) {
  final targetRate = _targetRateText(task);
  final note = task.taskNote?.trim();
  final hasNote = note != null && note.isNotEmpty;
  if (targetRate == null && !hasNote) return null;
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      if (targetRate != null)
        Text(targetRate, style: const TextStyle(color: AppColors.slate)),
      if (hasNote)
        Text('Note: $note', style: const TextStyle(color: AppColors.slate)),
    ],
  );
}

/// "Target: X" for [task], or null when there's no target to show. Only
/// Task Based and Hourly tasks carry a completion target — Daily/Monthly
/// tasks have none to report here.
String? _targetRateText(WorkerTask task) {
  final showsTarget =
      task.taskType == TaskType.taskBased.name ||
      task.taskType == TaskType.hourBased.name;
  final parts = [
    if (showsTarget && task.taskTarget != null) 'Target: ${task.taskTarget}',
  ];
  return parts.isEmpty ? null : parts.join(' · ');
}
