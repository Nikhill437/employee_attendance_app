import 'package:flutter/material.dart';

import '../../../core/routes/section_navigation.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/date_time_formatter.dart';
import '../../../data/models/worker_attendance_model.dart';
import '../../common/widgets/common_widgets.dart';
import '../../task/view/task_status_screen.dart';
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
    // may be invisible" assertion this replaces).
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
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

/// One attendance day: its check-in/check-out times, and a button to the
/// tasks assigned for that day (task_status_screen.dart), so a supervisor
/// can review or fix a Yes/No call from any past day, not just at checkout.
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _timeLine(
                  icon: Icons.login,
                  label: 'Check In',
                  time: record.checkInTime,
                ),
                const SizedBox(height: 4),
                _timeLine(
                  icon: Icons.logout,
                  label: 'Check Out',
                  time: record.checkOutTime,
                ),
              ],
            ),
          ),
          if (workerId != null)
            TextButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => TaskStatusScreen(
                    workerId: workerId!,
                    workerName: workerName,
                    attendanceId: record.attendanceId,
                  ),
                ),
              ),
              icon: const Icon(Icons.fact_check_outlined, size: 16),
              label: const Text('Tasks'),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.deepGreen,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                textStyle: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _timeLine({
    required IconData icon,
    required String label,
    required String? time,
  }) {
    return Row(
      children: [
        Icon(icon, size: 14, color: AppColors.muted),
        const SizedBox(width: 6),
        Text(
          '$label: ${time == null ? 'Not yet' : DateTimeFormatter.format(time)}',
          style: const TextStyle(fontSize: 13, color: AppColors.slate),
        ),
      ],
    );
  }
}
