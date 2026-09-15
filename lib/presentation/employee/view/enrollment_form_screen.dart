import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/routes/section_navigation.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/date_time_formatter.dart';
import '../../../data/models/enrollment_draft_model.dart';
import '../../../data/models/worker_model.dart';
import '../../common/widgets/common_widgets.dart';
import '../../face_scan/view/face_capture_screen.dart';
import '../viewmodel/create_employee_viewmodel.dart';
import '../viewmodel/enrollment_form_viewmodel.dart';
import 'enrollment_complete_screen.dart';

/// Step 1 of enrollment: the worker's personal details, before the face
/// capture on step 2.
class EnrollmentFormScreen extends StatefulWidget {
  const EnrollmentFormScreen({super.key});

  @override
  State<EnrollmentFormScreen> createState() => _EnrollmentFormScreenState();
}

class _EnrollmentFormScreenState extends State<EnrollmentFormScreen> {
  static const List<String> _steps = ['Details', 'Face Capture', 'Complete'];

  static const int _fullNameMaxLength = 100;

  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _dobController = TextEditingController();
  final _nationalIdController = TextEditingController();
  final _phoneController = TextEditingController();
  final _addressController = TextEditingController();
  final _departmentController = TextEditingController();

  final EnrollmentFormViewModel _formViewModel = EnrollmentFormViewModel();
  final CreateEmployeeViewModel _employeeViewModel = CreateEmployeeViewModel();

