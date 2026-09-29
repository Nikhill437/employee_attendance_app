import 'package:flutter/material.dart';

import '../../../core/routes/section_navigation.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/date_time_formatter.dart';
import '../../../data/models/worker_attendance_model.dart';
import '../../common/widgets/common_widgets.dart';
import '../viewmodel/worker_history_viewmodel.dart';

/// Reports: every enrolled worker's attendance log and assigned task list,
/// reached from the bottom nav's "Reports" tab.
class WorkerHistoryScreen extends StatefulWidget {
  /// Overridable so tests can inject a fake, avoiding the real DatabaseHelper.
  final WorkerHistoryViewModel? viewModel;

  const WorkerHistoryScreen({super.key, this.viewModel});

  @override
  State<WorkerHistoryScreen> createState() => _WorkerHistoryScreenState();
}

class _WorkerHistoryScreenState extends State<WorkerHistoryScreen> {
  late final WorkerHistoryViewModel _viewModel;

  @override
  void initState() {
    super.initState();
    _viewModel = widget.viewModel ?? WorkerHistoryViewModel();
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
          const AppScreenHeader(
            title: 'Worker History',
            subtitle: 'Attendance & tasks',
          ),
          Expanded(
            child: ListenableBuilder(
              listenable: _viewModel,
              builder: (context, _) => _buildBody(),
            ),
          ),
        ],
      ),
      bottomNavigationBar: AppBottomNavBar(
        current: AppSection.reports,
        onSectionSelected: (target) =>
            switchToSection(context, AppSection.reports, target),
      ),
    );
  }

  Widget _buildBody() {
    if (_viewModel.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_viewModel.entries.isEmpty) {
      return const Center(
        child: Text(
          'No workers to show',
          style: TextStyle(color: AppColors.muted),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _viewModel.load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          for (final entry in _viewModel.entries) ...[
            _WorkerHistoryCard(entry: entry),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}

class _WorkerHistoryCard extends StatelessWidget {
  final WorkerHistoryEntry entry;

  const _WorkerHistoryCard({required this.entry});

  @override
  Widget build(BuildContext context) {
    // Material, not a plain decorated Container — ExpansionTile's ListTile
    // paints its background/ink splashes on the nearest Material ancestor,
    // and a Container's DecoratedBox sitting in between would paint over
    // and hide them (see the "ListTile background color or ink splashes
    // may be invisible" assertion this replaces). Radius/border match the
    // card look used on worker_report_screen.dart's day cards.
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: AppColors.cardBorder),
      ),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        // ExpansionTile paints a divider by default; the app's cards don't
        // use one, so this keeps the collapsed state visually consistent.
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          title: Text(
            entry.employee.name,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppColors.ink,
            ),
          ),
          subtitle: Text(
            '${entry.employee.employeeId} • '
            '${entry.attendanceRecords.length} day'
            '${entry.attendanceRecords.length == 1 ? '' : 's'} • '
            '${entry.tasks.length} task'
            '${entry.tasks.length == 1 ? '' : 's'}',
            style: const TextStyle(fontSize: 12.5, color: AppColors.muted),
          ),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SectionLabel('ATTENDANCE LOG'),
                  const SizedBox(height: 8),
                  if (entry.attendanceRecords.isEmpty)
                    const Text(
                      'No attendance recorded yet',
                      style: TextStyle(fontSize: 13, color: AppColors.muted),
                    )
                  else
                    for (final record in entry.attendanceRecords)
                      _AttendanceDayRow(
                        record: record,
                        workerId: entry.employee.id,
                        workerName: entry.employee.name,
                      ),
                  const SizedBox(height: 16),
                  const SectionLabel('ASSIGNED TASKS'),
                  const SizedBox(height: 8),
                  if (entry.tasks.isEmpty)
                    const Text(
                      'No tasks assigned yet',
                      style: TextStyle(fontSize: 13, color: AppColors.muted),
                    )
                  else
                    for (final task in entry.tasks)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.task_alt_outlined,
                              size: 14,
                              color: AppColors.deepGreen,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              task.taskName,
                              style: const TextStyle(
                                fontSize: 13,
                                color: AppColors.slate,
                              ),
                            ),
                          ],
                        ),
                      ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One attendance day, styled the same as worker_report_screen.dart's day
/// card: date/weekday and a Synced/Not synced pill up top, a divider, then
/// check-in/check-out times.
class _AttendanceDayRow extends StatelessWidget {
  final WorkerAttendanceRecord record;
  final int? workerId;
  final String workerName;

  const _AttendanceDayRow({
    required this.record,
    required this.workerId,
    required this.workerName,
  });

  @override
  Widget build(BuildContext context) {
    final date = DateTime.tryParse(record.attendanceDate);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.cardBorder),
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
                    date == null ? record.attendanceDate : _shortDate(date),
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppColors.ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    date == null ? '' : _weekday(date),
                    style: const TextStyle(fontSize: 12, color: AppColors.muted),
                  ),
                ],
              ),
              _StatusPill(
                label: record.isSynced ? 'Synced' : 'Not synced',
                color: record.isSynced ? AppColors.success : AppColors.warning,
                background: record.isSynced
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
                  time: record.checkInTime,
                ),
              ),
              Expanded(
                child: _TimeColumn(
                  icon: Icons.logout,
                  label: 'Check out',
                  time: record.checkOutTime,
                ),
              ),
            ],
          ),
        ],
      ),
    );
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
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  String _weekday(DateTime date) => _weekdayNames[date.weekday - 1];
  String _shortDate(DateTime date) =>
      '${_monthAbbreviations[date.month - 1]} ${date.day}';
}

/// Same look as worker_report_screen.dart's own `_TimeColumn`.
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

/// Same look as worker_report_screen.dart's own `_StatusPill`.
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
