import 'package:flutter/material.dart';

import '../../../core/routes/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/input_formatters.dart';
import '../../../data/models/auth/auth_user_model.dart';
import '../../../data/models/department_model.dart';
import '../../../data/models/worker_attendance_model.dart';
import '../../../data/repositories/employee_repository.dart';
import '../../../data/repositories/task_repository.dart';
import '../../../data/repositories/worker_attendance_repository.dart';
import '../../common/widgets/common_widgets.dart';
import '../../face_scan/view/face_scan_screen.dart';
import '../../task/view/assign_task_screen.dart';
import '../../task/view/worker_task_list_screen.dart';
import '../viewmodel/login_viewmodel.dart';

class MarkAttendanceScreen extends StatefulWidget {
  /// Non-null skips the National ID entry form and starts the scan for
  /// this employeeId immediately — the "Mark Attendance" action on a
  /// worker's card in worker_list_screen.dart.
  final String? initialEmployeeId;

  const MarkAttendanceScreen({super.key, this.initialEmployeeId});

  @override
  State<MarkAttendanceScreen> createState() => _MarkAttendanceScreenState();
}

class _MarkAttendanceScreenState extends State<MarkAttendanceScreen> {
  static const Duration _successPause = Duration(milliseconds: 1400);

  final _formKey = GlobalKey<FormState>();
  final _employeeIdController = TextEditingController();
  final LoginViewModel _viewModel = LoginViewModel();
  final WorkerAttendanceRepository _attendanceRepository =
      WorkerAttendanceRepository();
  final EmployeeRepository _employeeRepository = EmployeeRepository();
  final TaskRepository _taskRepository = TaskRepository();

  /// This scan's check-in/check-out outcome, recorded as soon as the face
  /// match succeeds — read by [_buildSuccessView] to pick the right
  /// headline and by [_openFollowUpScreen] to pick the right next screen,
  /// so [WorkerAttendanceRepository.recordScan] (which updates the day's
  /// row every time it's called) only ever runs once per scan.
  WorkerAttendanceRecord? _scanRecord;

  bool get _isSupervisorInitiated => widget.initialEmployeeId != null;

