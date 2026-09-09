import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../common/widgets/common_widgets.dart';

/// Confirmation shown once attendance has been marked, handing the employee
/// the PIN they use to log their work for the rest of the day.
class PinScreen extends StatelessWidget {
  /// The digits to display. Rendered one per box, so any length works, but
  /// the design is built around four.
  final String pin;

  const PinScreen({super.key, required this.pin});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: BackgroundScreen(
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Column(
              children: [
                const SizedBox(height: 24),
                const BrandHeader(),
                const SizedBox(height: 60),
                _buildSuccessBadge(),
                const SizedBox(height: 28),
                const Text(
                  'Attendance Marked!',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'YOUR DAILY PIN',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                    color: AppColors.lime,
                  ),
                ),
                const SizedBox(height: 20),
                _buildPinCard(),
                const SizedBox(height: 28),
                AppPrimaryButton(
                  label: 'Done',
                  background: Colors.white,
                  foreground: Colors.black,
                  // Unwinds the scan stack the employee arrived through.
                  onPressed: () =>
                      Navigator.of(context).popUntil((route) => route.isFirst),
                ),
                const SizedBox(height: 40),
                const AppVersionLabel(),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSuccessBadge() {
    return Container(
      width: 84,
      height: 84,
      decoration: const BoxDecoration(
        color: AppColors.lime,
        shape: BoxShape.circle,
      ),
      child: const Icon(Icons.check, size: 42, color: Color(0xFF11311A)),
    );
  }

  Widget _buildPinCard() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (final digit in pin.split(''))
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: _buildDigitBox(digit),
                ),
            ],
          ),
          const SizedBox(height: 16),
          const Text(
            'Use this PIN to log your work today',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: Colors.white60),
          ),
        ],
      ),
    );
  }

  Widget _buildDigitBox(String digit) {
    return Container(
      width: 62,
      height: 66,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        digit,
        style: const TextStyle(
          fontSize: 30,
          fontWeight: FontWeight.w700,
          color: Colors.black,
        ),
      ),
    );
  }
}
