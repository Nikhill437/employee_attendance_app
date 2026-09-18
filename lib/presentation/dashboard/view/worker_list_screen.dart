import 'package:flutter/material.dart';

import '../../../core/routes/app_routes.dart';
import '../../../core/routes/section_navigation.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/date_time_formatter.dart';
import '../../../data/models/worker_model.dart';
import '../../common/widgets/common_widgets.dart';
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
      messenger.showSnackBar(
        SnackBar(content: Text('${worker.name} removed')),
      );
    } catch (e) {
      await _viewModel.load();
      messenger.showSnackBar(
        SnackBar(content: Text('Could not delete ${worker.name}: $e')),
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
              child: _WorkerCard(worker: worker),
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

  const _WorkerCard({required this.worker});

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
              const SizedBox(width: 8),
              _buildAttendance(),
            ],
          ),
          const Divider(height: 22, color: AppColors.cardBorder),
          _buildFooter(),
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
          _StatusText(
            label: worker.verification.label,
            color: _verificationColor,
            showDot: worker.verification != VerificationStatus.verified,
            alignEnd: true,
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
    VerificationStatus.notVerified => AppColors.muted,
  };
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
