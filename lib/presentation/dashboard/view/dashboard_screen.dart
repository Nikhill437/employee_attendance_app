import 'package:employee_attendance_app/presentation/settings/view/settings_screen.dart';
import 'package:flutter/material.dart';

import '../../../core/routes/app_routes.dart';
import '../../../core/routes/section_navigation.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/app_time.dart';
import '../../../core/utils/date_time_formatter.dart';
import '../../../data/models/dashboard_summary_model.dart';
import '../../../data/models/employee_model.dart';
import '../../common/widgets/common_widgets.dart';
import '../viewmodel/dashboard_viewmodel.dart';
import 'sync_bottom_sheet.dart';

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
    _viewModel.load().then((_) {
      if (!mounted || !_viewModel.takePendingSyncNotice()) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Data is remaining to be synced to server.'),
        ),
      );
    });
  }

  @override
  void dispose() {
    if (_ownsViewModel) _viewModel.dispose();
    super.dispose();
  }

  /// Fetches the full worker roster from the backend and upserts it
  /// locally by National ID, showing the sync bottom sheet throughout. The
  /// very first (full, paginated) import reports real page-by-page
  /// progress; every later (incremental, single-call) import shows the
  /// sheet's indeterminate spinner instead.
  ///
  /// If a previous full import was interrupted partway through, this asks
  /// first (Cancel / Start From Beginning / Resume) rather than silently
  /// re-fetching or silently continuing.
  Future<void> _importWorkers() async {
    final checkpoint = await _viewModel.getInterruptedEmployeeImport();
    var resumeFrom = checkpoint;
    if (checkpoint != null) {
      if (!mounted) return;
      final choice = await showResumeSyncDialog(
        context,
        recordLabel: 'Employee',
        stoppedAtPage: checkpoint.nextPage - 1,
        totalPages: checkpoint.totalPages,
        recordsSoFar: checkpoint.fetchedSoFar,
      );
      if (choice == null || choice == SyncResumeChoice.cancel) return;
      if (choice == SyncResumeChoice.startOver) {
        await _viewModel.discardInterruptedEmployeeImport();
        resumeFrom = null;
      }
    }

    // What the import's own cumulative fetched-so-far count starts at this
    // run — 0 for a fresh/restarted import, or the checkpoint's count when
    // resuming — so "Downloading" below reflects only this run's progress,
    // not records already accounted for under "Existing".
    final sessionBaseline = resumeFrom?.fetchedSoFar ?? 0;
    final existingBefore = _viewModel.summary.totalEmployees;
    if (!mounted) return;
    await showSyncBottomSheet(
      context,
      recordLabel: 'employee',
      availableCount: resumeFrom == null
          ? _viewModel.updatedCounts.workerCount
          : null,
      download: (onProgress) => _viewModel.importWorkersFromServer(
        resumeFrom: resumeFrom,
        onProgress: (fetchedSoFar, currentPage, totalPages) => onProgress(
          _pageProgress(
            existingBefore: existingBefore,
            sessionBaseline: sessionBaseline,
            fetchedSoFar: fetchedSoFar,
            currentPage: currentPage,
            totalPages: totalPages,
          ),
        ),
      ),
    );
  }

  /// The combined Employee List Data & Tasks card's shared "Check For New
  /// Data" button: imports the worker roster, then the worker-task
  /// assignments, one after another — each still showing its own sync
  /// sheet and updating its own last-synced checkpoint exactly as it did
  /// as a separate card, same as [_fetchDepartmentsAndTasks] does for
  /// Departments & Tasks.
  Future<void> _fetchEmployeeListAndTasks() async {
    await _importWorkers();
    if (!mounted) return;
    await _fetchWorkerTasks();
  }

  /// Turns one page's raw `(fetchedSoFar, currentPage, totalPages)` report
  /// — the shape every paginated fetch API reports progress in — into the
  /// sync bottom sheet's [SyncProgress]. [existingBefore] is the local row
  /// count snapshotted before the fetch started; [sessionBaseline] is what
  /// the fetch's own cumulative [fetchedSoFar] starts at this run (0
  /// unless resuming an interrupted import), so "Downloading" reflects
  /// only this run's progress, not rows already counted under "Existing".
  /// The total (and so "Remaining") is only an estimate — the server
  /// reports page counts, not an exact row total — extrapolated from the
  /// average page size seen so far.
  SyncProgress _pageProgress({
    required int existingBefore,
    required int sessionBaseline,
    required int fetchedSoFar,
    required int currentPage,
    required int totalPages,
  }) {
    final averagePerPage = currentPage > 0 ? fetchedSoFar / currentPage : 0.0;
    final estimatedTotal = (totalPages * averagePerPage).round();
    return SyncProgress(
      existing: existingBefore,
      downloading: fetchedSoFar - sessionBaseline,
      remaining: (estimatedTotal - fetchedSoFar).clamp(0, estimatedTotal),
      percent: totalPages == 0 ? 0 : currentPage / totalPages,
    );
  }

  /// Shows a Cancel/Clear confirmation dialog with [message], then — only
  /// if confirmed — runs [clear] and reports success or failure in a
  /// snackbar. Shared by every overview card's Clear button.
  Future<void> _confirmAndClear({
    required String title,
    required String message,
    required Future<void> Function() clear,
    required String successMessage,
    required String failurePrefix,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'Clear',
              style: TextStyle(color: AppColors.danger),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      await clear();
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(successMessage)));
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('$failurePrefix: $e')));
    }
  }

  /// The combined Employee List Data & Tasks card's single Clear action:
  /// wipes both local caches and resets both fetch checkpoints, so the
  /// next Check For New Data tap pulls both full lists again. Also drops
  /// any locally enrolled employee, or task reassignment/review, not yet
  /// pushed to the server — the view's confirmation dialog warns about
  /// this before calling here.
  Future<void> _clearEmployeeListAndTasksData() => _confirmAndClear(
    title: 'Clear employee & task data?',
    message:
        'This removes every employee and employee task assignment stored '
        'on this device, including any not yet synced to the server. The '
        'next Check For New Data tap will re-download both full lists.',
    clear: () async {
      await _viewModel.clearEmployeeData();
      await _viewModel.clearWorkerTasksData();
    },
    successMessage: 'Employee & task data cleared',
    failurePrefix: 'Could not clear employee & task data',
  );

  /// The standalone Employee Attendance card's Clear action: wipes every
  /// local check-in/check-out record, including any not yet synced to the
  /// server.
  Future<void> _clearAttendanceData() => _confirmAndClear(
    title: 'Clear attendance data?',
    message:
        'This removes every attendance record stored on this device, '
        'including any not yet synced to the server. The next Check For '
        'New Data tap will re-download the full list.',
    clear: _viewModel.clearAttendanceData,
    successMessage: 'Attendance data cleared',
    failurePrefix: 'Could not clear attendance data',
  );

  /// The combined Departments & Tasks card's single Clear action: wipes
  /// both local caches and resets both fetch checkpoints, so the next
  /// Check For New Data tap pulls both full lists again (their
  /// initial-fetch behavior). Both are pure server-reflected reference
  /// data, so nothing local is ever lost here.
  Future<void> _clearDepartmentsAndTasksData() => _confirmAndClear(
    title: 'Clear department & task data?',
    message:
        'This removes every department and task stored on this device. '
        'The next Check For New Data tap will re-download both full lists.',
    clear: () async {
      await _viewModel.clearDepartmentsData();
      await _viewModel.clearTasksCatalogData();
    },
    successMessage: 'Department & task data cleared',
    failurePrefix: 'Could not clear department & task data',
  );

  /// The later of two last-synced times, for the combined Departments &
  /// Tasks card's single last-synced line — each catalog's own checkpoint
  /// is still tracked and preserved independently underneath; only the
  /// display is merged into one.
  DateTime? _latestOf(DateTime? a, DateTime? b) {
    if (a == null) return b;
    if (b == null) return a;
    return a.isAfter(b) ? a : b;
  }

  /// Departments/Tasks fetches are paginated the same way the Employee
  /// List import is, so this reports real progress too.
  Future<void> _fetchDepartments() async {
    final existingBefore = _viewModel.summary.departmentsTotal;
    await showSyncBottomSheet(
      context,
      recordLabel: 'department',
      availableCount: _viewModel.updatedCounts.departmentCount,
      download: (onProgress) => _viewModel.fetchDepartments(
        onProgress: (fetchedSoFar, currentPage, totalPages) => onProgress(
          _pageProgress(
            existingBefore: existingBefore,
            sessionBaseline: 0,
            fetchedSoFar: fetchedSoFar,
            currentPage: currentPage,
            totalPages: totalPages,
          ),
        ),
      ),
    );
  }

  Future<void> _fetchTasks() async {
    final existingBefore = _viewModel.summary.tasksCatalogTotal;
    await showSyncBottomSheet(
      context,
      recordLabel: 'task',
      availableCount: _viewModel.updatedCounts.taskCount,
      download: (onProgress) => _viewModel.fetchTasks(
        onProgress: (fetchedSoFar, currentPage, totalPages) => onProgress(
          _pageProgress(
            existingBefore: existingBefore,
            sessionBaseline: 0,
            fetchedSoFar: fetchedSoFar,
            currentPage: currentPage,
            totalPages: totalPages,
          ),
        ),
      ),
    );
  }

  /// The combined Departments & Tasks card's shared "Check For New Data"
  /// button: runs the two existing, independent fetches one after another,
  /// each still showing its own sync sheet and updating its own last-synced
  /// checkpoint. Neither call's failure is reported as the other's success —
  /// [showSyncBottomSheet] already keeps each download's error inside its
  /// own sheet, so one failing has no effect on the other running.
  Future<void> _fetchDepartmentsAndTasks() async {
    await _fetchDepartments();
    if (!mounted) return;
    await _fetchTasks();
  }

  /// No server-reported "changed count" exists for attendance, so the
  /// sheet skips the "New Data Available" step and starts downloading
  /// immediately — but it is paginated, so it reports real progress like
  /// the other three cards.
  Future<void> _fetchAttendance() async {
    final existingBefore = _viewModel.summary.attendanceTotal;
    await showSyncBottomSheet(
      context,
      recordLabel: 'attendance record',
      download: (onProgress) => _viewModel.fetchDepartmentAttendance(
        onProgress: (fetchedSoFar, currentPage, totalPages) => onProgress(
          _pageProgress(
            existingBefore: existingBefore,
            sessionBaseline: 0,
            fetchedSoFar: fetchedSoFar,
            currentPage: currentPage,
            totalPages: totalPages,
          ),
        ),
      ),
    );
  }

  /// No server-reported changed count exists for employee task
  /// assignments either, so this also skips straight to downloading — but
  /// it is paginated, so it reports real progress like Departments/Tasks.
  Future<void> _fetchWorkerTasks() async {
    final existingBefore = _viewModel.summary.workerTasksTotal;
    await showSyncBottomSheet(
      context,
      recordLabel: 'employee task',
      download: (onProgress) => _viewModel.fetchWorkerTasks(
        onProgress: (fetchedSoFar, currentPage, totalPages) => onProgress(
          _pageProgress(
            existingBefore: existingBefore,
            sessionBaseline: 0,
            fetchedSoFar: fetchedSoFar,
            currentPage: currentPage,
            totalPages: totalPages,
          ),
        ),
      ),
    );
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
                _EmployeeListAndTasksCard(
                  isFetching:
                      _viewModel.isImportingWorkers ||
                      _viewModel.isFetchingWorkerTasks,
                  onFetch: _viewModel.canRunSetupStep(1)
                      ? _fetchEmployeeListAndTasks
                      : null,
                  isClearing:
                      _viewModel.isClearingEmployees ||
                      _viewModel.isClearingWorkerTasks,
                  onClear: _clearEmployeeListAndTasksData,
                  lastFetchedAt: _latestOf(
                    _viewModel.summary.employeesLastFetchedAt,
                    _viewModel.summary.workerTasksLastFetchedAt,
                  ),
                  updatedWorkerCount: _viewModel.updatedCounts.workerCount,
                  totalEmployees: _viewModel.summary.totalEmployees,
                  offlineEmployees: _viewModel.summary.offlineEmployees,
                  totalTasks: _viewModel.summary.workerTasksTotal,
                  pendingReview: _viewModel.summary.pendingWorkerTasks,
                ),
                const SizedBox(height: 14),
                _FetchAttendanceCard(
                  isFetching: _viewModel.isFetchingAttendance,
                  isClearing: _viewModel.isClearingAttendance,
                  onPressed: _viewModel.canRunSetupStep(3)
                      ? _fetchAttendance
                      : null,
                  onClear: _clearAttendanceData,
                  total: _viewModel.summary.attendanceTotal,
                  unsynced: _viewModel.summary.unsyncedAttendance,
                  lastFetchedAt: _viewModel.summary.attendanceLastFetchedAt,
                ),
                const SizedBox(height: 14),
                _DepartmentsAndTasksCard(
                  isFetching:
                      _viewModel.isFetchingDepartments ||
                      _viewModel.isFetchingTasks,
                  onFetch: _fetchDepartmentsAndTasks,
                  isClearing:
                      _viewModel.isClearingDepartments ||
                      _viewModel.isClearingTasks,
                  onClear: _clearDepartmentsAndTasksData,
                  lastFetchedAt: _latestOf(
                    _viewModel.summary.departmentsLastFetchedAt,
                    _viewModel.summary.tasksCatalogLastFetchedAt,
                  ),
                  newOnServer:
                      _viewModel.updatedCounts.departmentCount +
                      _viewModel.updatedCounts.taskCount,
                  departmentsTotal: _viewModel.summary.departmentsTotal,
                  tasksTotal: _viewModel.summary.tasksCatalogTotal,
                ),
                const SizedBox(height: 14),
                // _EmployeesPreviewCard(
                //   employees: _viewModel.roster,
                //   onViewAll: () =>
                //       Navigator.pushNamed(context, AppRoutes.workerList),
                //   onEnroll: () =>
                //       Navigator.pushNamed(context, AppRoutes.enrollmentForm),
                // ),
                const SizedBox(height: 14),
                // _OfflineRegistrationsCard(
                //   summary: _viewModel.summary,
                //   onSync: _viewModel.sync,
                // ),
                // const SizedBox(height: 14),
                _HeadlineStats(summary: _viewModel.summary),
                const SizedBox(height: 14),
                _AttendanceCard(
                  summary: _viewModel.summary,
                  onRefresh: _viewModel.load,
                ),
                // const SizedBox(height: 5),
                // _VerificationCard(
                //   summary: _viewModel.summary,
                //   onSync: _viewModel.sync,
                // ),
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
                'Today, ${DateTimeFormatter.dayLabel(AppTime.nowInUserZone())}',
                style: const TextStyle(fontSize: 14, color: AppColors.muted),
              ),
            ],
          ),
        ),
        GestureDetector(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => SettingsScreen()),
          ),
          child: Container(
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
        ),
      ],
    );
  }
}