  @override
  void initState() {
    super.initState();
    final initialId = widget.initialEmployeeId;
    if (initialId != null) {
      _employeeIdController.text = initialId;
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _runScanFlow(initialId),
      );
    }
  }

  @override
  void dispose() {
    _employeeIdController.dispose();
    _viewModel.dispose();
    super.dispose();
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _startScan() async {
    if (!_formKey.currentState!.validate()) return;
    await _runScanFlow(_employeeIdController.text.trim());
  }

  /// The actual lookup → scan → mark-attendance sequence, shared by both
  /// the manual-entry path and the supervisor-initiated one.
  Future<void> _runScanFlow(String employeeId) async {
    if (!await _lookUpEmployee(employeeId)) return;

    final user = await _scanFace(employeeId);
    if (!mounted) return;
    if (user == null) {
      // The camera screen already popped itself (Cancel Scan). For the
      // supervisor-initiated flow there's nothing left to show but the
      // "Starting face verification..." loading state — with no camera left
      // to cancel — so back out of this screen too instead of stranding the
      // supervisor there for a second Cancel tap.
      if (_isSupervisorInitiated) Navigator.pop(context);
      return;
    }

    // Recorded before the success view renders (not inside
    // _openFollowUpScreen, which used to run this after the pause) so the
    // headline below can already say which one just happened. recordScan
    // checks the worker in on their first scan of the day and checks them
    // out — updating the same row — on every scan after that, so a worker
    // can check out as many times as they like in a day and the row always
    // keeps the latest one.
    _scanRecord = await _recordAttendanceScan(user);
    if (!mounted) return;

    _viewModel.completeLogin(user);
    await Future.delayed(_successPause);
    if (!mounted) return;

    final shouldFinish = await _openFollowUpScreen(user);
    if (!mounted) return;
    if (shouldFinish) _finish();
  }

  Future<WorkerAttendanceRecord?> _recordAttendanceScan(AuthUser user) async {
    final workerId = user.id;
    if (workerId == null) return null;
    return _attendanceRepository.recordScan(workerId);
  }

  /// After attendance is marked, additionally shows the worker's assigned
  /// tasks on check-in, or the Assign Task screen's Worker Submission card
  /// on check-out (so the worker can record today's numeric
  /// reading/photo for whatever task is currently assigned). This is
  /// purely additive: it only reads and writes `worker_attendance` (a
  /// previously unused, schema-only table) via [WorkerAttendanceRepository]
  /// — the existing attendance_logs write above (`_viewModel.completeLogin`,
  /// backed by AuthRepository.login) is untouched. Reuses [_scanRecord]
  /// from [_runScanFlow] rather than recording the scan again here.
  ///
  /// Returns whether [_runScanFlow] should go on to call [_finish] —
  /// true once the follow-up screen (if any was shown) is dismissed by any
  /// means, whether that's a successful save, its header back arrow, or
  /// the OS back button/swipe-back gesture — none of those should leave
  /// the worker stranded on this screen's own success view. [_finish]
  /// itself is what already picks the right destination for how this
  /// screen was opened: back to worker_list_screen.dart's card
  /// ([_isSupervisorInitiated]) or on to splash_screen.dart (the public
  /// kiosk flow).
  Future<bool> _openFollowUpScreen(AuthUser user) async {
    final workerId = user.id;
    final record = _scanRecord;
    if (workerId == null || record == null) return true;

    switch (record.outcome) {
      case WorkerScanOutcome.checkedIn:
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) =>
                WorkerTaskListScreen(workerId: workerId, workerName: user.name),
          ),
        );
        return true;
      case WorkerScanOutcome.checkedOut:
        final assignment = await _taskRepository.getCurrentAssignment(
          workerId,
        );
        if (!mounted) return false;
        // Daily/Monthly tasks have nothing for the worker to submit at
        // checkout (no per-day count/hours to record) — only Task Based/
        // Hour Based tasks (and the checkout-time Worker Submission card
        // that goes with them) need this screen at all.
        final taskType = assignment?.taskType;
        final needsSubmission =
            taskType == TaskType.taskBased.name ||
            taskType == TaskType.hourBased.name;
        if (!needsSubmission) return true;

        final employee = await _employeeRepository.findByEmployeeId(
          user.employeeId,
        );
        if (!mounted) return false;
        // The result (true on a successful save, null/false from the header
        // back arrow or the OS back button/swipe-back gesture) is ignored —
        // showing this screen is additive, same as WorkerTaskListScreen
        // above for check-in, so dismissing it by any means should still go
        // on to _finish(). Gating on `saved == true` left a back/swipe exit
        // stuck on this screen's own success view forever, since nothing
        // else was left to move it on.
        await Navigator.push<bool>(
          context,
          MaterialPageRoute(
            builder: (context) => AssignTaskScreen(
              workerId: workerId,
              workerName: user.name,
              employeeId: user.employeeId,
              department: employee?.department,
              initialDepartmentId: employee?.departmentId,
              isCheckoutSubmission: true,
            ),
          ),
        );
        return true;
      case WorkerScanOutcome.alreadyCheckedOut:
      case null:
        return true;
    }
  }

  /// Confirms the ID is enrolled before the camera is opened. Surfaces the
  /// rejection and returns false when it is not.
  Future<bool> _lookUpEmployee(String employeeId) async {
    final canLogin = await _viewModel.prepareLogin(employeeId);
    if (!mounted || canLogin) return canLogin;

    final error = _viewModel.errorMessage;
    if (error != null) _showSnackBar(error);
    _viewModel.consumeError();
    return false;
  }

  Future<AuthUser?> _scanFace(String employeeId) {
    return Navigator.push<AuthUser>(
      context,
      MaterialPageRoute(
        builder: (context) => FaceScanScreen(
          mode: FaceScanMode.attendance,
          title: 'Face Verification',
          onMatch: (embedding) =>
              _viewModel.authenticate(employeeId, embedding),
        ),
      ),
    );
  }

  /// Supervisor-initiated: pops back to whichever worker card this was
  /// opened from, signalling success so the list reloads. Public kiosk
  /// flow: swaps this screen for the (supervisor-only) login screen rather
  /// than popping — an employee arrived here straight from the splash
  /// screen with no login step of their own, so there is nothing to pop
  /// back to that still makes sense once attendance is marked.
  void _finish() {
    if (_isSupervisorInitiated) {
      Navigator.pop(context, true);
    } else {
      Navigator.pushReplacementNamed(context, AppRoutes.splash);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: BackgroundScreen(
        child: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 28,
                    vertical: 24,
                  ),
                  child: ListenableBuilder(
                    listenable: _viewModel,
                    builder: (context, _) => _viewModel.isAuthenticated
                        ? _buildSuccessView()
                        : _isSupervisorInitiated
                        ? _buildSupervisorLoadingState()
                        : _buildScanPrompt(),
                  ),
                ),
              ),
              const SizedBox(height: 23),
              const AppFooterImage(),
            ],
          ),
        ),
      ),
    );
  }

  /// Which of the two outcomes [_scanRecord] (set in [_runScanFlow]) was —
  /// check-in on the day's first scan, checkout on every scan after that.
  String _successHeadline() {
    switch (_scanRecord?.outcome) {
      case WorkerScanOutcome.checkedOut:
        return 'Check Out completed successfully';
      case WorkerScanOutcome.checkedIn:
        return 'Check In completed successfully';
      case WorkerScanOutcome.alreadyCheckedOut:
      case null:
        return 'Attendance Marked Successfully';
    }
  }

  Widget _buildSuccessView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 110,
          height: 110,
          decoration: const BoxDecoration(
            color: Color(0xFFE3F6E8),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.check_circle_rounded,
            color: Color(0xFF2E9E4F),
            size: 84,
          ),
        ),
        const SizedBox(height: 24),
        Text(
          _successHeadline(),
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 19,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          _viewModel.authenticatedUser?.name ?? '',
          style: const TextStyle(fontSize: 16, color: Colors.white70),
        ),
      ],
    );
  }

  /// Shown briefly while the supervisor-initiated flow looks the worker up
  /// and opens the camera — there's no form to fill in since the worker is
  /// already known. Keeps a way back out in case the lookup fails (e.g. no
  /// enrolled face) before the camera ever opens.
  Widget _buildSupervisorLoadingState() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SizedBox(height: MediaQuery.of(context).size.height * 0.15),
        const BrandHeader(logoWidth: 220, logoHeight: 220, showTagline: false),
        const SizedBox(height: 28),
        const CircularProgressIndicator(color: Colors.white),
        const SizedBox(height: 16),
        const Text(
          'Starting face verification...',
          style: TextStyle(color: Colors.white70, fontSize: 14.5),
        ),
        const SizedBox(height: 24),
        AppLinkText(
          label: 'Cancel',
          fontSize: 16,
          onTap: () => Navigator.maybePop(context),
        ),
      ],
    );
  }

  Widget _buildScanPrompt() {
    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(height: MediaQuery.of(context).size.height * 0.08),
          const BrandHeader(
            logoWidth: 220,
            logoHeight: 220,
            showTagline: false,
          ),
          const SizedBox(height: 10),
          const Text(
            'Mark Attendance',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Enter the Employee ID your supervisor assigned you, to continue',
            style: TextStyle(fontSize: 14.5, color: Colors.white70),
          ),
          const SizedBox(height: 32),
          AppTextField(
            label: 'Employee ID',
            hint: 'eg. Employee ID Number',
            icon: Icons.badge_outlined,
            controller: _employeeIdController,
            keyboardType: TextInputType.visiblePassword,
            textInputAction: TextInputAction.done,
            inputFormatters: AppInputFormatters.alphanumericUppercase,
            onSubmitted: (_) => _startScan(),
            validator: (v) => (v == null || v.trim().isEmpty)
                ? 'Enter your Employee ID'
                : null,
          ),
          const SizedBox(height: 28),
          AppPrimaryButton(
            label: _viewModel.isLookingUp ? 'Looking up...' : 'Continue',
            icon: Icons.face,
            isBusy: _viewModel.isLookingUp,
            background: AppColors.lime,
            onPressed: _startScan,
          ),
          AppLinkText(
            label: 'Back to Login',
            fontSize: 16,
            onTap: () => Navigator.maybePop(context),
          ),
        ],
      ),
    );
  }
}
