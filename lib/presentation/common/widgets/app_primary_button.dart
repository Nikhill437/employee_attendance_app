import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';

/// The full-width action button used at the foot of every form and card.
///
/// Defaults to the lime-on-green treatment; pass [background]/[foreground]
/// for the white and deep-green variants.
class AppPrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final Color background;
  final Color foreground;
  final IconData? icon;

  /// Replaces [icon] with a spinner and is what disables the button while an
  /// action is in flight.
  final bool isBusy;

  const AppPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.background = AppColors.lime,
    this.foreground = AppColors.onLime,
    this.icon,
    this.isBusy = false,
  });

  @override
  Widget build(BuildContext context) {
    final style = ElevatedButton.styleFrom(
      backgroundColor: background,
      foregroundColor: foreground,
      disabledBackgroundColor: background.withValues(alpha: 0.6),
      minimumSize: const Size(double.infinity, 56),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 0,
    );
    final text = Text(
      label,
      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
    );

    if (icon == null && !isBusy) {
      return ElevatedButton(
        style: style,
        onPressed: isBusy ? null : onPressed,
        child: text,
      );
    }

    return ElevatedButton.icon(
      style: style,
      onPressed: isBusy ? null : onPressed,
      icon: isBusy
          ? SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: foreground,
              ),
            )
          : Icon(icon),
      label: text,
    );
  }
}
