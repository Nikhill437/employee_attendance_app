import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/app_time.dart';
import '../../../core/utils/date_time_formatter.dart';
import '../../../data/models/worker_task_model.dart';
import '../../../data/repositories/employee_repository.dart';
import '../../common/widgets/common_widgets.dart';
import '../../employee/view/enrollment_form_screen.dart';
import '../viewmodel/worker_report_viewmodel.dart';

/// One worker's attendance/sync report over a date range — reached from
/// the worker list's "Worker report" button. Each day in the range links
/// to a read-only Day Details view of that day's check-in/out.
class WorkerReportScreen extends StatefulWidget {
  final int workerId;
  final String workerName;
  final String? employeeId;
  final String? department;

  /// The backend's own `worker_id`, shown beside the National ID. Null for a
  /// worker not yet synced or imported.
  final int? remoteWorkerId;

  /// The backend's `employee_id` (`workers.employee_id`) — distinct from
  /// [remoteWorkerId] and from [employeeId] (the National ID). Null until
  /// this worker's been imported/synced.
  final int? remoteEmployeeId;

  /// The backend's approval status ('approved' / 'pending' / 'rejected') —
  /// shown as the header's status pill.
  final String status;

  /// Overridable so tests can inject a fake, avoiding the real DatabaseHelper.
  final WorkerReportViewModel? viewModel;

  const WorkerReportScreen({
    super.key,
    required this.workerId,
    required this.workerName,
    this.employeeId,
    this.department,
    this.remoteWorkerId,
    this.remoteEmployeeId,
    this.status = 'pending',
    this.viewModel,
  });

  @override
  State<WorkerReportScreen> createState() => _WorkerReportScreenState();
}

class _WorkerReportScreenState extends State<WorkerReportScreen> {
  late final WorkerReportViewModel _viewModel;
  final EmployeeRepository _employees = EmployeeRepository();

  @override
  void initState() {
    super.initState();
    _viewModel =
        widget.viewModel ?? WorkerReportViewModel(workerId: widget.workerId);
    _viewModel.load();
  }

  @override
  void dispose() {
    _viewModel.dispose();
    super.dispose();
  }