/// A short preview of the roster, read straight from the employee table —
/// full names and IDs, not the demo placeholders.
// class _EmployeesPreviewCard extends StatelessWidget {
//   static const int _previewCount = 4;

//   final List<Employee> employees;
//   final VoidCallback onViewAll;
//   final VoidCallback onEnroll;

//   const _EmployeesPreviewCard({
//     required this.employees,
//     required this.onViewAll,
//     required this.onEnroll,
//   });

//   @override
//   Widget build(BuildContext context) {
//     return AppCard(
//       child: Column(
//         crossAxisAlignment: CrossAxisAlignment.start,
//         children: [
//           Row(
//             children: [
//               const Expanded(child: SectionLabel('WORKERS')),
//               if (employees.isNotEmpty)
//                 GestureDetector(
//                   behavior: HitTestBehavior.opaque,
//                   onTap: onViewAll,
//                   child: const Text(
//                     'View All',
//                     style: TextStyle(
//                       fontSize: 13,
//                       fontWeight: FontWeight.w700,
//                       color: AppColors.deepGreen,
//                     ),
//                   ),
//                 ),
//             ],
//           ),
//           const SizedBox(height: 12),
//           if (employees.isEmpty)
//             _buildEmptyState()
//           else
//             for (final employee in employees.take(_previewCount))
//               _EmployeeRow(employee: employee),
//         ],
//       ),
//     );
//   }

