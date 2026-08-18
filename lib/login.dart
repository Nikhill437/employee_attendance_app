import 'package:flutter/material.dart';
import 'database_helper.dart';
import 'employee_model.dart';
import 'attendance_log_model.dart';
import 'face_scan_screen.dart';
import 'face_recognition_service.dart';
import 'attendance_summary_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _employeeIdController = TextEditingController();
  final DatabaseHelper _dbHelper = DatabaseHelper();
  final FaceRecognitionService _faceService = FaceRecognitionService();

  bool _isSuccess = false;
  bool _isLookingUp = false;
  Employee? _matchedEmployee;

  @override
  void dispose() {
    _employeeIdController.dispose();
    super.dispose();
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  /// Verifies [embedding] against the employee identified by the entered
  /// employeeId only (1:1 verification against their multi-pose profile),
  /// not a search across every enrolled employee. Called by
  /// [FaceScanScreen] once it has a stable, live (liveness-checked)
  /// single-face embedding.
  Future<Employee?> _verifyAndMarkAttendance(
    List<double> embedding,
    Employee employee,
  ) async {
    final matched = _faceService.verify(embedding, employee.faceEmbeddings);
    if (!matched) return null;

    final log = AttendanceLog(
      employeeId: employee.employeeId,
      employeeName: employee.name,
      loginTime: DateTime.now().toIso8601String(),
    );
    await _dbHelper.insertAttendanceLog(log);
    return employee;
  }

  Future<void> _startScan() async {
    if (!_formKey.currentState!.validate()) return;
    final employeeId = _employeeIdController.text.trim();

    setState(() => _isLookingUp = true);
    final employee = await _dbHelper.getEmployeeByEmployeeId(employeeId);
    setState(() => _isLookingUp = false);

    if (employee == null) {
      _showSnackBar('No employee found with that ID');
      return;
    }
    if (employee.faceEmbeddings.isEmpty) {
      _showSnackBar('This employee has no enrolled face. Enroll first.');
      return;
    }
    if (!mounted) return;

    final matched = await Navigator.push<Employee>(
      context,
      MaterialPageRoute(
        builder: (context) => FaceScanScreen(
          mode: FaceScanMode.attendance,
          title: 'Scan Face to Login',
          onMatch: (embedding) => _verifyAndMarkAttendance(embedding, employee),
        ),
      ),
    );
    if (matched == null || !mounted) return;

    setState(() {
      _isSuccess = true;
      _matchedEmployee = matched;
    });

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
        child: _isSuccess ? _buildSuccessView(scheme) : _buildScanPrompt(scheme),
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
            _matchedEmployee?.name ?? '',
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
                  onPressed: _isLookingUp ? null : _startScan,
                  icon: _isLookingUp
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
                    _isLookingUp ? 'Looking up...' : 'Scan Face',
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
