import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';

/// Outlined counterpart to [AppPrimaryButton], for the lesser of two actions.
class AppSecondaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final Color color;

  const AppSecondaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.color = AppColors.deepGreen,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        minimumSize: const Size(double.infinity, 56),
        side: BorderSide(color: color, width: 1.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      ),
    );
  }
}