//   Widget _buildEmptyState() {
//     return Column(
//       crossAxisAlignment: CrossAxisAlignment.start,
//       children: [
//         const Text(
//           'No employees enrolled yet.',
//           style: TextStyle(fontSize: 14, color: AppColors.muted),
//         ),
//         const SizedBox(height: 12),
//         GestureDetector(
//           behavior: HitTestBehavior.opaque,
//           onTap: onEnroll,
//           child: const Text(
//             'Enroll the first worker',
//             style: TextStyle(
//               fontSize: 14,
//               fontWeight: FontWeight.w700,
//               color: AppColors.deepGreen,
//               decoration: TextDecoration.underline,
//             ),
//           ),
//         ),
//       ],
//     );
//   }
// }

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
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: AppColors.muted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (employee.taskType != null)
            TaskTypeChip(taskType: employee.taskType!),
        ],
      ),
    );
  }
}

/// A small pill showing how many changed records the server reports for
/// one of Workers/Departments/Tasks (`attendance/updated-counts`) — hidden
/// entirely at zero, so the dashboard doesn't clutter itself with "0" pills
/// once everything's caught up.
class _UpdatedCountBadge extends StatelessWidget {
  final int count;

  const _UpdatedCountBadge({required this.count});

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFFFDF3E3),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        'New data available',
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: AppColors.warning,
        ),
      ),
    );
  }
}

