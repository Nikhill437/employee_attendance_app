import 'package:flutter/material.dart';

import '../../../core/routes/app_routes.dart';
import '../../../core/routes/section_navigation.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/date_time_formatter.dart';
import '../../../data/models/dashboard_summary_model.dart';
import '../../../data/models/employee_model.dart';
import '../../common/widgets/common_widgets.dart';
import '../viewmodel/dashboard_viewmodel.dart';

class DashboardScreen extends StatefulWidget {
  final DashboardViewModel? viewModel;

  const DashboardScreen({super.key, this.viewModel});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late final DashboardViewModel _viewModel;
  late final bool _ownsViewModel;

  @override
  void initState() {
    super.initState();
    _ownsViewModel = widget.viewModel == null;
    _viewModel = widget.viewModel ?? DashboardViewModel();
    _viewModel.load();
  }

  @override
  void dispose() {
    if (_ownsViewModel) _viewModel.dispose();
    super.dispose();
  }

  /// Fetches the full worker roster from the backend and upserts it
  /// locally by National ID.
  Future<void> _importWorkers() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final count = await _viewModel.importWorkersFromServer();
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

  Future<void> _fetchDepartments() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final count = await _viewModel.fetchDepartments();
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Fetched $count departments from server')),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Could not fetch departments: $e')),
      );
    }
  }

  Future<void> _fetchTasks() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final count = await _viewModel.fetchTasks();
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Fetched $count tasks from server')),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Could not fetch tasks: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.pageGrey,
      body: SafeArea(
        child: ListenableBuilder(
          listenable: _viewModel,
          builder: (context, _) => RefreshIndicator(
            onRefresh: _viewModel.load,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              children: [
                const _DashboardHeader(),
                const SizedBox(height: 24),
                _QuickActions(
                  onEnroll: () =>
                      Navigator.pushNamed(context, AppRoutes.enrollmentForm),
                  onViewWorkers: () =>
                      Navigator.pushNamed(context, AppRoutes.workerList),
                ),
                const SizedBox(height: 14),
                _ImportWorkersCard(
                  isImporting: _viewModel.isImportingWorkers,
                  onPressed: _importWorkers,
                ),
                const SizedBox(height: 14),
                _RefreshLookupsCard(
                  isFetchingDepartments: _viewModel.isFetchingDepartments,
                  isFetchingTasks: _viewModel.isFetchingTasks,
                  onFetchDepartments: _fetchDepartments,
                  onFetchTasks: _fetchTasks,
                ),
                const SizedBox(height: 14),
                _EmployeesPreviewCard(
                  employees: _viewModel.roster,
                  onViewAll: () =>
                      Navigator.pushNamed(context, AppRoutes.workerList),
                  onEnroll: () =>
                      Navigator.pushNamed(context, AppRoutes.enrollmentForm),
                ),
                const SizedBox(height: 14),
                _OfflineRegistrationsCard(
                  summary: _viewModel.summary,
                  onSync: _viewModel.sync,
                ),
                const SizedBox(height: 14),
                _HeadlineStats(summary: _viewModel.summary),
                const SizedBox(height: 14),
                _AttendanceCard(
                  summary: _viewModel.summary,
                  onRefresh: _viewModel.load,
                ),
                const SizedBox(height: 14),
                _VerificationCard(
                  summary: _viewModel.summary,
                  onSync: _viewModel.sync,
                ),
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: AppBottomNavBar(
        current: AppSection.dashboard,
        onSectionSelected: (target) =>
            switchToSection(context, AppSection.dashboard, target),
      ),
    );
  }
}

class _DashboardHeader extends StatelessWidget {
  const _DashboardHeader();

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Welcome, Supervisor',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Today, ${DateTimeFormatter.dayLabel(DateTime.now())}',
                style: const TextStyle(fontSize: 14, color: AppColors.muted),
              ),
            ],
          ),
        ),
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.cardBorder),
            color: Colors.white,
          ),
          child: const Icon(
            Icons.person_outline,
            size: 22,
            color: AppColors.ink,
          ),
        ),
      ],
    );
  }
}

/// A short preview of the roster, read straight from the employee table —
/// full names and IDs, not the demo placeholders.
class _EmployeesPreviewCard extends StatelessWidget {
  static const int _previewCount = 4;

  final List<Employee> employees;
  final VoidCallback onViewAll;
  final VoidCallback onEnroll;