  @override
  void dispose() {
    _nameController.dispose();
    _dobController.dispose();
    _nationalIdController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _departmentController.dispose();
    _formViewModel.dispose();
    _employeeViewModel.dispose();
    super.dispose();
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _pickDateOfBirth() async {
    final now = DateTime.now();
    final selected = await showDatePicker(
      context: context,
      initialDate: _formViewModel.dateOfBirth ?? DateTime(now.year - 25),
      firstDate: DateTime(now.year - 80),
      lastDate: now,
      helpText: 'Select Date of Birth',
    );
    if (selected == null) return;

    _formViewModel.selectDateOfBirth(selected);
    _dobController.text = DateTimeFormatter.dayLabel(selected);
  }

  Future<void> _proceedToFaceCapture() async {
    if (!_formKey.currentState!.validate()) return;
    if (_formViewModel.dateOfBirth == null) {
      _showSnackBar('Select the date of birth');
      return;
    }

    final nationalId = _nationalIdController.text.trim();
    if (await _employeeViewModel.isNationalIdTaken(nationalId)) {
      if (!mounted) return;
      _showSnackBar(
        'National ID $nationalId is already enrolled. Enter a unique ID.',
      );
      return;
    }
    if (!mounted) return;

    final draft = _formViewModel.buildDraft(
      fullName: _nameController.text.trim(),
      nationalId: nationalId,
      phoneNumber: _phoneController.text.trim(),
      address: _addressController.text.trim(),
      department: _departmentController.text.trim(),
    );

    final embeddings = await Navigator.push<List<List<double>>>(
      context,
      MaterialPageRoute(builder: (context) => const FaceCaptureScreen()),
    );
    if (embeddings == null || !mounted) return;

    await _saveEnrollment(draft, embeddings);
  }

  /// Persists the whole draft — the face embeddings just captured plus every
  /// field collected on step 1.
  Future<void> _saveEnrollment(
    EnrollmentDraft draft,
    List<List<double>> embeddings,
  ) async {
    _employeeViewModel.setFaceEmbeddings(embeddings);
    final employee = await _employeeViewModel.save(
      name: draft.fullName,
      number: draft.phoneNumber,
      employeeId: draft.nationalId,
      dateOfBirth: draft.dateOfBirth?.toIso8601String(),
      gender: draft.gender,
      address: draft.address,
      payType: draft.enrollmentType,
      department: draft.department,
    );
    if (employee == null || !mounted) return;

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => EnrollmentCompleteScreen(
          workerName: employee.name,
          systemId: _systemIdFor(employee.id),
          enrollmentType: draft.enrollmentType,
          registeredAt: DateTime.parse(employee.attendanceTime),
        ),
      ),
    );
  }

  /// The database row id, presented the way the design labels it: EMP-048.
  String _systemIdFor(int? rowId) =>
      'EMP-${(rowId ?? 0).toString().padLeft(3, '0')}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.pageGrey,
      body: Column(
        children: [
          const AppScreenHeader(
            title: 'New Enrollment',
            subtitle: 'Supervisor Panel',
            showBack: true,
          ),
          Expanded(
            child: ListenableBuilder(
              listenable: Listenable.merge([
                _formViewModel,
                _employeeViewModel,
              ]),
              child: const AppCard(
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                child: AppStepIndicator(steps: _steps, currentStep: 0),
              ),
              builder: (context, stepIndicator) => ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                children: [
                  stepIndicator!,
                  const SizedBox(height: 16),
                  _buildDetailsCard(),
                  const SizedBox(height: 20),
                  AppPrimaryButton(
                    label: 'Proceed to Face Capture',
                    isBusy: _employeeViewModel.isSaving,
                    onPressed: _proceedToFaceCapture,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: AppBottomNavBar(
        current: AppSection.workers,
        onSectionSelected: (target) =>
            switchToSection(context, AppSection.workers, target),
      ),
    );
  }

  Widget _buildDetailsCard() {
    return AppCard(
      padding: const EdgeInsets.all(18),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppFormField(
              label: 'Full Name',
              isRequired: true,
              hint: 'e.g. Jhon Doe',
              icon: Icons.person_outline,
              controller: _nameController,
              maxLength: _fullNameMaxLength,
              inputFormatters: [
                // Blocks digits and symbols as they're typed rather than
                // rejecting them only after the field is submitted.
                FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z ]')),
              ],
              validator: _validateFullName,
            ),
            const SizedBox(height: 18),
            AppFormField(
              label: 'Date of Birth',
              hint: 'Select Date of Birth',
              icon: Icons.calendar_today_outlined,
              controller: _dobController,
              onTap: _pickDateOfBirth,
            ),
            const SizedBox(height: 18),
            AppOptionSelector<Gender>(
              label: 'Gender',
              options: Gender.values,
              selected: _formViewModel.gender,
              onSelected: _formViewModel.selectGender,
              labelBuilder: (gender) => gender.label,
            ),
            const SizedBox(height: 18),
            AppFormField(
              label: 'National ID',
              isRequired: true,
              hint: 'Enter National ID Card Number',
              icon: Icons.badge_outlined,
              controller: _nationalIdController,
              validator: (v) => _requireText(v, 'Enter the National ID'),
            ),
            const SizedBox(height: 18),
            AppFormField(
              label: 'Phone Number',
              isRequired: true,
              hint: 'e.g. 98765 43210',
              icon: Icons.phone_outlined,
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              validator: _validatePhoneNumber,
            ),
            const SizedBox(height: 18),
            AppFormField(
              label: 'Department',
              hint: 'e.g. Site Operations',
              icon: Icons.apartment_outlined,
              controller: _departmentController,
              validator: (v) => _requireText(v, 'Enter the department'),
            ),
            const SizedBox(height: 18),
            AppFormField(
              label: 'Address',
              isRequired: true,
              hint: 'Enter permanent residential address...',
              controller: _addressController,
              minLines: 3,
              maxLines: 4,
              validator: (v) => _requireText(v, 'Enter the address'),
            ),
            const SizedBox(height: 18),
            AppOptionSelector<PayType>(
              label: 'Enrollment Type',
              options: PayType.values,
              selected: _formViewModel.enrollmentType,
              onSelected: _formViewModel.selectEnrollmentType,
              labelBuilder: (type) => type.label,
              selectedBackground: const Color(0xFFD6E4FB),
              selectedForeground: const Color(0xFF1565C0),
            ),
          ],
        ),
      ),
    );
  }

  String? _requireText(String? value, String message) =>
      (value == null || value.trim().isEmpty) ? message : null;

  String? _validateFullName(String? value) {
    final name = value?.trim() ?? '';
    if (name.isEmpty) return 'Enter the full name';
    if (name.length > _fullNameMaxLength) {
      return 'Full name must be $_fullNameMaxLength characters or fewer';
    }
    // The input formatter already blocks these as the supervisor types, but
    // a name pasted in some other way could still slip through.
    if (!RegExp(r'^[a-zA-Z ]+$').hasMatch(name)) {
      return 'Full name can only contain letters and spaces';
    }
    return null;
  }

  String? _validatePhoneNumber(String? value) {
    final digitsOnly = (value ?? '').replaceAll(RegExp(r'\s+'), '');
    if (digitsOnly.isEmpty) return 'Enter the phone number';
    // Loose E.164-style check — an optional country-code '+' followed by
    // 7-15 digits — rather than a strict per-country format.
    if (!RegExp(r'^\+?[0-9]{7,15}$').hasMatch(digitsOnly)) {
      return 'Enter a valid phone number';
    }

    if (digitsOnly.length != 10) {
      return 'Enter 10 digits mobile number';
    }
    return null;
  }
}