/// Employee List Data and Employee Tasks List, combined into one card:
/// each still shows its own two stat boxes (nothing stops being tracked),
/// under one shared last-synced time, one shared Clear button, and one
/// shared "Check For New Data" button that imports the worker roster, then
/// the worker-task assignments, one after another. Fetches worker data
/// from the backend (`POST attendance/worker_data`) and upserts it locally
/// by National ID. [updatedWorkerCount] is how many changed worker records
/// the server currently reports (`attendance/updated-counts`) — a hint
/// that there's something new to fetch, not a cap on what actually comes
/// back; there's no equivalent server-reported count for worker tasks.
class _EmployeeListAndTasksCard extends StatelessWidget {
  final bool isFetching;
  final VoidCallback? onFetch;
  final bool isClearing;
  final VoidCallback onClear;
  final DateTime? lastFetchedAt;
  final int updatedWorkerCount;

  final int totalEmployees;
  final int offlineEmployees;
  final int totalTasks;
  final int pendingReview;

  const _EmployeeListAndTasksCard({
    required this.isFetching,
    required this.onFetch,
    required this.isClearing,
    required this.onClear,
    required this.lastFetchedAt,
    required this.updatedWorkerCount,
    required this.totalEmployees,
    required this.offlineEmployees,
    required this.totalTasks,
    required this.pendingReview,
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
              const Expanded(child: SectionLabel('EMPLOYEE LIST & TASKS')),
              if (updatedWorkerCount > 0)
                _UpdatedCountBadge(count: updatedWorkerCount),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _StatBox(
                  icon: Icons.check_circle_outline,
                  label: 'TOTAL EMPLOYEES',
                  value: totalEmployees,
                  caption: 'ON THIS DEVICE',
                  color: AppColors.success,
                  background: const Color(0xFFE9F7EF),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _StatBox(
                  icon: Icons.cloud_off_outlined,
                  label: 'OFFLINE EMPLOYEES',
                  value: offlineEmployees,
                  caption: 'SAVED WITHOUT SYNC',
                  color: AppColors.warning,
                  background: const Color(0xFFFCEFE3),
                ),
              ),
            ],
          ),
          // const SizedBox(height: 10),
          // Row(
          //   children: [
          //     Expanded(
          //       child: _StatBox(
          //         icon: Icons.check_circle_outline,
          //         label: 'TOTAL TASKS',
          //         value: totalTasks,
          //         caption: 'ON THIS DEVICE',
          //         color: AppColors.success,
          //         background: const Color(0xFFE9F7EF),
          //       ),
          //     ),
          //     const SizedBox(width: 12),
          //     Expanded(
          //       child: _StatBox(
          //         icon: Icons.rate_review_outlined,
          //         label: 'PENDING REVIEW',
          //         value: pendingReview,
          //         caption: 'AWAITING VERDICT',
          //         color: AppColors.warning,
          //         background: const Color(0xFFFCEFE3),
          //       ),
          //     ),
          //   ],
          // ),
          const SizedBox(height: 14),
          _OverviewCardActions(
            lastFetchedAt: lastFetchedAt,
            isFetching: isFetching,
            isClearing: isClearing,
            onFetch: onFetch,
            onClear: onClear,
          ),
        ],
      ),
    );
  }
}

