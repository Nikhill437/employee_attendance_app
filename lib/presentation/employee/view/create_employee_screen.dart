import 'package:employee_attendance_app/attendance_detail_screen.dart';
import 'package:flutter/material.dart';
import 'database_helper.dart';
import 'employee_model.dart';
import 'face_scan_screen.dart';

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

  final DatabaseHelper _dbHelper = DatabaseHelper();

  bool _isFaceVerified = false;
  bool _isSaving = false;
  List<List<double>>? _faceEmbeddings;

  @override
  void dispose() {
    _nameController.dispose();
    _numberController.dispose();
    _employeeIdController.dispose();
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
          title: 'Scan Your Face',
        ),
      ),
    );

    if (embeddings == null) return;

    setState(() {
      _faceEmbeddings = embeddings;
      _isFaceVerified = true;
    });
    _showSnackBar('Face profile captured successfully');
  }

  Future<void> _saveAttendance() async {
    if (!_formKey.currentState!.validate()) return;

    if (!_isFaceVerified || _faceEmbeddings == null) {
      _showSnackBar('Please scan the employee\'s face before submitting');
      return;
    }

    setState(() => _isSaving = true);

    final employee = Employee(
      name: _nameController.text.trim(),
      number: _numberController.text.trim(),
      employeeId: _employeeIdController.text.trim(),
      attendanceTime: DateTime.now().toIso8601String(),
      faceVerified: true,
      faceEmbeddings: _faceEmbeddings!,
    );

    final insertedId = await _dbHelper.insertAttendance(employee);

    setState(() => _isSaving = false);

    if (!mounted) return;

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => AttendanceDetailScreen(
          employee: Employee(
            id: insertedId,
            name: employee.name,
            number: employee.number,
            employeeId: employee.employeeId,
            attendanceTime: employee.attendanceTime,
            faceVerified: employee.faceVerified,
            faceEmbeddings: employee.faceEmbeddings,
          ),
        ),
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
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _isFaceVerified
                      ? Colors.green.shade50
                      : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _isFaceVerified
                        ? Colors.green
                        : Colors.grey.shade300,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      _isFaceVerified ? Icons.check_circle : Icons.face,
                      color: _isFaceVerified ? Colors.green : Colors.grey,
                      size: 32,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _isFaceVerified ? 'Face captured' : 'Face not captured',
                        style: const TextStyle(fontSize: 15),
                      ),
                    ),
                    ElevatedButton(
                      onPressed: _captureFace,
                      child: Text(_isFaceVerified ? 'Re-scan' : 'Scan Face'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                height: 50,
                child: ElevatedButton(
                  onPressed: _isSaving ? null : _saveAttendance,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                  ),
                  child: _isSaving
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text(
                          'Submit Attendance',
                          style: TextStyle(color: Colors.white, fontSize: 16),
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
