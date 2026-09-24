import 'package:flutter/material.dart';

import '../../../core/routes/app_routes.dart';
import '../../../core/routes/section_navigation.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/date_time_formatter.dart';
import '../../../data/models/worker_model.dart';
import '../../auth/view/mark_attendance_screen.dart';
import '../../common/widgets/common_widgets.dart';
import '../../employee/view/enrollment_form_screen.dart';
import '../../task/view/assign_task_screen.dart';
import '../../task/view/worker_task_list_screen.dart';
import '../viewmodel/worker_list_viewmodel.dart';

class WorkerListScreen extends StatefulWidget {
  final WorkerListViewModel? viewModel;

  const WorkerListScreen({super.key, this.viewModel});

  @override
  State<WorkerListScreen> createState() => _WorkerListScreenState();
}

class _WorkerListScreenState extends State<WorkerListScreen> {
  late final WorkerListViewModel _viewModel;
  late final bool _ownsViewModel;

  bool _isSearching = false;

  @override
  void initState() {
    super.initState();
    _ownsViewModel = widget.viewModel == null;
    _viewModel = widget.viewModel ?? WorkerListViewModel();
    _viewModel.load();
  }

  @override
  void dispose() {
    if (_ownsViewModel) _viewModel.dispose();
    super.dispose();
  }

  void _toggleSearch() {
    setState(() => _isSearching = !_isSearching);
    if (!_isSearching) _viewModel.search('');
  }

  Future<void> _pickAttendanceFilter() async {
    final selected = await showModalBottomSheet<_FilterChoice>(
      context: context,
      builder: (context) => const _AttendanceFilterSheet(),
    );
    if (selected == null) return;
    _viewModel.filterByAttendance(selected.status);
  }

  /// Opens enrollment, reloading the roster if a worker was added.
  Future<void> _enrollWorker() async {
    await Navigator.pushNamed(context, AppRoutes.enrollmentForm);
    await _viewModel.load();
  }