/// One stat tile on a dashboard overview card — a tinted box with an icon
/// + label up top, the number itself, and a muted caption underneath.
class _StatBox extends StatelessWidget {
  final IconData icon;
  final String label;
  final int value;
  final String caption;
  final Color color;
  final Color background;

  const _StatBox({
    required this.icon,
    required this.label,
    required this.value,
    required this.caption,
    required this.color,
    required this.background,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.3,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '$value',
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            caption,
            style: const TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
              color: AppColors.muted,
            ),
          ),
        ],
      ),
    );
  }
}

/// The bottom row shared by every overview card: the last-fetched
/// timestamp on the left, Clear and the fetch action right-aligned
/// (wrapping onto a second line on a narrow screen rather than
/// overflowing). Each card shows its own "New data available" pill only
/// once, next to its section label — not repeated here too.
class _OverviewCardActions extends StatelessWidget {
  final DateTime? lastFetchedAt;
  final bool isFetching;
  final bool isClearing;
  final VoidCallback? onFetch;
  final VoidCallback? onClear;

  const _OverviewCardActions({
    required this.lastFetchedAt,
    required this.isFetching,
    required this.isClearing,
    required this.onFetch,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final busy = isFetching || isClearing;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _LastSynced(lastFetchedAt, withIcon: true, withDate: true),
        const SizedBox(height: 10),
        Wrap(
          alignment: WrapAlignment.end,
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: busy ? null : onClear,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.danger,
                side: const BorderSide(color: AppColors.danger),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                shape: const StadiumBorder(),
              ),
              icon: isClearing
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.danger,
                      ),
                    )
                  : const Icon(Icons.delete_outline, size: 16),
              label: const Text('Clear'),
            ),
            ElevatedButton.icon(
              onPressed: busy ? null : onFetch,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.deepGreen,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                shape: const StadiumBorder(),
              ),
              icon: isFetching
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.refresh, size: 16),
              label: Text(isFetching ? 'Checking...' : 'Check For New Data'),
            ),
          ],
        ),
      ],
    );
  }
}

