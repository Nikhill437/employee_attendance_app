import 'package:flutter/material.dart';

import '../../../data/models/auth/auth_user_model.dart';
import '../../attendance/view/attendance_summary_screen.dart';
import '../../face_scan/view/face_scan_screen.dart';
import '../viewmodel/login_viewmodel.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
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

    final canLogin = await _viewModel.prepareLogin(employeeId);
    if (!mounted) return;
    if (!canLogin) {
      final error = _viewModel.errorMessage;
      if (error != null) _showSnackBar(error);
      _viewModel.consumeError();
      return;
    }

    final user = await Navigator.push<AuthUser>(
      context,
      MaterialPageRoute(
        builder: (context) => FaceScanScreen(
          mode: FaceScanMode.attendance,
          title: 'Scan Face to Login',
          onMatch: (embedding) =>
              _viewModel.authenticate(employeeId, embedding),
        ),
      ),
    );
    if (user == null || !mounted) return;

    _viewModel.completeLogin(user);

    Future.delayed(const Duration(milliseconds: 1400), () {
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => const AttendanceSummaryScreen(),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        title: const Text('Login'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: _viewModel,
          builder: (context, _) => _viewModel.isAuthenticated
              ? _buildSuccessView(scheme)
              : _buildScanPrompt(scheme),
        ),
      ),
    );
  }

  Widget _buildSuccessView(ColorScheme scheme) {
    return Center(
      child: Column(
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
            style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            _viewModel.authenticatedUser?.name ?? '',
            style: TextStyle(fontSize: 16, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _buildScanPrompt(ColorScheme scheme) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.face_retouching_natural,
                    size: 52,
                    color: scheme.onPrimaryContainer,
                  ),
                ),
              ),
              const SizedBox(height: 28),
              Text(
                'Welcome back',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Enter your Employee ID, then scan your face to mark attendance',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14.5, color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 32),
              TextFormField(
                controller: _employeeIdController,
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(
                  labelText: 'Employee ID',
                  prefixIcon: const Icon(Icons.badge_outlined),
                  filled: true,
                  fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Enter your Employee ID' : null,
              ),
              const SizedBox(height: 28),
              SizedBox(
                height: 56,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(28),
                    ),
                    elevation: 0,
                  ),
                  onPressed: _viewModel.isLookingUp ? null : _startScan,
                  icon: _viewModel.isLookingUp
                      ? SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: scheme.onPrimary,
                          ),
                        )
                      : const Icon(Icons.face),
                  label: Text(
                    _viewModel.isLookingUp ? 'Looking up...' : 'Scan Face',
                    style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
