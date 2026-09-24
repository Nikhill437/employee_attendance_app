import 'package:flutter/material.dart';

import '../../../core/routes/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/input_formatters.dart';
import '../../../data/models/auth/auth_user_model.dart';
import '../../../data/models/worker_attendance_model.dart';
import '../../../data/repositories/worker_attendance_repository.dart';
import '../../common/widgets/common_widgets.dart';
import '../../face_scan/view/face_scan_screen.dart';
import '../../task/view/task_status_screen.dart';
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
    if (user == null || !mounted) return;

    _viewModel.completeLogin(user);
    await Future.delayed(_successPause);
    if (!mounted) return;

    await _showTaskScreenIfNeeded(user);
    if (!mounted) return;
    _finish();
  }

  /// After attendance is marked, additionally shows the worker's assigned
  /// tasks (on check-in) or lets the supervisor record which were
  /// completed (on check-out). This is purely additive: it only reads and
  /// writes `worker_attendance`/`worker_task_completion` (previously
  /// unused, schema-only tables) via [WorkerAttendanceRepository] — the
  /// existing attendance_logs write above (`_viewModel.completeLogin`,
  /// backed by AuthRepository.login) is untouched.
  Future<void> _showTaskScreenIfNeeded(AuthUser user) async {
    final workerId = user.id;
    if (workerId == null) return;

    final record = await _attendanceRepository.recordScan(workerId);
    if (!mounted) return;

    switch (record.outcome) {
      case WorkerScanOutcome.checkedIn:
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) =>
                WorkerTaskListScreen(workerId: workerId, workerName: user.name),
          ),
        );
      case WorkerScanOutcome.checkedOut:
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => TaskStatusScreen(
              workerId: workerId,
              workerName: user.name,
              attendanceId: record.attendanceId,
              // The worker's own self-service checkout (public kiosk flow,
              // no supervisor involved) only ever gets to see whatever
              // Yes/No the supervisor already set — never to change it
              // themselves. The supervisor-initiated flow (checking a
              // worker out from worker_list_screen.dart) still gets the
              // editable version.
              readOnly: !_isSupervisorInitiated,
            ),
          ),
        );
      case WorkerScanOutcome.alreadyCheckedOut:
      case null:
        break;
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

  Widget _buildSuccessView() {
    return Column(
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
        const Text(
          'Attendance Marked Successfully',
          textAlign: TextAlign.center,
          style: TextStyle(
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
            'Enter the National ID your supervisor assigned you, to continue',
            style: TextStyle(fontSize: 14.5, color: Colors.white70),
          ),
          const SizedBox(height: 32),
          AppTextField(
            label: 'National ID',
            hint: 'eg. National ID Card Number',
            icon: Icons.badge_outlined,
            controller: _employeeIdController,
            keyboardType: TextInputType.visiblePassword,
            textInputAction: TextInputAction.done,
            inputFormatters: AppInputFormatters.alphanumericUppercase,
            onSubmitted: (_) => _startScan(),
            validator: (v) => (v == null || v.trim().isEmpty)
                ? 'Enter your National ID'
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