  /// Confirms before removing a worker — deletion also clears their
  /// attendance history, so it isn't reversible.
  Future<bool> _confirmDeleteWorker(Worker worker) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete worker?'),
        content: Text(
          'This removes ${worker.name} and their attendance history. '
          'This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  Future<void> _deleteWorker(Worker worker) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await _viewModel.deleteWorker(worker.employeeId);
      messenger.showSnackBar(SnackBar(content: Text('${worker.name} removed')));
    } catch (e) {
      await _viewModel.load();
      messenger.showSnackBar(
        SnackBar(content: Text('Could not delete ${worker.name}: $e')),
      );
    }
  }

  /// Pushes a single worker to the backend — the sync endpoint only takes
  /// one worker per call, so this runs per-card rather than as a bulk
  /// "sync everyone" action.
  Future<void> _syncWorker(Worker worker) async {
    final messenger = ScaffoldMessenger.of(context);
    final error = await _viewModel.syncWorker(worker.employeeId);
    if (!mounted) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          error == null
              ? '${worker.name} synced'
              : 'Could not sync ${worker.name}: $error',
        ),
      ),
    );
  }

  /// Opens task assignment for [worker] — needs their department, so this
  /// is a no-op (with an explanatory snackbar) for the rare row missing
  /// one (e.g. a `Worker` not backed by a real DB record).
  Future<void> _openAssignTask(Worker worker) async {
    if (worker.workerId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This worker has no record to assign to')),
      );
      return;
    }
    final assigned = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => AssignTaskScreen(
          workerId: worker.workerId!,
          workerName: worker.name,
          initialDepartmentId: worker.departmentId,
        ),
      ),
    );
    if (assigned == true && mounted) await _viewModel.load();
  }

  /// Pushes [worker]'s task assignments to the backend — the endpoint only
  /// takes one assignment per call, so this pushes each of the worker's
  /// assigned tasks in turn (see TaskSyncRepository.syncWorkerTasks).
  Future<void> _syncTasks(Worker worker) async {
    final workerId = worker.workerId;
    if (workerId == null) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final result = await _viewModel.syncTasks(worker.employeeId, workerId);
      if (!mounted || result == null) return;
      final message = result.total == 0
          ? 'No tasks to sync for ${worker.name}'
          : result.hasFailures
          ? 'Synced ${result.succeeded} of ${result.total} tasks for '
                '${worker.name} — ${result.failed.length} failed'
          : 'Synced ${result.succeeded} task(s) for ${worker.name}';
      messenger.showSnackBar(SnackBar(content: Text(message)));
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Could not sync tasks for ${worker.name}: $e')),
      );
    }
  }

  /// Pushes [worker]'s pending (Yes or No) task completions to the backend.
  Future<void> _syncTaskCompletion(Worker worker) async {
    final workerId = worker.workerId;
    if (workerId == null) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final result = await _viewModel.syncTaskCompletion(
        worker.employeeId,
        workerId,
      );
      if (!mounted || result == null) return;
      final message = result.total == 0
          ? 'No task completions to sync for ${worker.name}'
          : result.hasFailures
          ? 'Synced ${result.succeeded} of ${result.total} task completions '
                'for ${worker.name} — ${result.total - result.succeeded} failed'
          : 'Synced ${result.succeeded} task completion(s) for ${worker.name}';
      messenger.showSnackBar(SnackBar(content: Text(message)));
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Could not sync task completions for ${worker.name}: $e',
          ),
        ),
      );
    }
  }

  Future<void> _openWorkerTasks(Worker worker) async {
    if (worker.workerId == null) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => WorkerTaskListScreen(
          workerId: worker.workerId!,
          workerName: worker.name,
        ),
      ),
    );
  }

  /// Opens the enrollment form in edit mode for [worker] — only its
  /// Department can actually change there (see EnrollmentFormScreen).
  /// Available regardless of [WorkerListViewModel.canManageTasks], since
  /// editing a worker's department isn't a task action.
  Future<void> _openEditWorker(Worker worker) async {
    final employee = await _viewModel.getEmployee(worker.employeeId);
    if (!mounted || employee == null) return;
    final updated = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => EnrollmentFormScreen(editingWorker: employee),
      ),
    );
    if (updated == true) await _viewModel.load();
  }

  /// Opens the same face-scan attendance flow used by the public kiosk
  /// screen, pre-filled for [worker] — see
  /// MarkAttendanceScreen.initialEmployeeId. Reloads the list on success so
  /// the card picks up the new check-in/check-out state.
  Future<void> _openMarkAttendance(Worker worker) async {
    final marked = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) =>
            MarkAttendanceScreen(initialEmployeeId: worker.employeeId),
      ),
    );
    if (marked == true && mounted) await _viewModel.load();
  }

  /// Pushes [worker]'s today's check-in/check-out record to the backend
  /// (`POST attendance/check-in`).
  Future<void> _syncAttendance(Worker worker) async {
    final workerId = worker.workerId;
    if (workerId == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final error = await _viewModel.syncAttendance(worker.employeeId, workerId);
    if (!mounted) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          error == null
              ? '${worker.name}\'s attendance synced'
              : 'Could not sync ${worker.name}\'s attendance: $error',
        ),
      ),
    );
  }

  /// Fetches the full worker roster from the backend — existing workers
  /// matched by National ID are updated, new ones inserted (see
  /// DatabaseHelper.upsertRemoteWorkers).
  Future<void> _fetchFromServer() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final count = await _viewModel.fetchFromServer();
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Fetched $count workers from server')),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Could not fetch workers: $e')),
      );
    }
  }

  Widget _buildHeader() {
    return AppScreenHeader(
      title: 'Worker List',
      subtitle: 'Today, ${DateTimeFormatter.dayLabel(DateTime.now())}',
      titleOverride: _isSearching ? _buildSearchField() : null,
      actions: [
        CircleHeaderAction(
          icon: _isSearching ? Icons.close : Icons.search,
          onPressed: _toggleSearch,
          tooltip: _isSearching ? 'Clear search' : 'Search workers',
        ),
        CircleHeaderAction(
          icon: Icons.filter_alt_outlined,
          onPressed: _pickAttendanceFilter,
          tooltip: 'Filter by attendance',
        ),
        _viewModel.isFetchingFromServer
            ? const Padding(
                padding: EdgeInsets.all(10),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                ),
              )
            : CircleHeaderAction(
                icon: Icons.cloud_download_outlined,
                onPressed: _fetchFromServer,
                tooltip: 'Fetch workers from server',
              ),
      ],
    );
  }

  Widget _buildSearchField() {
    return TextField(
      autofocus: true,
      onChanged: _viewModel.search,
      style: const TextStyle(color: Colors.white),
      decoration: const InputDecoration(
        isDense: true,
        hintText: 'Search name or ID',
        hintStyle: TextStyle(color: Colors.white54),
        enabledBorder: UnderlineInputBorder(
          borderSide: BorderSide(color: Colors.white54),
        ),
        focusedBorder: UnderlineInputBorder(
          borderSide: BorderSide(color: Colors.white),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.pageGrey,
      body: ListenableBuilder(
        listenable: _viewModel,
        builder: (context, _) => Column(
          children: [
            _buildHeader(),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _enrollWorker,
        backgroundColor: AppColors.deepGreen,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text(
          'Enroll Worker',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      bottomNavigationBar: AppBottomNavBar(
        current: AppSection.workers,
        onSectionSelected: (target) =>
            switchToSection(context, AppSection.workers, target),
      ),
    );
  }

  Widget _buildBody() {
    if (_viewModel.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return RefreshIndicator(
      onRefresh: _viewModel.load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          _SummaryCard(
            total: _viewModel.total,
            present: _viewModel.presentCount,
            absent: _viewModel.absentCount,
          ),
          const SizedBox(height: 16),
          if (_viewModel.workers.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 48),
              child: Center(
                child: Text(
                  'No workers to show',
                  style: TextStyle(color: AppColors.muted),
                ),
              ),
            ),
          for (final worker in _viewModel.workers) ...[
            Dismissible(
              key: ValueKey(worker.employeeId),
              direction: DismissDirection.endToStart,
              confirmDismiss: (_) => _confirmDeleteWorker(worker),
              onDismissed: (_) => _deleteWorker(worker),
              background: _buildDeleteBackground(),
              child: _WorkerCard(
                worker: worker,
                isSyncing: _viewModel.isSyncing(worker.employeeId),
                onSync: () => _syncWorker(worker),
                onAssignTask: () => _openAssignTask(worker),
                onViewTasks: () => _openWorkerTasks(worker),
                isSyncingTasks: _viewModel.isSyncingTasks(worker.employeeId),
                onSyncTasks: () => _syncTasks(worker),
                canManageTasks: _viewModel.canManageTasks(worker),
                onEdit: () => _openEditWorker(worker),
                onMarkAttendance: () => _openMarkAttendance(worker),
                isSyncingAttendance: _viewModel.isSyncingAttendance(
                  worker.employeeId,
                ),
                onSyncAttendance: () => _syncAttendance(worker),
                isSyncingTaskCompletion: _viewModel.isSyncingTaskCompletion(
                  worker.employeeId,
                ),
                onSyncTaskCompletion: () => _syncTaskCompletion(worker),
              ),
            ),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }

  Widget _buildDeleteBackground() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      alignment: Alignment.centerRight,
      decoration: BoxDecoration(
        color: AppColors.danger,
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Icon(Icons.delete_outline, color: Colors.white),
    );
  }
}

/// Total / present / absent headcounts, split by hairline dividers.
class _SummaryCard extends StatelessWidget {
  final int total;
  final int present;
  final int absent;

  const _SummaryCard({
    required this.total,
    required this.present,
    required this.absent,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: IntrinsicHeight(
        child: Row(
          children: [
            Expanded(
              child: _SummaryTile(
                label: 'TOTAL',
                value: total,
                color: AppColors.ink,
              ),
            ),
            const VerticalDivider(width: 1, color: AppColors.cardBorder),
            Expanded(
              child: _SummaryTile(
                label: 'PRESENT',
                value: present,
                color: AppColors.success,
              ),
            ),
            const VerticalDivider(width: 1, color: AppColors.cardBorder),
            Expanded(
              child: _SummaryTile(
                label: 'ABSENT',
                value: absent,
                color: AppColors.danger,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryTile extends StatelessWidget {
  final String label;
  final int value;
  final Color color;

  const _SummaryTile({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SectionLabel(label),
        const SizedBox(height: 6),
        Text(
          '$value',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ],
    );
  }
}

/// One worker: identity on top, work and verification state underneath.
class _WorkerCard extends StatelessWidget {
  final Worker worker;
  final bool isSyncing;
  final VoidCallback onSync;
  final VoidCallback onAssignTask;
  final VoidCallback onViewTasks;
  final bool isSyncingTasks;
  final VoidCallback onSyncTasks;

  /// Whether Assign/View/Sync Task should show at all — approved status
  /// and matching the supervisor's own department, both required (see
  /// WorkerListViewModel.canManageTasks).
  final bool canManageTasks;
  final VoidCallback onEdit;
  final VoidCallback onMarkAttendance;
  final bool isSyncingAttendance;
  final VoidCallback onSyncAttendance;
  final bool isSyncingTaskCompletion;
  final VoidCallback onSyncTaskCompletion;

  const _WorkerCard({
    required this.worker,
    required this.isSyncing,
    required this.onSync,
    required this.onAssignTask,
    required this.onViewTasks,
    required this.isSyncingTasks,
    required this.onSyncTasks,
    required this.canManageTasks,
    required this.onEdit,
    required this.onMarkAttendance,
    required this.isSyncingAttendance,
    required this.onSyncAttendance,
    required this.isSyncingTaskCompletion,
    required this.onSyncTaskCompletion,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Avatar(worker: worker),
              const SizedBox(width: 12),
              Expanded(child: _buildIdentity()),
              const SizedBox(width: 4),
              Tooltip(
                message: 'Edit department',
                child: IconButton(
                  onPressed: onEdit,
                  icon: const Icon(
                    Icons.edit_outlined,
                    size: 18,
                    color: AppColors.muted,
                  ),
                  constraints: const BoxConstraints(),
                  padding: const EdgeInsets.all(4),
                ),
              ),
              const SizedBox(width: 4),
              _buildAttendance(),
            ],
          ),
          const Divider(height: 22, color: AppColors.cardBorder),
          _buildFooter(),
          // Gated on approval alone — unlike Assign/View/Sync Task, marking
          // attendance isn't department-scoped, so it doesn't need
          // canManageTasks' department match too.
          if (worker.status == 'approved') ...[
            const Divider(height: 18, color: AppColors.cardBorder),
            _buildMarkAttendanceAction(),
          ],
          if (canManageTasks) ...[
            const Divider(height: 18, color: AppColors.cardBorder),
            _buildTaskActions(),
            _buildTaskCompletionSyncAction(),
          ],
        ],
      ),
    );
  }

  /// Before today's first scan: "Check In". After that, until the second
  /// scan: "Check Out". Once both are recorded there's nothing left to mark
  /// today, so the button is disabled (tapping it again would just leave
  /// the row unchanged — see WorkerScanOutcome.alreadyCheckedOut).
  Widget _buildMarkAttendanceAction() {
    final isComplete = worker.hasCheckedInToday && worker.hasCheckedOutToday;
    final label = !worker.hasCheckedInToday
        ? 'Check In'
        : !worker.hasCheckedOutToday
        ? 'Check Out'
        : 'Attendance Complete';

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: isComplete ? null : onMarkAttendance,
              icon: const Icon(Icons.fingerprint, size: 16),
              label: Text(label),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.deepGreen,
                side: const BorderSide(color: AppColors.cardBorder),
                padding: const EdgeInsets.symmetric(vertical: 8),
                textStyle: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          // Nothing to push to the server until at least a check-in exists.
          if (worker.hasCheckedInToday) ...[
            const SizedBox(width: 8),
            _buildAttendanceSyncAction(),
          ],
        ],
      ),
    );
  }

  /// Enabled/disabled by whether today's row already has the backend's
  /// real `attendance_id` (see Worker.hasRealAttendanceIdToday) — not by
  /// `isAttendanceSynced` alone, since a sync attempt can mark the row
  /// synced without the response actually returning a usable id (see
  /// DatabaseHelper.markWorkerAttendanceSynced), in which case this stays
  /// tappable so it can be retried.
  Widget _buildAttendanceSyncAction() {
    if (isSyncingAttendance) {
      return const Padding(
        padding: EdgeInsets.all(8),
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    return Tooltip(
      message: worker.hasRealAttendanceIdToday
          ? 'Attendance synced'
          : 'Sync attendance to server',
      child: IconButton(
        onPressed: worker.hasRealAttendanceIdToday ? null : onSyncAttendance,
        icon: Icon(
          worker.hasRealAttendanceIdToday
              ? Icons.cloud_done_outlined
              : Icons.cloud_upload_outlined,
          size: 20,
          color: worker.hasRealAttendanceIdToday
              ? AppColors.success
              : AppColors.deepGreen,
        ),
        constraints: const BoxConstraints(),
        padding: const EdgeInsets.all(8),
      ),
    );
  }

  Widget _buildTaskActions() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: onAssignTask,
              icon: const Icon(Icons.playlist_add, size: 16),
              label: const Text('Assign Task'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.deepGreen,
                side: const BorderSide(color: AppColors.cardBorder),
                padding: const EdgeInsets.symmetric(vertical: 8),
                textStyle: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Tooltip(
            message: 'View assigned tasks',
            child: IconButton(
              onPressed: onViewTasks,
              icon: const Icon(
                Icons.visibility_outlined,
                size: 20,
                color: AppColors.deepGreen,
              ),
              constraints: const BoxConstraints(),
              padding: const EdgeInsets.all(8),
            ),
          ),
          const SizedBox(width: 4),
          if (isSyncingTasks)
            const Padding(
              padding: EdgeInsets.all(8),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            Tooltip(
              message: 'Sync tasks to server',
              child: IconButton(
                onPressed: onSyncTasks,
                icon: const Icon(
                  Icons.cloud_sync_outlined,
                  size: 20,
                  color: AppColors.deepGreen,
                ),
                constraints: const BoxConstraints(),
                padding: const EdgeInsets.all(8),
              ),
            ),
        ],
      ),
    );
  }

  /// Pushes the worker's task-completion rows (Yes or No) recorded on
  /// task_status_screen.dart to the backend — separate from
  /// [_buildTaskActions]'s "Sync tasks" (which syncs the *assignment*,
  /// `worker_tasks`) since this syncs the *completion*,
  /// `worker_task_completion`.
  Widget _buildTaskCompletionSyncAction() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: isSyncingTaskCompletion ? null : onSyncTaskCompletion,
          icon: isSyncingTaskCompletion
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.fact_check_outlined, size: 16),
          label: Text(
            isSyncingTaskCompletion
                ? 'Syncing Task Completion...'
                : 'Sync Task Completion',
          ),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.deepGreen,
            side: const BorderSide(color: AppColors.cardBorder),
            padding: const EdgeInsets.symmetric(vertical: 8),
            textStyle: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildIdentity() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          worker.name,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: AppColors.ink,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          // Falls back to the placeholder role for records enrolled before
          // the department field existed.
          '${worker.employeeId} • ${worker.department?.isNotEmpty == true ? worker.department : worker.role}',
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 13, color: AppColors.muted),
        ),
        const SizedBox(height: 6),
        PayTypeChip(payType: worker.payType),
      ],
    );
  }

  Widget _buildAttendance() {
    final present = worker.isPresent;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        _Pill(
          label: worker.attendance.label,
          foreground: present ? AppColors.success : AppColors.danger,
          background: present
              ? const Color(0xFFE7F6EC)
              : const Color(0xFFFDECEC),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.access_time, size: 14, color: AppColors.muted),
            const SizedBox(width: 4),
            Text(
              worker.checkInAt == null
                  ? 'N/A'
                  : DateTimeFormatter.clock(worker.checkInAt!),
              style: const TextStyle(fontSize: 12.5, color: AppColors.muted),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildFooter() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: _StatusText(
              prefix: 'Work: ',
              label: worker.workStatus.label,
              color: _workColor,
              showDot: worker.workStatus != WorkStatus.completed,
            ),
          ),
          const SizedBox(width: 8),
          // Flexible (not Expanded) so the verification label is the one
          // that ellipsizes if space is tight — the sync pill next to it
          // stays a fixed, always-fully-visible tap target.
          Flexible(
            child: _StatusText(
              label: worker.verification.label,
              color: _verificationColor,
              showDot: worker.verification != VerificationStatus.verified,
              alignEnd: true,
            ),
          ),
          const SizedBox(width: 10),
          _SyncIndicator(
            isSyncing: isSyncing,
            isSynced: worker.isSynced,
            onTap: onSync,
          ),
        ],
      ),
    );
  }

  Color get _workColor => switch (worker.workStatus) {
    WorkStatus.completed => AppColors.success,
    WorkStatus.inProgress => AppColors.warning,
    WorkStatus.notStarted => AppColors.muted,
  };

  Color get _verificationColor => switch (worker.verification) {
    VerificationStatus.verified => AppColors.success,
    VerificationStatus.pending => AppColors.warning,
    VerificationStatus.rejected => AppColors.danger,
    VerificationStatus.notVerified => AppColors.muted,
  };
}

