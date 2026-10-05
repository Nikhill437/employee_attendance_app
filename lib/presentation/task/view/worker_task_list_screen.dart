import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
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
                  subtitle: _targetRateText(task) == null
                      ? null
                      : Text(
                          _targetRateText(task)!,
                          style: const TextStyle(color: AppColors.slate),
                        ),
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

/// "Target: X · Rate: Y" for [task], or null when neither is set. Matches
/// the format the Assign Task screen uses.
String? _targetRateText(WorkerTask task) {
  final parts = [
    if (task.taskTarget != null) 'Target: ${task.taskTarget}',
    if (task.taskRate != null) 'Rate: ${task.taskRate}',
  ];
  return parts.isEmpty ? null : parts.join(' · ');
}