/// The Departments and Tasks catalogs, combined into one card: each still
/// shows its own total stat box (per-catalog last-synced/Clear are no
/// longer shown individually), under one shared last-synced time, one
/// shared Clear button, and one shared "Check For New Data" button that
/// runs both fetches together. [newOnServer] is however many changed
/// department + task records the server currently reports combined — shown
/// as one "New data available" pill, the same as every other overview card.
class _DepartmentsAndTasksCard extends StatelessWidget {
  final bool isFetching;
  final VoidCallback onFetch;
  final bool isClearing;
  final VoidCallback onClear;
  final DateTime? lastFetchedAt;
  final int newOnServer;

  final int departmentsTotal;
  final int tasksTotal;

  const _DepartmentsAndTasksCard({
    required this.isFetching,
    required this.onFetch,
    required this.isClearing,
    required this.onClear,
    required this.lastFetchedAt,
    required this.newOnServer,
    required this.departmentsTotal,
    required this.tasksTotal,
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
              const Expanded(child: SectionLabel('DEPARTMENTS & TASKS')),
              if (newOnServer > 0) _UpdatedCountBadge(count: newOnServer),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _StatBox(
                  icon: Icons.check_circle_outline,
                  label: 'TOTAL DEPARTMENTS',
                  value: departmentsTotal,
                  caption: 'ON THIS DEVICE',
                  color: AppColors.success,
                  background: const Color(0xFFE9F7EF),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _StatBox(
                  icon: Icons.check_circle_outline,
                  label: 'TOTAL TASKS',
                  value: tasksTotal,
                  caption: 'ON THIS DEVICE',
                  color: AppColors.success,
                  background: const Color(0xFFE9F7EF),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _OverviewCardActions(
            lastFetchedAt: lastFetchedAt,
            isFetching: isFetching,
            isClearing: isClearing,
            onFetch: onFetch,
            onClear: onClear,
          ),
        ],
      ),
    );
  }
}