  /// Opens the enrollment form in edit mode — only the worker's Department
  /// can actually change there (see EnrollmentFormScreen); every other
  /// field is shown read-only for context. On a successful save, pops this
  /// screen too (with `true`) so the worker list above it reloads and
  /// picks up the new "Not synced" state.
  Future<void> _openEditWorker() async {
    final employeeId = widget.employeeId;
    if (employeeId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This worker has no record to edit')),
      );
      return;
    }
    final employee = await _employees.findByEmployeeId(employeeId);
    if (!mounted || employee == null) return;
    final updated = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => EnrollmentFormScreen(editingWorker: employee),
      ),
    );
    if (updated == true && mounted) Navigator.pop(context, true);
  }

  Future<void> _pickRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: AppTime.nowInUserZone(),
      initialDateRange: DateTimeRange(
        start: _viewModel.rangeStart,
        end: _viewModel.rangeEnd,
      ),
    );
    if (picked == null) return;
    await _viewModel.setRange(picked.start, picked.end);
  }

  void _openDayDetails(WorkerReportDay day) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            _DayDetailScreen(workerName: widget.workerName, day: day),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.pageGrey,
      body: Column(
        children: [
          _buildHeader(),
          // No bottomNavigationBar on this screen, so its list needs its own
          // clearance from the system navigation bar/gesture area.
          Expanded(
            child: SafeArea(
              top: false,
              child: ListenableBuilder(
                listenable: _viewModel,
                builder: (context, _) => _buildBody(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(10, 12, 20, 20),
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
                const Expanded(
                  child: Text(
                    'Employee Profile',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
                Material(
                  color: Colors.white.withValues(alpha: 0.16),
                  shape: const CircleBorder(),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: _openEditWorker,
                    child: const SizedBox(
                      width: 36,
                      height: 36,
                      child: Icon(Icons.edit, size: 18, color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
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
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _subtitle,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          color: Colors.white70,
                        ),
                      ),
                    ],
                  ),
                ),
                _StatusPill(
                  label: _statusLabel,
                  color: Colors.white,
                  background: Colors.white.withValues(alpha: 0.2),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // Department goes on its own line, so a long name wraps instead of being
  // cut off alongside the IDs on one line.
  String get _subtitle {
    final department = widget.department ?? 'Unassigned';
    final nationalId = widget.employeeId;
    if (nationalId == null) return department;
    final ids = [
      nationalId,
      if (widget.remoteEmployeeId != null)
        'Employee ID ${widget.remoteEmployeeId}',
      // if (widget.remoteWorkerId != null) 'Worker ID ${widget.remoteWorkerId}',
    ];
    return '${ids.join(' • ')}\n$department';
  }

  String get _statusLabel => switch (widget.status) {
    'approved' => 'Active',
    'rejected' => 'Rejected',
    _ => 'Pending',
  };

  Widget _buildBody() {
    if (_viewModel.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        _DateRangeCard(
          start: _viewModel.rangeStart,
          end: _viewModel.rangeEnd,
          onTap: _pickRange,
        ),
        const SizedBox(height: 14),
        _PeriodSummaryCard(
          totalDays: _viewModel.totalDaysInRange,
          daysPresent: _viewModel.daysPresent,
          daysSynced: _viewModel.daysSynced,
        ),
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const SectionLabel('DAILY ACTIVITY'),
            const Text(
              'Newest first',
              style: TextStyle(fontSize: 12, color: AppColors.muted),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (_viewModel.days.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 24),
            child: Center(
              child: Text(
                'No activity in this range',
                style: TextStyle(color: AppColors.muted),
              ),
            ),
          ),
        for (final day in _viewModel.days) ...[
          _DayCard(day: day, onViewDetails: () => _openDayDetails(day)),
          const SizedBox(height: 12),
        ],
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
      width: 50,
      height: 50,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withValues(alpha: 0.16),
      ),
      child: Text(
        _initials,
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
      ),
    );
  }
}

class _DateRangeCard extends StatelessWidget {
  final DateTime start;
  final DateTime end;
  final VoidCallback onTap;

  const _DateRangeCard({
    required this.start,
    required this.end,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Row(
        children: [
          const Icon(
            Icons.calendar_today_outlined,
            size: 18,
            color: AppColors.deepGreen,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'DATE RANGE',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.4,
                    color: AppColors.muted,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${_label(start)} – ${_label(end)}',
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                  ),
                ),
              ],
            ),
          ),
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: onTap,
            child: const Padding(
              padding: EdgeInsets.all(6),
              child: Icon(Icons.tune, size: 20, color: AppColors.muted),
            ),
          ),
        ],
      ),
    );
  }

  String _label(DateTime date) => DateTimeFormatter.dayLabel(date);
}

class _PeriodSummaryCard extends StatelessWidget {
  final int totalDays;
  final int daysPresent;
  final int daysSynced;

