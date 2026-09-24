import 'package:flutter/material.dart';

import '../../face_scan/view/face_scan_screen.dart';
import '../viewmodel/create_employee_viewmodel.dart';
import 'attendance_detail_screen.dart';

class CreateAttendanceScreen extends StatefulWidget {
  const CreateAttendanceScreen({super.key});

  @override
  State<CreateAttendanceScreen> createState() => _CreateAttendanceScreenState();
}

class _CreateAttendanceScreenState extends State<CreateAttendanceScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _numberController = TextEditingController();
  final _employeeIdController = TextEditingController();
  final CreateEmployeeViewModel _viewModel = CreateEmployeeViewModel();

  @override
  void dispose() {
    _nameController.dispose();
    _numberController.dispose();
    _employeeIdController.dispose();
    _viewModel.dispose();
    super.dispose();
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _captureFace() async {
    final embeddings = await Navigator.push<List<List<double>>>(
      context,
      MaterialPageRoute(
        builder: (context) => const FaceScanScreen(
          mode: FaceScanMode.enroll,
          title: 'Face Enrollment',
        ),
      ),
    );

    if (embeddings == null || !mounted) return;

    _viewModel.setFaceEmbeddings(embeddings);
    _showSnackBar('Face profile captured successfully');
  }

  Future<void> _saveAttendance() async {
    if (!_formKey.currentState!.validate()) return;

    if (!_viewModel.isFaceVerified) {
      _showSnackBar('Please scan the employee\'s face before submitting');
      return;
    }

    final employee = await _viewModel.save(
      name: _nameController.text.trim(),
      number: _numberController.text.trim(),
      employeeId: _employeeIdController.text.trim(),
    );

    if (employee == null || !mounted) return;

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => AttendanceDetailScreen(employee: employee),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Create Attendance')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Employee Name',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.person),
                ),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'Enter employee name'
                    : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _numberController,

                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Phone Number',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.phone),
                ),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'Enter phone number'
                    : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _employeeIdController,

                decoration: const InputDecoration(
                  labelText: 'Employee ID',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.badge),
                ),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'Enter employee ID'
                    : null,
              ),
              const SizedBox(height: 24),
              ListenableBuilder(
                listenable: _viewModel,
                builder: (context, _) => Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildFaceCaptureCard(),
                    const SizedBox(height: 24),
                    _buildSubmitButton(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFaceCaptureCard() {
    final isVerified = _viewModel.isFaceVerified;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isVerified ? Colors.green.shade50 : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isVerified ? Colors.green : Colors.grey.shade300,
        ),
      ),
      child: Row(
        children: [
          Icon(
            isVerified ? Icons.check_circle : Icons.face,
            color: isVerified ? Colors.green : Colors.grey,
            size: 32,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              isVerified ? 'Face captured' : 'Face not captured',
              style: const TextStyle(fontSize: 15),
            ),
          ),
          ElevatedButton(
            onPressed: _captureFace,
            child: Text(isVerified ? 'Re-scan' : 'Scan Face'),
          ),
        ],
      ),
    );
  }

  Widget _buildSubmitButton() {
    return SizedBox(
      height: 50,
      child: ElevatedButton(
        onPressed: _viewModel.isSaving ? null : _saveAttendance,
        style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
        child: _viewModel.isSaving
            ? const CircularProgressIndicator(color: Colors.white)
            : const Text(
                'Submit Attendance',
                style: TextStyle(color: Colors.white, fontSize: 16),
              ),
      ),
    );
  }
}
