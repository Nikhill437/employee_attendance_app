import 'package:flutter/material.dart';

import '../../../core/routes/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/input_formatters.dart';
import '../../../data/models/auth/auth_user_model.dart';
import '../../common/widgets/common_widgets.dart';
import '../../face_scan/view/face_scan_screen.dart';
import '../viewmodel/login_viewmodel.dart';

/// Employee-ID entry followed by a face scan, verified 1:1 against the
/// profile enrolled for that ID. On a match the attendance log is written and
/// the app returns to the (supervisor-only) login screen — an employee has
/// no credentials for it, so this is also what keeps the dashboard behind
/// the supervisor login rather than reachable from the attendance flow.
class MarkAttendanceScreen extends StatefulWidget {
  const MarkAttendanceScreen({super.key});

  @override
  State<MarkAttendanceScreen> createState() => _MarkAttendanceScreenState();
}

class _MarkAttendanceScreenState extends State<MarkAttendanceScreen> {
  static const Duration _successPause = Duration(milliseconds: 1400);

  final _formKey = GlobalKey<FormState>();
  final _employeeIdController = TextEditingController();
  final LoginViewModel _viewModel = LoginViewModel();

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
    final employeeId = _employeeIdController.text.trim();

    if (!await _lookUpEmployee(employeeId)) return;

    final user = await _scanFace(employeeId);
    if (user == null || !mounted) return;

    _viewModel.completeLogin(user);
    await Future.delayed(_successPause);
    if (!mounted) return;
    _returnToLogin();
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

  /// Swaps this screen for the (supervisor-only) login screen rather than
  /// popping — an employee arrived here straight from the splash screen with
  /// no login step of their own, so there is nothing to pop back to that
  /// still makes sense once attendance is marked.
  void _returnToLogin() {
    Navigator.pushReplacementNamed(context, AppRoutes.splash);
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
