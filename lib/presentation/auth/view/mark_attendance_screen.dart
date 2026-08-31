import 'package:flutter/material.dart';

import '../../../core/utils/background.dart';
import '../../../data/models/auth/auth_user_model.dart';
import '../../attendance/view/attendance_summary_screen.dart';
import '../../face_scan/view/face_scan_screen.dart';
import '../viewmodel/login_viewmodel.dart';

/// Employee-ID entry followed by a face scan, verified 1:1 against the
/// profile enrolled for that ID. On a match the attendance log is written and
/// the summary screen replaces this one.
class MarkAttendanceScreen extends StatefulWidget {
  const MarkAttendanceScreen({super.key});

  @override
  State<MarkAttendanceScreen> createState() => _MarkAttendanceScreenState();
}

class _MarkAttendanceScreenState extends State<MarkAttendanceScreen> {
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
          title: 'Scan Face to Mark Attendance',
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
    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('Mark Attendance'),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: BackgroundScreen(
        child: SafeArea(
          child: ListenableBuilder(
            listenable: _viewModel,
            builder: (context, _) => _viewModel.isAuthenticated
                ? _buildSuccessView()
                : _buildScanPrompt(),
          ),
        ),
      ),
    );
  }

  Widget _buildSuccessView() {
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
      ),
    );
  }

  Widget _buildScanPrompt() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Center(
                child: Icon(
                  Icons.face_retouching_natural,
                  size: 72,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 28),
              const Text(
                'Welcome back',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Enter your Employee ID, then scan your face to mark '
                'attendance',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14.5, color: Colors.white70),
              ),
              const SizedBox(height: 32),
              TextFormField(
                controller: _employeeIdController,
                textInputAction: TextInputAction.done,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'Employee ID',
                  labelStyle: const TextStyle(color: Colors.white70),
                  prefixIcon: const Icon(
                    Icons.badge_outlined,
                    color: Colors.white70,
                  ),
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                ),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'Enter your Employee ID'
                    : null,
              ),
              const SizedBox(height: 28),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: const Color(0xFF0D4A1C),
                  minimumSize: const Size(double.infinity, 56),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 0,
                ),
                onPressed: _viewModel.isLookingUp ? null : _startScan,
                icon: _viewModel.isLookingUp
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Color(0xFF0D4A1C),
                        ),
                      )
                    : const Icon(Icons.face),
                label: Text(
                  _viewModel.isLookingUp ? 'Looking up...' : 'Scan Face',
                  style: const TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w600,
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
