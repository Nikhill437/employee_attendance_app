import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';

/// A labelled row of mutually exclusive pill options (gender, pay type…).
///
/// [T] is whatever the caller wants back — an enum, a string, anything.
class AppOptionSelector<T> extends StatelessWidget {
  final String label;
  final List<T> options;
  final T selected;
  final ValueChanged<T> onSelected;

  /// How each option is titled.
  final String Function(T option) labelBuilder;

  final Color selectedBackground;
  final Color selectedForeground;

  /// False makes every pill non-interactive (still shows which is
  /// selected, just can't be changed) — e.g. Gender/Enrollment Type when
  /// editing an existing worker.
  final bool enabled;

  const AppOptionSelector({
    super.key,
    required this.label,
    required this.options,
    required this.selected,
    required this.onSelected,
    required this.labelBuilder,
    this.selectedBackground = AppColors.deepGreen,
    this.selectedForeground = Colors.white,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w600,
            color: AppColors.slate,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final option in options)
              _OptionPill(
                label: labelBuilder(option),
                isSelected: option == selected,
                selectedBackground: selectedBackground,
                selectedForeground: selectedForeground,
                enabled: enabled,
                onTap: () => onSelected(option),
              ),
          ],
        ),
      ],
    );
  }
}

class _OptionPill extends StatelessWidget {
  final String label;
  final bool isSelected;
  final Color selectedBackground;
  final Color selectedForeground;
  final bool enabled;
  final VoidCallback onTap;

  const _OptionPill({
    required this.label,
    required this.isSelected,
    required this.selectedBackground,
    required this.selectedForeground,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.6,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? onTap : null,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? selectedBackground : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isSelected ? selectedBackground : AppColors.cardBorder,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: isSelected ? selectedForeground : AppColors.ink,
            ),
          ),
        ),
      ),
    );
  }
}