/// Small per-card tap target that pushes that one worker to the backend —
/// a spinner while the sync is in flight, then a "Synced" pill once it has
/// (still tappable, to push again). Reuses [_Pill]'s look for visual
/// consistency with the attendance pill above it.
class _SyncIndicator extends StatelessWidget {
  final bool isSyncing;
  final bool isSynced;
  final VoidCallback onTap;

  const _SyncIndicator({
    required this.isSyncing,
    required this.isSynced,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (isSyncing) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 4),
        child: SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    return Tooltip(
      message: isSynced ? 'Synced — tap to sync again' : 'Sync worker',
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: _Pill(
          label: isSynced ? 'SYNCED' : 'NOT SYNCED',
          foreground: isSynced ? AppColors.success : AppColors.deepGreen,
          background: isSynced
              ? const Color(0xFFE7F6EC)
              : const Color(0xFFEFF6F0),
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  final Worker worker;

  const _Avatar({required this.worker});

  @override
  Widget build(BuildContext context) {
    final present = worker.isPresent;
    return Container(
      width: 44,
      height: 44,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: present ? const Color(0xFFE7F6EC) : const Color(0xFFEFEFEF),
      ),
      child: Text(
        worker.initials,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: present ? AppColors.deepGreen : AppColors.muted,
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final String label;
  final Color foreground;
  final Color background;

  const _Pill({
    required this.label,
    required this.foreground,
    required this.background,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w700,
          color: foreground,
        ),
      ),
    );
  }
}

/// A footer status, optionally preceded by a coloured dot.
class _StatusText extends StatelessWidget {
  final String? prefix;
  final String label;
  final Color color;
  final bool showDot;
  final bool alignEnd;

  const _StatusText({
    this.prefix,
    required this.label,
    required this.color,
    required this.showDot,
    this.alignEnd = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: alignEnd
          ? MainAxisAlignment.end
          : MainAxisAlignment.start,
      children: [
        if (showDot) ...[
          Icon(Icons.circle, size: 9, color: color),
          const SizedBox(width: 6),
        ],
        Flexible(
          child: Text.rich(
            TextSpan(
              children: [
                if (prefix != null)
                  TextSpan(
                    text: prefix,
                    style: const TextStyle(color: AppColors.slate),
                  ),
                TextSpan(
                  text: label,
                  style: TextStyle(color: color, fontWeight: FontWeight.w700),
                ),
              ],
            ),
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13.5),
          ),
        ),
      ],
    );
  }
}

/// One option in the attendance filter sheet.
class _FilterChoice {
  final String label;
  final AttendanceStatus? status;

  const _FilterChoice(this.label, this.status);
}

class _AttendanceFilterSheet extends StatelessWidget {
  const _AttendanceFilterSheet();

  static const List<_FilterChoice> _choices = [
    _FilterChoice('All workers', null),
    _FilterChoice('Present only', AttendanceStatus.present),
    _FilterChoice('Absent only', AttendanceStatus.absent),
  ];

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final choice in _choices)
            ListTile(
              title: Text(choice.label),
              onTap: () => Navigator.pop(context, choice),
            ),
        ],
      ),
    );
  }
}