/// The dashboard's standalone "Employee Attendance" overview: how many
/// check-in/check-out records are stored locally, how many of those
/// haven't synced yet, when it was last checked, and the actions to clear
/// or refresh it. Fetches the department's check-ins/check-outs
/// (`GET attendance/departmentwise_attendance`) via
/// [DashboardViewModel.fetchDepartmentAttendance] — no server-reported
/// "changed count" exists for attendance, so there's no badge here.
class _FetchAttendanceCard extends StatelessWidget {
  final bool isFetching;
  final bool isClearing;
  final VoidCallback? onPressed;
  final VoidCallback onClear;
  final int total;
  final int unsynced;
  final DateTime? lastFetchedAt;

  const _FetchAttendanceCard({
    required this.isFetching,
    required this.isClearing,
    required this.onPressed,
    required this.onClear,
    required this.total,
    required this.unsynced,
    required this.lastFetchedAt,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionLabel('EMPLOYEE ATTENDANCE'),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _StatBox(
                  icon: Icons.check_circle_outline,
                  label: 'TOTAL RECORDS',
                  value: total,
                  caption: 'ON THIS DEVICE',
                  color: AppColors.success,
                  background: const Color(0xFFE9F7EF),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _StatBox(
                  icon: Icons.cloud_off_outlined,
                  label: 'NOT SYNCED',
                  value: unsynced,
                  caption: 'AWAITING SYNC',
                  color: AppColors.warning,
                  background: const Color(0xFFFCEFE3),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _OverviewCardActions(
            lastFetchedAt: lastFetchedAt,
            isFetching: isFetching,
            isClearing: isClearing,
            onFetch: onPressed,
            onClear: onClear,
          ),
        ],
      ),
    );
  }
}

// class _OfflineRegistrationsCard extends StatelessWidget {
//   final DashboardSummary summary;
//   final VoidCallback onSync;

//   const _OfflineRegistrationsCard({
//     required this.summary,
//     required this.onSync,
//   });