  const _PeriodSummaryCard({
    required this.totalDays,
    required this.daysPresent,
    required this.daysSynced,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Period summary',
                style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink,
                ),
              ),
              Text(
                '$totalDays day${totalDays == 1 ? '' : 's'}',
                style: const TextStyle(fontSize: 12, color: AppColors.muted),
              ),
            ],
          ),
          const SizedBox(height: 14),
          IntrinsicHeight(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Expanded(
                  child: _SummaryTile(
                    label: 'ATTENDANCE',
                    value: '$daysPresent/$totalDays',
                    caption: 'Days present',
                    color: AppColors.success,
                  ),
                ),
                Expanded(
                  child: _SummaryTile(
                    label: 'SYNC',
                    value: '$daysSynced/$totalDays',
                    caption: 'Days synced',
                    color: AppColors.deepGreen,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryTile extends StatelessWidget {
  final String label;
  final String value;
  final String caption;
  final Color color;

  const _SummaryTile({
    required this.label,
    required this.value,
    required this.caption,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.4,
            color: AppColors.muted,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          value,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          caption,
          style: const TextStyle(fontSize: 11, color: AppColors.muted),
        ),
      ],
    );
  }
}

/// One day's summary row in the Daily Activity list.
class _DayCard extends StatelessWidget {
  final WorkerReportDay day;
  final VoidCallback onViewDetails;

  const _DayCard({required this.day, required this.onViewDetails});

  bool get _isToday => DateTimeFormatter.isSameDay(
    DateTime.tryParse(day.attendance.attendanceDate) ?? DateTime(0),
    AppTime.nowInUserZone(),
  );

  /// Which task row(s) represent this day: the one actually synced to the
  /// server, if any — the definitive record of what happened, even once a
  /// later reassignment has deactivated it — or, if nothing's synced yet,
  /// whichever row is currently active (the last task assigned that day,
  /// since reassigning deactivates every other row for the date; see
  /// DatabaseHelper.assignWorkerTask/_applyTodaysTaskAssignment). Applies
  /// to any day, not just today: a past day can end up with the same
  /// several-reassignments-in-one-day shape if the supervisor changed
  /// their mind more than once before it synced or the day ended.
  List<WorkerTask> get _visibleTasks {
    final synced = day.tasks.where((task) => task.realWorkerTaskId != null);
    if (synced.isNotEmpty) return synced.toList();
    final active = day.tasks.where((task) => task.status == 'active');
    if (active.isNotEmpty) return active.toList();
    return day.tasks;
  }

  @override
  Widget build(BuildContext context) {
    final date = DateTime.tryParse(day.attendance.attendanceDate);
    final isSynced = day.attendance.isSynced;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: _isToday ? AppColors.deepGreen : AppColors.cardBorder,
          width: _isToday ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    date == null
                        ? day.attendance.attendanceDate
                        : _shortDate(date),
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppColors.ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    date == null
                        ? ''
                        : _isToday
                        ? 'Today · ${_weekday(date)}'
                        : _weekday(date),
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.muted,
                    ),
                  ),
                ],
              ),
              _StatusPill(
                label: isSynced ? 'Synced' : 'Not synced',
                color: isSynced ? AppColors.success : AppColors.warning,
                background: isSynced
                    ? const Color(0xFFE7F6EC)
                    : const Color(0xFFFDF3E3),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Divider(height: 1, color: AppColors.cardBorder),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _TimeColumn(
                  icon: Icons.login,
                  label: 'Check in',
                  time: day.attendance.checkInTime,
                ),
              ),
              Expanded(
                child: _TimeColumn(
                  icon: Icons.logout,
                  label: 'Check out',
                  time: day.attendance.checkOutTime,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Divider(height: 1, color: AppColors.cardBorder),
          const SizedBox(height: 10),
          const SectionLabel('TASKS'),
          const SizedBox(height: 10),
          if (_visibleTasks.isEmpty)
            const Text(
              'No tasks recorded for this day.',
              style: TextStyle(fontSize: 13.5, color: AppColors.muted),
            )
          else
            for (final task in _visibleTasks) ...[
              _DayTaskCard(task: task),
              const SizedBox(height: 10),
            ],
          // const SizedBox(height: 10),
          // Row(
          //   mainAxisAlignment: MainAxisAlignment.spaceBetween,
          //   children: [
          //     Text(
          //       _recordedAtLabel(),
          //       style: const TextStyle(fontSize: 11.5, color: AppColors.muted),
          //     ),
          //     InkWell(
          //       onTap: onViewDetails,
          //       child: const Row(
          //         mainAxisSize: MainAxisSize.min,
          //         children: [
          //           Text(
          //             'View day details',
          //             style: TextStyle(
          //               fontSize: 12.5,
          //               fontWeight: FontWeight.w700,
          //               color: AppColors.deepGreen,
          //             ),
          //           ),
          //           SizedBox(width: 2),
          //           Icon(
          //             Icons.chevron_right,
          //             size: 16,
          //             color: AppColors.deepGreen,
          //           ),
          //         ],
          //       ),
          //     ),
          //   ],
          // ),
        ],
      ),
    );
  }

  String _recordedAtLabel() {
    final time = day.attendance.checkOutTime ?? day.attendance.checkInTime;
    if (time == null) return '';
    final parsed = DateTime.tryParse(time);
    if (parsed == null) return '';
    return 'Recorded ${DateTimeFormatter.clock(parsed)}';
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

  String _weekday(DateTime date) => _weekdayNames[date.weekday - 1];
  String _shortDate(DateTime date) =>
      '${_monthAbbreviations[date.month - 1]} ${date.day}';
}

class _TimeColumn extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? time;

  const _TimeColumn({
    required this.icon,
    required this.label,
    required this.time,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 13, color: AppColors.muted),
            const SizedBox(width: 4),
            Text(
              label,
              style: const TextStyle(fontSize: 12, color: AppColors.muted),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          time == null ? '—' : DateTimeFormatter.clock(DateTime.parse(time!)),
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: AppColors.ink,
          ),
        ),
      ],
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
        borderRadius: BorderRadius.circular(20),
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