  const _EmployeesPreviewCard({
    required this.employees,
    required this.onViewAll,
    required this.onEnroll,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(child: SectionLabel('EMPLOYEES')),
              if (employees.isNotEmpty)
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onViewAll,
                  child: const Text(
                    'View All',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.deepGreen,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (employees.isEmpty)
            _buildEmptyState()
          else
            for (final employee in employees.take(_previewCount))
              _EmployeeRow(employee: employee),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'No employees enrolled yet.',
          style: TextStyle(fontSize: 14, color: AppColors.muted),
        ),
        const SizedBox(height: 12),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onEnroll,
          child: const Text(
            'Enroll the first worker',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppColors.deepGreen,
              decoration: TextDecoration.underline,
            ),
          ),
        ),
      ],
    );
  }
}

class _EmployeeRow extends StatelessWidget {
  final Employee employee;

  const _EmployeeRow({required this.employee});

  String get _initials {
    final parts = employee.name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: const Color(0xFFE7F6EC),
            child: Text(
              _initials,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.deepGreen,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  employee.name,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                  ),
                ),
                Text(
                  employee.employeeId,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12.5, color: AppColors.muted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          PayTypeChip(payType: employee.payType),
        ],
      ),
    );
  }
}

/// Fetches the full worker roster from the backend
/// (`POST attendance/list`) and upserts it locally by National ID.
class _ImportWorkersCard extends StatelessWidget {
  final bool isImporting;
  final VoidCallback onPressed;

  const _ImportWorkersCard({required this.isImporting, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SectionLabel('WORKER DATA'),
                SizedBox(height: 6),
                Text(
                  'Fetch the latest worker list from the server',
                  style: TextStyle(fontSize: 13, color: AppColors.muted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          ElevatedButton.icon(
            onPressed: isImporting ? null : onPressed,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.deepGreen,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              shape: const StadiumBorder(),
            ),
            icon: isImporting
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.cloud_download_outlined, size: 16),
            label: Text(isImporting ? 'Fetching...' : 'Fetch Workers'),
          ),
        ],
      ),
    );
  }
}

/// Two independent refresh actions for the local `departments`/`tasks`
/// caches — each hits its own endpoint
/// (`attendance/searchDept`/`attendance/list_task`) and can be refreshed
/// on its own.
class _RefreshLookupsCard extends StatelessWidget {
  final bool isFetchingDepartments;
  final bool isFetchingTasks;
  final VoidCallback onFetchDepartments;
  final VoidCallback onFetchTasks;

  const _RefreshLookupsCard({
    required this.isFetchingDepartments,
    required this.isFetchingTasks,
    required this.onFetchDepartments,
    required this.onFetchTasks,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionLabel('REFERENCE DATA'),
          const SizedBox(height: 12),
          _RefreshRow(
            label: 'Departments',
            isFetching: isFetchingDepartments,
            onPressed: onFetchDepartments,
          ),
          const Divider(height: 20, color: AppColors.cardBorder),
          _RefreshRow(
            label: 'Tasks',
            isFetching: isFetchingTasks,
            onPressed: onFetchTasks,
          ),
        ],
      ),
    );
  }
}

class _RefreshRow extends StatelessWidget {
  final String label;
  final bool isFetching;
  final VoidCallback onPressed;

  const _RefreshRow({
    required this.label,
    required this.isFetching,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(fontSize: 14.5, color: AppColors.ink),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.cardBorder),
          ),
          child: IconButton(
            onPressed: isFetching ? null : onPressed,
            iconSize: 18,
            color: AppColors.deepGreen,
            icon: isFetching
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
            tooltip: 'Refresh $label',
          ),
        ),
      ],
    );
  }
}

class _OfflineRegistrationsCard extends StatelessWidget {
  final DashboardSummary summary;
  final VoidCallback onSync;

  const _OfflineRegistrationsCard({
    required this.summary,
    required this.onSync,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SectionLabel('OFFLINE REGISTRATIONS'),
                    const SizedBox(height: 8),
                    Text(
                      '${summary.pendingRegistrations} Pending',
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                        color: AppColors.deepGreen,
                      ),
                    ),
                  ],
                ),
              ),
              ElevatedButton(
                onPressed: onSync,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.deepGreen,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 14,
                  ),
                  shape: const StadiumBorder(),
                ),
                child: const Text(
                  'Sync Now',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _LastSynced(summary.lastRegistrationSync, withIcon: true),
        ],
      ),
    );
  }
}

class _HeadlineStats extends StatelessWidget {
  final DashboardSummary summary;

  const _HeadlineStats({required this.summary});