//   @override
//   Widget build(BuildContext context) {
//     return AppCard(
//       child: Column(
//         crossAxisAlignment: CrossAxisAlignment.start,
//         children: [
//           Row(
//             crossAxisAlignment: CrossAxisAlignment.start,
//             children: [
//               Expanded(
//                 child: Column(
//                   crossAxisAlignment: CrossAxisAlignment.start,
//                   children: [
//                     const SectionLabel('OFFLINE REGISTRATIONS'),
//                     const SizedBox(height: 8),
//                     Text(
//                       '${summary.pendingRegistrations} Pending',
//                       style: const TextStyle(
//                         fontSize: 26,
//                         fontWeight: FontWeight.w700,
//                         color: AppColors.deepGreen,
//                       ),
//                     ),
//                   ],
//                 ),
//               ),
//               ElevatedButton(
//                 onPressed: onSync,
//                 style: ElevatedButton.styleFrom(
//                   backgroundColor: AppColors.deepGreen,
//                   foregroundColor: Colors.white,
//                   elevation: 0,
//                   padding: const EdgeInsets.symmetric(
//                     horizontal: 20,
//                     vertical: 14,
//                   ),
//                   shape: const StadiumBorder(),
//                 ),
//                 child: const Text(
//                   'Sync Now',
//                   style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
//                 ),
//               ),
//             ],
//           ),
//           const SizedBox(height: 12),
//           _LastSynced(summary.lastRegistrationSync, withIcon: true),
//         ],
//       ),
//     );
//   }
// }

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
                  label: 'Check In',
                  value: summary.checkedIn,
                  color: AppColors.success,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _MiniStat(
                  label: 'Check Out',
                  value: summary.checkedOut,
                  color: AppColors.warning,
                ),
              ),
              // const SizedBox(width: 10),
              // Expanded(
              //   child: _MiniStat(
              //     label: 'Pending',
              //     value: summary.pendingEntries,
              //     color: AppColors.danger,
              //   ),
              // ),
            ],
          ),
          // const SizedBox(height: 14),
          // Text(
          //   'Total Entries: ${summary.totalEntries}',
          //   style: const TextStyle(fontSize: 13.5, color: AppColors.muted),
          // ),
          // const SizedBox(height: 10),
          // Row(
          //   children: [
          //     Expanded(
          //       child: DotLabel(
          //         text: '${summary.pendingSyncEntries} pending sync',
          //         color: AppColors.deepGreen,
          //       ),
          //     ),
          //     const SizedBox(width: 8),
          //     Flexible(child: _LastSynced(summary.lastEntrySync)),
          //   ],
          // ),
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

// class _VerificationCard extends StatelessWidget {
//   final DashboardSummary summary;
//   final VoidCallback onSync;

//   const _VerificationCard({required this.summary, required this.onSync});

//   @override
//   Widget build(BuildContext context) {
//     return AppCard(
//       child: Column(
//         crossAxisAlignment: CrossAxisAlignment.start,
//         children: [
//           const SectionLabel('VERIFICATION TASKS'),
//           const SizedBox(height: 14),
//           _VerificationRow(
//             icon: Icons.check_circle_outline,
//             iconColor: AppColors.success,
//             label: 'Verified',
//             value: summary.verifiedTasks,
//           ),
//           const SizedBox(height: 12),
//           _VerificationRow(
//             icon: Icons.error_outline,
//             iconColor: AppColors.muted,
//             label: 'Pending',
//             value: summary.pendingTasks,
//           ),
//           const SizedBox(height: 18),
//           AppPrimaryButton(
//             label: 'Sync Data',
//             background: AppColors.deepGreen,
//             foreground: Colors.white,
//             onPressed: onSync,
//           ),
//           const SizedBox(height: 12),
//           Center(child: _LastSynced(summary.lastVerificationSync)),
//         ],
//       ),
//     );
//   }
// }

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

  /// Includes the date (`Oct 7 • 2:11 PM`), not just the clock — the
  /// dashboard overview cards each track their own independent "last
  /// synced" checkpoint, and without a date two cards synced around the
  /// same time of day on different days render identically, which looks
  /// like they share one timestamp even though they don't.
  final bool withDate;

  const _LastSynced(
    this.syncedAt, {
    this.withIcon = false,
    this.withDate = false,
  });

  @override
  Widget build(BuildContext context) {
    final time = syncedAt == null
        ? '—'
        : withDate
        ? DateTimeFormatter.shortDateAndClock(syncedAt!)
        : DateTimeFormatter.clock(syncedAt!);
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
            label: 'Enroll Employee',
            background: AppColors.deepGreen,
            foreground: Colors.white,
            onTap: onEnroll,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: _QuickAction(
            icon: Icons.groups_outlined,
            label: 'Employee List',
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