/// Read-only detail view for one day — reached from a [_DayCard]'s "View
/// day details" link. Unlike assign_task_screen.dart's Day Details section
/// (always today, with task assignment alongside it), this shows a single
/// past-or-present day with no editing.
class _DayDetailScreen extends StatelessWidget {
  final String workerName;
  final WorkerReportDay day;

  const _DayDetailScreen({required this.workerName, required this.day});

  @override
  Widget build(BuildContext context) {
    final attendance = day.attendance;
    final date = DateTime.tryParse(attendance.attendanceDate);
    return Scaffold(
      backgroundColor: AppColors.pageGrey,
      body: Column(
        children: [
          AppScreenHeader(
            title: 'Day Details',
            subtitle: date == null
                ? '$workerName — ${attendance.attendanceDate}'
                : '$workerName — ${DateTimeFormatter.dayLabel(date)}',
            showBack: true,
          ),
          // No bottomNavigationBar on this screen, so its list needs its own
          // clearance from the system navigation bar/gesture area.
          Expanded(
            child: SafeArea(
              top: false,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  AppCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const SectionLabel('ATTENDANCE'),
                            _StatusPill(
                              label: attendance.isSynced
                                  ? 'Synced'
                                  : 'Not synced',
                              color: attendance.isSynced
                                  ? AppColors.success
                                  : AppColors.warning,
                              background: attendance.isSynced
                                  ? const Color(0xFFE7F6EC)
                                  : const Color(0xFFFDF3E3),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: _TimeColumn(
                                icon: Icons.login,
                                label: 'Check in',
                                time: attendance.checkInTime,
                              ),
                            ),
                            Expanded(
                              child: _TimeColumn(
                                icon: Icons.logout,
                                label: 'Check out',
                                time: attendance.checkOutTime,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  const SectionLabel('TASKS'),
                  const SizedBox(height: 10),
                  if (day.tasks.isEmpty)
                    const AppCard(
                      child: Text(
                        'No tasks recorded for this day.',
                        style: TextStyle(
                          fontSize: 13.5,
                          color: AppColors.muted,
                        ),
                      ),
                    )
                  else
                    for (final task in day.tasks) ...[
                      _DayTaskCard(task: task),
                      const SizedBox(height: 10),
                    ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One task the worker had on the day: its name, the worker's own quantity,
/// the supervisor's quantity/status/note, and whether it's still active.
class _DayTaskCard extends StatelessWidget {
  final WorkerTask task;

  const _DayTaskCard({required this.task});

  String get _taskStatusLabel => switch (task.taskStatus) {
    'approved' => 'Approved',
    'rejected' => 'Rejected',
    _ => 'Pending',
  };

  Color get _taskStatusColor => switch (task.taskStatus) {
    'approved' => AppColors.deepGreen,
    'rejected' => AppColors.danger,
    _ => AppColors.ink,
  };

  @override
  Widget build(BuildContext context) {
    final note = task.supervisorNote?.trim();
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  task.taskName,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                  ),
                ),
              ),
            ],
          ),

          _TaskDetailLine(
            label: 'Task Status',
            value: _taskStatusLabel,
            valueColor: _taskStatusColor,
          ),
          // const SizedBox(height: 10),
          if (task.employeeTarget != null)
            _TaskDetailLine(
              label: 'Employee quantity',
              value: task.employeeTarget.toString(),
            ),
          if (task.completedTarget != null)
            _TaskDetailLine(
              label: 'Supervisor quantity',
              value: task.completedTarget.toString(),
            ),
          // _TaskDetailLine(
          //   label: 'Review',
          //   value: _taskStatusLabel,
          //   valueColor: _taskStatusColor,
          // ),
          if (note != null && note.isNotEmpty)
            _TaskDetailLine(label: 'Note', value: note),
        ],
      ),
    );
  }
}

class _TaskDetailLine extends StatelessWidget {
  final String label;
  final String value;

  /// Overrides the value's usual muted-ink color — used for the Review
  /// line, colored by its Approved/Rejected/Pending status.
  final Color? valueColor;

  const _TaskDetailLine({
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: const TextStyle(fontSize: 13, color: AppColors.muted),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 13,
                fontWeight: valueColor == null
                    ? FontWeight.w400
                    : FontWeight.w700,
                color: valueColor ?? AppColors.ink,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
