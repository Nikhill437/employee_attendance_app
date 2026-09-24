import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/models/department_model.dart';
import '../../common/widgets/common_widgets.dart';
import '../viewmodel/assign_task_viewmodel.dart';

/// Supervisor screen: pick a department, then pick one or more of its
/// tasks to assign to one worker. Changing department clears the task
/// selection and reloads that department's own tasks/existing assignments.
class AssignTaskScreen extends StatefulWidget {
  final int workerId;
  final String workerName;

  /// Pre-selects this department in the dropdown if it's one of the
  /// options — normally the worker's own enrolled department.
  final int? initialDepartmentId;

  /// Overridable so tests can inject a fake, avoiding the real DatabaseHelper.
  final AssignTaskViewModel? viewModel;

  const AssignTaskScreen({
    super.key,
    required this.workerId,
    required this.workerName,
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.pageGrey,
      body: Column(
        children: [
          AppScreenHeader(
            title: 'Assign Task',
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
    if (_viewModel.isLoadingDepartments) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            children: [
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
              const SizedBox(height: 18),
              _buildSelectedTasks(),
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

  Widget _buildSelectedTasks() {
    final tasks = _viewModel.selectedTasks;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionLabel('SELECTED TASKS'),
        const SizedBox(height: 10),
        if (tasks.isEmpty)
          const Text(
            'No tasks selected yet',
            style: TextStyle(fontSize: 13, color: AppColors.muted),
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final task in tasks)
                Chip(
                  label: Text(task.name),
                  deleteIcon: const Icon(Icons.close, size: 16),
                  onDeleted: () => _viewModel.removeTask(task),
                  backgroundColor: const Color(0xFFE7F6EC),
                  labelStyle: const TextStyle(
                    color: AppColors.deepGreen,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                  side: BorderSide.none,
                ),
            ],
          ),
      ],
    );
  }
}