  @override
  Widget build(BuildContext context) {
    // Not `stretch`: inside the scrolling list that would demand an infinite
    // height. The two cards hold matching content, so they line up anyway.
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _StatTile(
            label: 'TOTAL EMPLOYEES',
            value: '${summary.totalEmployees}',
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: _StatTile(
            label: 'PRESENT TODAY',
            value: '${summary.presentToday}',
            suffix: '(${summary.presentPercent}%)',
          ),
        ),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  final String label;
  final String value;
  final String? suffix;

  const _StatTile({required this.label, required this.value, this.suffix});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionLabel(label),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                value,
                style: const TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.w700,
                  color: AppColors.deepGreen,
                ),
              ),
              if (suffix != null) ...[
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    suffix!,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.ink,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _AttendanceCard extends StatelessWidget {
  final DashboardSummary summary;
  final VoidCallback onRefresh;

  const _AttendanceCard({required this.summary, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(child: SectionLabel('ATTENDANCE IN/OUT')),
              Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.cardBorder),
                ),
                child: IconButton(
                  onPressed: onRefresh,
                  iconSize: 18,
                  color: AppColors.deepGreen,
                  icon: const Icon(Icons.sync),
                  tooltip: 'Refresh',
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _MiniStat(
                  label: 'In',
                  value: summary.checkedIn,
                  color: AppColors.success,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _MiniStat(
                  label: 'Out',
                  value: summary.checkedOut,
                  color: AppColors.warning,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _MiniStat(
                  label: 'Pending',
                  value: summary.pendingEntries,
                  color: AppColors.danger,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            'Total Entries: ${summary.totalEntries}',
            style: const TextStyle(fontSize: 13.5, color: AppColors.muted),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: DotLabel(
                  text: '${summary.pendingSyncEntries} pending sync',
                  color: AppColors.deepGreen,
                ),
              ),
              const SizedBox(width: 8),
              Flexible(child: _LastSynced(summary.lastEntrySync)),
            ],
          ),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String label;
  final int value;
  final Color color;

  const _MiniStat({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.pageGrey,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DotLabel(text: label, color: color, fontSize: 12.5),
          const SizedBox(height: 8),
          Text(
            '$value',
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: AppColors.ink,
            ),
          ),
        ],
      ),
    );
  }
}

class _VerificationCard extends StatelessWidget {
  final DashboardSummary summary;
  final VoidCallback onSync;

  const _VerificationCard({required this.summary, required this.onSync});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionLabel('VERIFICATION TASKS'),
          const SizedBox(height: 14),
          _VerificationRow(
            icon: Icons.check_circle_outline,
            iconColor: AppColors.success,
            label: 'Verified',
            value: summary.verifiedTasks,
          ),
          const SizedBox(height: 12),
          _VerificationRow(
            icon: Icons.error_outline,
            iconColor: AppColors.muted,
            label: 'Pending',
            value: summary.pendingTasks,
          ),
          const SizedBox(height: 18),
          AppPrimaryButton(
            label: 'Sync Data',
            background: AppColors.deepGreen,
            foreground: Colors.white,
            onPressed: onSync,
          ),
          const SizedBox(height: 12),
          Center(child: _LastSynced(summary.lastVerificationSync)),
        ],
      ),
    );
  }
}

class _VerificationRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final int value;

  const _VerificationRow({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20, color: iconColor),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(fontSize: 15, color: AppColors.ink),
          ),
        ),
        Text(
          '$value',
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: AppColors.ink,
          ),
        ),
      ],
    );
  }
}

/// "Last synced: 10:30 AM", or an em dash while nothing has synced yet.
class _LastSynced extends StatelessWidget {
  final DateTime? syncedAt;
  final bool withIcon;

  const _LastSynced(this.syncedAt, {this.withIcon = false});

  @override
  Widget build(BuildContext context) {
    final time = syncedAt == null ? '—' : DateTimeFormatter.clock(syncedAt!);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (withIcon) ...[
          const Icon(Icons.access_time, size: 15, color: AppColors.muted),
          const SizedBox(width: 6),
        ],
        Flexible(
          child: Text(
            'Last synced: $time',
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13, color: AppColors.muted),
          ),
        ),
      ],
    );
  }
}

/// The two things a supervisor most often does from the dashboard.
class _QuickActions extends StatelessWidget {
  final VoidCallback onEnroll;
  final VoidCallback onViewWorkers;

  const _QuickActions({required this.onEnroll, required this.onViewWorkers});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _QuickAction(
            icon: Icons.person_add_alt_1,
            label: 'Enroll Worker',
            background: AppColors.deepGreen,
            foreground: Colors.white,
            onTap: onEnroll,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: _QuickAction(
            icon: Icons.groups_outlined,
            label: 'Worker List',
            background: Colors.white,
            foreground: AppColors.deepGreen,
            onTap: onViewWorkers,
          ),
        ),
      ],
    );
  }
}

class _QuickAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color background;
  final Color foreground;
  final VoidCallback onTap;

  const _QuickAction({
    required this.icon,
    required this.label,
    required this.background,
    required this.foreground,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.cardBorder),
        ),
        child: Column(
          children: [
            Icon(icon, size: 24, color: foreground),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: foreground,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
