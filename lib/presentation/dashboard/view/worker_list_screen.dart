import 'package:flutter/material.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/routes/app_routes.dart';
import '../../../core/routes/section_navigation.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/app_time.dart';
import '../../../core/utils/date_time_formatter.dart';
import '../../../data/models/worker_model.dart';
import '../../auth/view/mark_attendance_screen.dart';
import '../../employee/view/enrollment_form_screen.dart';
import '../../common/widgets/common_widgets.dart';
import '../../history/view/worker_history_screen.dart';
import '../../history/view/worker_profile_screen.dart';
import '../../task/view/assign_task_screen.dart';
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

  /// Whether this tap should send only the worker's profile change. That
  /// applies to a non-Pending worker with a pending department or type change
  /// whose attendance can't go yet (not checked out, or the task isn't
  /// Approved/Rejected).
  bool _isProfileOnlySync(Worker worker) {
    if (worker.status == 'pending') return false;
    if (!worker.hasPendingDepartmentOrTypeChange) return false;
    final attendanceReady =
        worker.hasCheckedOutToday &&
        (worker.taskStatus == 'approved' || worker.taskStatus == 'rejected');
    return !attendanceReady;
  }

  /// Pushes a single worker to the backend — the sync endpoint only takes
  /// one worker per call, so this runs per-card rather than as a bulk
  /// "sync everyone" action.
  Future<void> _syncWorker(Worker worker) async {
    final messenger = ScaffoldMessenger.of(context);
    final error = await _viewModel.syncWorker(
      worker.employeeId,
      worker.workerId,
      status: worker.status,
      profileOnly: _isProfileOnlySync(worker),
    );
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

  /// Opens [worker]'s Day Details/assign-task screen — always reachable,
  /// even with nothing assigned yet or no check-in today, since that's
  /// exactly where a supervisor assigns a worker's first task from. Only
  /// needs a real local record to assign against.
  Future<void> _openTasks(Worker worker) async {
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
          employeeId: worker.employeeId,
          department: worker.department,
          initialDepartmentId: worker.departmentId,
        ),
      ),
    );
    if (assigned == true && mounted) await _viewModel.load();
  }

  /// Opens the same face-scan attendance flow used by the public kiosk
  /// screen, pre-filled for [worker] — see
  /// MarkAttendanceScreen.initialEmployeeId. Reloads the list on success so
  /// the card picks up the new check-in/check-out state.
  ///
  /// Passes [Worker.remoteEmployeeId] (the numeric `employee_id`), not
  /// [Worker.employeeId] (their National ID) — the attendance login flow
  /// (see AuthRepository) matches on `employee_id`, same as when a worker
  /// types it themselves on the public kiosk screen. The button that calls
  /// this is already hidden until `remoteEmployeeId` is set (see the
  /// `_WorkerCard` construction below), so this is just a safety net.
  Future<void> _openMarkAttendance(Worker worker) async {
    final employeeId = worker.remoteEmployeeId;
    if (employeeId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'This worker has no employee ID to mark attendance with',
          ),
        ),
      );
      return;
    }
    await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) =>
            MarkAttendanceScreen(initialEmployeeId: employeeId.toString()),
      ),
    );
    // Reload however the screen was left, so the card's Check In/Check Out
    // button reflects today's attendance right away.
    if (mounted) await _viewModel.load();
  }

  /// Opens [worker]'s own attendance/task/sync report — falls back to the
  /// all-workers Reports screen for the rare row with no local record (e.g.
  /// a `Worker` not backed by a real DB row), since there's no per-day
  /// history to key a per-worker report off without one. Reloads the list
  /// on a truthy pop — the report screen's Edit icon pops `true` after a
  /// successful department change, so the card picks up the new
  /// department/"Not synced" state immediately.
  Future<void> _openWorkerReport(Worker worker) async {
    final workerId = worker.workerId;
    if (workerId == null) {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const WorkerHistoryScreen()),
      );
      return;
    }
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => WorkerReportScreen(
          workerId: workerId,
          workerName: worker.name,
          employeeId: worker.employeeId,
          department: worker.department,
          remoteWorkerId: worker.remoteWorkerId,
          remoteEmployeeId: worker.remoteEmployeeId,
          status: worker.status,
        ),
      ),
    );
    if (changed == true && mounted) await _viewModel.load();
  }

  /// Opens the enrollment form in edit mode for a Pending [worker]. The
  /// full local record is read first, so the form pre-fills with the saved
  /// values. Reloads the list when the edit was saved.
  Future<void> _openEditWorker(Worker worker) async {
    final employee = await _viewModel.getEmployee(worker.employeeId);
    if (!mounted || employee == null) return;
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => EnrollmentFormScreen(editingWorker: employee),
      ),
    );
    if (saved == true && mounted) await _viewModel.load();
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
        SnackBar(
          content: Text(
            'Could not fetch workers: ${ApiException.messageFor(e)}',
          ),
        ),
      );
    }
  }

  Widget _buildHeader() {
    return AppScreenHeader(
      title: 'Employee List',
      subtitle: 'Today, ${DateTimeFormatter.dayLabel(AppTime.nowInUserZone())}',
      titleOverride: _isSearching ? _buildSearchField() : null,
      actions: [
        CircleHeaderAction(
          icon: Icons.add,
          onPressed: _enrollWorker,
          tooltip: 'Enroll employee',
        ),
        CircleHeaderAction(
          icon: _isSearching ? Icons.close : Icons.search,
          onPressed: _toggleSearch,
          tooltip: _isSearching ? 'Clear search' : 'Search employee',
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
        hintText: 'Search name, National ID or employee ID',
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
            checkedIn: _viewModel.presentCount,
            synced: _viewModel.syncedCount,
            notSynced: _viewModel.notSyncedCount,
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
              // Delete is offered only while the worker is Pending. Approved
              // and Rejected workers can't be swiped away.
              direction: worker.status == 'pending'
                  ? DismissDirection.endToStart
                  : DismissDirection.none,
              confirmDismiss: (_) => _confirmDeleteWorker(worker),
              onDismissed: (_) => _deleteWorker(worker),
              background: _buildDeleteBackground(),
              child: _WorkerCard(
                worker: worker,
                isSyncing: _viewModel.isSyncing(worker.employeeId),
                onSync: () => _syncWorker(worker),
                onViewTasks: () => _openTasks(worker),
                onMarkAttendance: () => _openMarkAttendance(worker),
                onOpenWorkerReport: () => _openWorkerReport(worker),
                onEdit: () => _openEditWorker(worker),
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

/// Total / checked-in / synced / not-synced headcounts, split by hairline
/// dividers.
class _SummaryCard extends StatelessWidget {
  final int total;
  final int checkedIn;
  final int synced;
  final int notSynced;

  const _SummaryCard({
    required this.total,
    required this.checkedIn,
    required this.synced,
    required this.notSynced,
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
            // Expanded(
            //   child: _SummaryTile(
            //     label: 'CHECKED IN',
            //     value: checkedIn,
            //     color: AppColors.success,
            //   ),
            // ),
            // const VerticalDivider(width: 1, color: AppColors.cardBorder),
            Expanded(
              child: _SummaryTile(
                label: 'SYNCED',
                value: synced,
                color: AppColors.deepGreen,
              ),
            ),
            const VerticalDivider(width: 1, color: AppColors.cardBorder),
            Expanded(
              child: _SummaryTile(
                label: 'NOT SYNCED',
                value: notSynced,
                color: AppColors.warning,
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
        Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.4,
            color: AppColors.muted,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '$value',
          style: TextStyle(
            fontSize: 20,
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
  final VoidCallback onViewTasks;
  final VoidCallback onMarkAttendance;
  final VoidCallback onOpenWorkerReport;
  final VoidCallback onEdit;

  const _WorkerCard({
    required this.worker,
    required this.isSyncing,
    required this.onSync,
    required this.onViewTasks,
    required this.onMarkAttendance,
    required this.onOpenWorkerReport,
    required this.onEdit,
  });

  // A bespoke container instead of the shared AppCard — a soft shadow (in
  // place of AppCard's flat border-only look) and a touch more corner
  // radius read as a more polished, "raised" card, scoped to this widget
  // alone so nothing elsewhere in the app that uses AppCard is affected.
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.cardBorder),
        boxShadow: [
          BoxShadow(
            color: AppColors.ink.withValues(alpha: 0.04),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Avatar(worker: worker),
              const SizedBox(width: 12),
              Expanded(child: _buildIdentity()),
              const SizedBox(width: 8),
              // Edit is offered only while the worker is Pending and not yet
              // synced (s_sync 0). Approved and Rejected workers' details are
              // locked, and a synced Pending worker can't be edited.
              if ((worker.status == 'pending' && !worker.isSynced) ||
                  worker.status == 'rejected')
                IconButton(
                  tooltip: 'Edit worker',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.edit_outlined, size: 17),
                  onPressed: onEdit,
                ),
              _buildAttendance(),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1, color: AppColors.cardBorder),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _StatusText(prefix: 'Employee Task Status: '),
              _StatusText(
                label: _taskStatusLabel,
                color: _taskStatusColor,
                showDot: true,
                alignEnd: true,
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1, color: AppColors.cardBorder),
          const SizedBox(height: 12),
          _buildSyncRow(),
          const SizedBox(height: 12),
          _buildActionButtons(),
        ],
      ),
    );
  }

  /// Whether [worker] is truly all-caught-up right now — their own profile
  /// ([Worker.isSynced]) AND, if they've checked in today, today's
  /// attendance too ([Worker.isAttendanceSynced]). Blending both is what
  /// keeps this pill/button honest: a Verified worker's profile flag no
  /// longer flips on check-in/checkout (see
  /// DatabaseHelper.recordWorkerScan), so profile-only [Worker.isSynced]
  /// alone would keep showing "Synced" all day even with a fresh,
  /// unsynced checkout sitting in `worker_attendance`.
  bool get _effectiveSynced => worker.isFullySynced;

  /// The NOT SYNCED / SYNCED button is tappable only when the worker isn't
  /// synced yet, today's checkout is recorded, and today's task status is
  /// Approved or Rejected. A Pending task status (or no task row today)
  /// keeps it disabled.
  bool get _canTapSync {
    if (_effectiveSynced) return false;
    // A Pending worker can sync without a checkout or task status.
    if (worker.status == 'pending') return true;
    // Checked in but not out yet: nothing to sync until checkout.
    if (worker.status == 'approved' &&
        worker.hasCheckedInToday &&
        !worker.hasCheckedOutToday) {
      return false;
    }
    // An unsynced department or enrollment-type change can always sync. If
    // the attendance can't go yet, only the profile change is sent.
    if (worker.hasPendingDepartmentOrTypeChange) return true;
    // Approved, no check-in today: the checkout/task-status rule below only
    // protects *today's* cycle, which doesn't exist yet here. Having reached
    // this line unsynced with nothing happening today means a previous day's
    // record is still pending, and the Approved sync path below already
    // pushes every unsynced day, not just today's.
    if (worker.status == 'approved' && !worker.hasCheckedInToday) return true;
    final taskStatus = worker.taskStatus;
    return worker.hasCheckedOutToday &&
        (taskStatus == 'approved' || taskStatus == 'rejected');
  }

  /// Once today's attendance has both a check-in and a check-out, there's
  /// nothing left for this button to do today, so it's hidden. A worker who
  /// has only checked in still sees "Check out". Both flags come from
  /// today's `worker_attendance` record (see WorkerListViewModel.load).
  bool get _hideMarkAttendance =>
      worker.hasCheckedInToday && worker.hasCheckedOutToday;

  Widget _buildSyncRow() {
    final effectiveSynced = _effectiveSynced;
    return Row(
      children: [
        Icon(
          Icons.circle,
          size: 8,
          color: effectiveSynced ? AppColors.success : AppColors.warning,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Last Synced Time',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.muted,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                worker.syncedAt == null
                    ? 'Never'
                    : effectiveSynced
                    ? DateTimeFormatter.clock(worker.syncedAt!)
                    : DateTimeFormatter.clock(worker.syncedAt!),
                style: const TextStyle(fontSize: 13, color: Colors.black),
              ),
            ],
          ),
        ),
        if (isSyncing)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 10),
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          )
        else
          ElevatedButton(
            onPressed: _canTapSync ? onSync : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: effectiveSynced
                  ? AppColors.deepGreen
                  : AppColors.warning,
              // Disabled gets its own grey, same chrome used elsewhere for a
              // disabled action — distinct from the enabled green/amber above.
              disabledBackgroundColor: const Color(0xFFF2F3F2),
              foregroundColor: Colors.white,
              disabledForegroundColor: AppColors.muted,
              elevation: 0,
              minimumSize: const Size(0, 34),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              textStyle: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
            child: Text(effectiveSynced ? 'Synced' : 'Not synced'),
          ),
      ],
    );
  }

  /// The three actions every card offers. The middle button shows "Check
  /// in" before the worker's first scan, then "Check out" from then on,
  /// including after they've already checked out once — a worker can be
  /// checked out multiple times in a day (see
  /// DatabaseHelper.recordWorkerScan, which always re-stamps
  /// `check_out_time` on every scan after the first), so it never disables
  /// just because today's attendance is already "complete". It does
  /// disappear once that complete day has actually been pushed to the
  /// backend, though — see [_hideMarkAttendance].
  ///
  /// When the Check In/Check Out button is hidden, it's left out of the row
  /// entirely (no empty slot or spacing), so View tasks and Employee report
  /// share the full width.
  Widget _buildActionButtons() {
    return Row(
      children: [
        Expanded(child: _buildViewTasksButton()),
        const SizedBox(width: 8),
        if (!_hideMarkAttendance) ...[
          Expanded(child: _buildMarkAttendanceButton()),
          const SizedBox(width: 8),
        ],
        Expanded(child: _buildWorkerReportButton()),
      ],
    );
  }

  static const _actionButtonPadding = EdgeInsets.symmetric(
    vertical: 9,
    horizontal: 4,
  );
  static const _actionButtonTextStyle = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w600,
  );

  /// Whether the worker's three action buttons should be tappable at all —
  /// they stay disabled until the backend has approved this worker,
  /// regardless of what else each button's own logic would otherwise allow.
  bool get _isApproved => worker.status == 'approved';

  Widget _buildViewTasksButton() {
    return OutlinedButton(
      onPressed: _isApproved ? onViewTasks : null,
      style: OutlinedButton.styleFrom(
        backgroundColor: AppColors.deepGreen,
        foregroundColor: Colors.white,
        disabledBackgroundColor: const Color(0xFFF2F3F2),
        disabledForegroundColor: AppColors.muted,
        side: BorderSide(
          color: _isApproved ? AppColors.deepGreen : AppColors.cardBorder,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        padding: _actionButtonPadding,
        textStyle: _actionButtonTextStyle,
      ),
      // Icon above the label, both centered.
      child: const Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(Icons.search, size: 16),
          SizedBox(height: 4),
          Text(
            'View tasks',
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildMarkAttendanceButton() {
    final label = worker.hasCheckedInToday ? 'Check out' : 'Check in';
    final icon = worker.hasCheckedInToday ? Icons.logout : Icons.login;
    return OutlinedButton(
      onPressed: _isApproved ? onMarkAttendance : null,
      style: OutlinedButton.styleFrom(
        backgroundColor: const Color(0xFFE7F6EC),
        foregroundColor: AppColors.deepGreen,
        disabledBackgroundColor: const Color(0xFFF2F3F2),
        disabledForegroundColor: AppColors.muted,
        side: BorderSide.none,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        padding: _actionButtonPadding,
        textStyle: _actionButtonTextStyle,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(icon, size: 16),
          SizedBox(height: 4),
          Text(
            label,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildWorkerReportButton() {
    return OutlinedButton(
      onPressed: _isApproved ? onOpenWorkerReport : null,
      style: OutlinedButton.styleFrom(
        backgroundColor: Colors.white,
        foregroundColor: AppColors.deepGreen,
        disabledBackgroundColor: const Color(0xFFF2F3F2),
        disabledForegroundColor: AppColors.muted,
        side: const BorderSide(color: AppColors.cardBorder),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        padding: _actionButtonPadding,
        textStyle: _actionButtonTextStyle,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(Icons.grid_view_outlined, size: 16),
          SizedBox(height: 4),
          Text(
            'Employee profile',
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
          ),
        ],
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
          // remoteEmployeeId (the backend's employee_id, distinct from
          // National ID and from the local workerId) is only populated
          // once this worker's been imported/synced from the server —
          // shown as an em dash rather than left blank until then. Falls
          // back to the placeholder role for records enrolled before the
          // department field existed.
          '${worker.remoteEmployeeId?.toString() ?? '—'} • ${worker.department?.isNotEmpty == true ? worker.department : worker.role}',
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 13,
            color: AppColors.muted,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 6),
        PayTypeChip(payType: worker.payType),
      ],
    );
  }

  Widget _buildAttendance() {
    // Derived from today's worker_attendance row (hasCheckedInToday/
    // hasCheckedOutToday), not the legacy attendance_logs-based
    // `worker.attendance`/`isPresent` — that flag only records a single
    // login for the day and never turns back off, so it kept reading
    // "Checked in" even after a worker had already checked out.
    final label = worker.hasCheckedOutToday
        ? 'Checked out'
        : worker.hasCheckedInToday
        ? 'Checked in'
        : 'Not checked in';
    final isActive = worker.hasCheckedInToday && !worker.hasCheckedOutToday;
    final foreground = isActive
        ? AppColors.success
        : worker.hasCheckedOutToday
        ? AppColors.deepGreen
        : AppColors.danger;
    final background = isActive
        ? const Color(0xFFE7F6EC)
        : worker.hasCheckedOutToday
        ? const Color(0xFFEFF6F0)
        : const Color(0xFFFDECEC);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        _Pill(label: label, foreground: foreground, background: background),
        const SizedBox(height: 8),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.access_time, size: 14, color: AppColors.muted),
            const SizedBox(width: 4),
            Text(
              worker.displayAttendanceAt == null
                  ? 'N/A'
                  : DateTimeFormatter.clock(worker.displayAttendanceAt!),
              style: const TextStyle(fontSize: 12.5, color: AppColors.muted),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _StatusText(
          label: _workerStatusLabel,
          color: _workerStatusColor,
          showDot: worker.status != 'approved',
          alignEnd: true,
        ),
      ],
    );
  }

  Color get _workStatusColor => switch (worker.workStatus) {
    WorkStatus.completed => AppColors.success,
    WorkStatus.inProgress => AppColors.warning,
    WorkStatus.notStarted => AppColors.muted,
  };

  /// The worker's own backend approval state (`workers.status`, via
  /// [Worker.status]) — distinct from [Worker.verification], which is a
  /// pure sync-state indicator. Sourced directly from what the last server
  /// fetch stored, so an approved worker reads "Approved" immediately after
  /// that fetch rather than falling back to "Pending".
  String get _workerStatusLabel => switch (worker.status) {
    'approved' => 'Approved',
    'rejected' => 'Rejected',
    _ => 'Pending',
  };

  Color get _workerStatusColor => switch (worker.status) {
    'approved' => AppColors.success,
    'rejected' => AppColors.danger,
    _ => AppColors.warning,
  };

  /// The worker's current active task assignment's own approve/reject/
  /// pending verdict (`worker_tasks.task_status`, via [Worker.taskStatus])
  /// — 'Pending' both for an explicit 'pending' verdict and for no active
  /// assignment at all, since there's nothing else useful to show either
  /// way.
  String get _taskStatusLabel => switch (worker.taskStatus) {
    'approved' => 'Approved',
    'rejected' => 'Rejected',
    _ => 'Pending',
  };

  Color get _taskStatusColor => switch (worker.taskStatus) {
    'approved' => AppColors.success,
    'rejected' => AppColors.danger,
    _ => AppColors.warning,
  };
}

class _Avatar extends StatelessWidget {
  final Worker worker;

  const _Avatar({required this.worker});

  @override
  Widget build(BuildContext context) {
    final present = worker.isPresent;
    final ringColor = present ? AppColors.success : AppColors.cardBorder;
    return Container(
      width: 48,
      height: 48,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: ringColor, width: 2),
      ),
      child: Container(
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
  final String? label;
  final Color? color;
  final bool? showDot;
  final bool alignEnd;

  const _StatusText({
    this.prefix,
    this.label,
    this.color,
    this.showDot,
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
        if (showDot != null) ...[
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
  final AttendanceFilter? status;

  const _FilterChoice(this.label, this.status);
}

class _AttendanceFilterSheet extends StatelessWidget {
  const _AttendanceFilterSheet();

  static const List<_FilterChoice> _choices = [
    _FilterChoice('All workers', null),
    _FilterChoice('Check In', AttendanceFilter.checkIn),
    _FilterChoice('Check Out', AttendanceFilter.checkOut),
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
