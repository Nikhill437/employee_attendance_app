import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';

/// The numbered "1 Details → 2 Face Capture → 3 Complete" progress strip.
class AppStepIndicator extends StatelessWidget {
  final List<String> steps;

  /// Zero-based index of the step currently in progress.
  final int currentStep;

  const AppStepIndicator({
    super.key,
    required this.steps,
    required this.currentStep,
  });

  @override
  Widget build(BuildContext context) {
    // The three steps are wider than a narrow phone, so the strip scrolls
    // sideways rather than overflowing its card.
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < steps.length; i++) ...[
            if (i > 0)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 6),
                child: Icon(
                  Icons.arrow_right_alt,
                  size: 16,
                  color: AppColors.muted,
                ),
              ),
            _Step(
              index: i,
              label: steps[i],
              isActive: i == currentStep,
              isComplete: i < currentStep,
            ),
          ],
        ],
      ),
    );
  }
}

class _Step extends StatelessWidget {
  final int index;
  final String label;
  final bool isActive;
  final bool isComplete;

  const _Step({
    required this.index,
    required this.label,
    required this.isActive,
    this.isComplete = false,
  });

  /// A finished step reads as done, so it is filled like the active one.
  bool get _isFilled => isActive || isComplete;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 22,
          height: 22,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _isFilled ? AppColors.deepGreen : const Color(0xFFE6E8E6),
          ),
          child: isComplete
              ? const Icon(Icons.check, size: 13, color: Colors.white)
              : Text(
                  '${index + 1}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: isActive ? Colors.white : AppColors.muted,
                  ),
                ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: _isFilled ? FontWeight.w700 : FontWeight.w500,
            color: _isFilled ? AppColors.ink : AppColors.muted,
          ),
        ),
      ],
    );
  }
}
