import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/app_time.dart';
import '../../../core/utils/date_time_formatter.dart';
import '../../../data/models/worker_task_completion_model.dart';
import '../../common/widgets/common_widgets.dart';
import '../viewmodel/worker_report_viewmodel.dart';

/// One worker's attendance/task/sync report over a date range — reached
/// from the worker list's "Worker report" button. Each day in the range
/// links to a read-only Day Details view of that day's check-in/out and
/// task checklist.
class WorkerReportScreen extends StatefulWidget {
  final int workerId;
  final String workerName;
  final String? employeeId;
  final String? department;

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
    this.status = 'pending',
    this.viewModel,
  });

  @override
  State<WorkerReportScreen> createState() => _WorkerReportScreenState();
}

class _WorkerReportScreenState extends State<WorkerReportScreen> {
  late final WorkerReportViewModel _viewModel;

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
                const Expanded(
                  child: Text(
                    'Worker Report',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
                Container(
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.16),
                  ),
                  child: const Icon(
                    Icons.share_outlined,
                    size: 18,
                    color: Colors.white,
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

  String get _subtitle {
    final department = widget.department ?? 'Unassigned';
    return widget.employeeId == null
        ? department
        : '${widget.employeeId} • $department';
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
          tasksCompleted: _viewModel.tasksCompleted,
          totalTasksAssigned: _viewModel.totalTasksAssigned,
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
  final int tasksCompleted;
  final int totalTasksAssigned;
  final int daysSynced;

  const _PeriodSummaryCard({
    required this.totalDays,
    required this.daysPresent,
    required this.tasksCompleted,
    required this.totalTasksAssigned,
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
                    label: 'TASKS',
                    value: '$tasksCompleted/$totalTasksAssigned',
                    caption: 'Completed',
                    color: AppColors.warning,
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
          if (day.totalCount > 0) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFF6F9F6),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.assignment_outlined,
                    size: 15,
                    color: AppColors.muted,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${day.totalCount} assigned task${day.totalCount == 1 ? '' : 's'}',
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: AppColors.slate,
                      ),
                    ),
                  ),
                  Text(
                    '${day.completedCount} completed',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: day.completedCount == day.totalCount
                          ? AppColors.success
                          : AppColors.warning,
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _recordedAtLabel(),
                style: const TextStyle(fontSize: 11.5, color: AppColors.muted),
              ),
              InkWell(
                onTap: onViewDetails,
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'View day details',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.deepGreen,
                      ),
                    ),
                    SizedBox(width: 2),
                    Icon(
                      Icons.chevron_right,
                      size: 16,
                      color: AppColors.deepGreen,
                    ),
                  ],
                ),
              ),
            ],
          ),
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
          Expanded(
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
                const SizedBox(height: 16),
                if (day.tasks.isNotEmpty) ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const SectionLabel('ASSIGNED TASKS'),
                      Text(
                        '${day.completedCount} of ${day.totalCount} completed',
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: AppColors.muted,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  for (var i = 0; i < day.tasks.length; i++) ...[
                    _DayTaskCard(index: i + 1, completion: day.tasks[i]),
                    if (i != day.tasks.length - 1) const SizedBox(height: 10),
                  ],
                ] else
                  const Text(
                    'No tasks were assigned this day',
                    style: TextStyle(color: AppColors.muted),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DayTaskCard extends StatelessWidget {
  final int index;
  final WorkerTaskCompletion completion;

  const _DayTaskCard({required this.index, required this.completion});

  bool get _isVerified =>
      completion.isCompleted && completion.completionId != null;

  @override
  Widget build(BuildContext context) {
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
                  '$index',
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
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _StatusPill(
                label: completion.isCompleted ? 'Completed' : 'Not started',
                color: completion.isCompleted
                    ? AppColors.success
                    : AppColors.muted,
                background: completion.isCompleted
                    ? const Color(0xFFE7F6EC)
                    : const Color(0xFFF2F3F2),
              ),
              _StatusPill(
                label: _isVerified
                    ? 'Verified'
                    : completion.isCompleted
                    ? 'Awaiting sync'
                    : 'Not verified',
                color: _isVerified
                    ? AppColors.success
                    : completion.isCompleted
                    ? AppColors.warning
                    : AppColors.muted,
                background: _isVerified
                    ? const Color(0xFFE7F6EC)
                    : completion.isCompleted
                    ? const Color(0xFFFDF3E3)
                    : const Color(0xFFF2F3F2),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
