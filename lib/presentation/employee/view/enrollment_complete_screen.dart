import 'package:flutter/material.dart';

import '../../../core/routes/app_routes.dart';
import '../../../core/routes/section_navigation.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/date_time_formatter.dart';
import '../../../data/models/worker_model.dart';
import '../../common/widgets/common_widgets.dart';

/// Step 3 of enrollment: confirms the worker was registered and offers the
/// two ways on from here.
class EnrollmentCompleteScreen extends StatelessWidget {
  final String workerName;

  /// The identifier the system assigned, e.g. `EMP-048`.
  final String systemId;

  final PayType enrollmentType;
  final DateTime registeredAt;

  const EnrollmentCompleteScreen({
    super.key,
    required this.workerName,
    required this.systemId,
    required this.enrollmentType,
    required this.registeredAt,
  });

  static const List<String> _steps = ['Details', 'Face Capture', 'Complete'];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.pageGrey,
      body: Column(
        children: [
          const AppScreenHeader(
            title: 'Enrollment Complete',
            subtitle: 'Confirmation',
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              children: [
                const AppCard(
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                  child: AppStepIndicator(steps: _steps, currentStep: 2),
                ),
                const SizedBox(height: 36),
                _buildSuccessBadge(),
                const SizedBox(height: 24),
                const Text(
                  'Enrollment Successful!',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'The worker face profile has been registered.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14.5, color: AppColors.muted),
                ),
                const SizedBox(height: 24),
                _buildIdentityCard(),
                const SizedBox(height: 24),
                AppPrimaryButton(
                  label: 'Back to Worker List',
                  background: AppColors.deepGreen,
                  foreground: Colors.white,
                  onPressed: () => _openWorkerList(context),
                ),
                const SizedBox(height: 14),
                AppSecondaryButton(
                  label: 'Enroll Another Worker',
                  onPressed: () => _startAnotherEnrollment(context),
                ),
              ],
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

  /// Drops the finished enrollment out of the stack on the way to the list.
  void _openWorkerList(BuildContext context) {
    Navigator.pushNamedAndRemoveUntil(
      context,
      AppRoutes.workerList,
      (route) => route.isFirst,
    );
  }

  void _startAnotherEnrollment(BuildContext context) {
    Navigator.pushReplacementNamed(context, AppRoutes.enrollmentForm);
  }

  Widget _buildSuccessBadge() {
    return Center(
      child: Container(
        width: 84,
        height: 84,
        decoration: const BoxDecoration(
          color: AppColors.lime,
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.check, size: 42, color: Color(0xFF1B3A16)),
      ),
    );
  }

  Widget _buildIdentityCard() {
    return AppCard(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Worker Identity Details',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(height: 6),
          _DetailRow(
            label: 'Worker Name',
            value: Text(workerName, style: _valueStyle),
          ),
          _DetailRow(
            label: 'System ID',
            value: Text(
              systemId,
              style: _valueStyle.copyWith(color: AppColors.success),
            ),
          ),
          _DetailRow(
            label: 'Enrollment Type',
            value: PayTypeChip(payType: enrollmentType),
          ),
          _DetailRow(
            label: 'Registration Date',
            value: Text(_registrationLabel, style: _valueStyle),
            showDivider: false,
          ),
        ],
      ),
    );
  }

  /// Reads as "Today, Oct 24, 2026" on the day of enrollment, and drops the
  /// prefix when the record is viewed later.
  String get _registrationLabel {
    final date = DateTimeFormatter.dayLabel(registeredAt);
    return DateTimeFormatter.isSameDay(registeredAt, DateTime.now())
        ? 'Today, $date'
        : date;
  }

  static const TextStyle _valueStyle = TextStyle(
    fontSize: 14.5,
    fontWeight: FontWeight.w700,
    color: AppColors.ink,
  );
}

/// One label/value line of the identity card, with a hairline beneath it.
class _DetailRow extends StatelessWidget {
  final String label;
  final Widget value;
  final bool showDivider;

  const _DetailRow({
    required this.label,
    required this.value,
    this.showDivider = true,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 14.5,
                    color: AppColors.muted,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              value,
            ],
          ),
        ),
        if (showDivider) const Divider(height: 1, color: AppColors.cardBorder),
      ],
    );
  }
}
