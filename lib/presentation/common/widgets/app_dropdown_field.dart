import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';

/// A labelled dropdown matching [AppFormField]'s look (same label, red
/// "*" for required, border and fill), backed by a fixed list of [T]
/// instead of free text.
class AppDropdownField<T> extends StatelessWidget {
  final String label;
  final String hint;
  final IconData? icon;
  final bool isRequired;
  final T? value;
  final List<T> items;
  final String Function(T item) labelBuilder;
  final ValueChanged<T?> onChanged;
  final FormFieldValidator<T?>? validator;

  const AppDropdownField({
    super.key,
    required this.label,
    required this.hint,
    required this.items,
    required this.labelBuilder,
    required this.onChanged,
    this.icon,
    this.isRequired = false,
    this.value,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text.rich(
          TextSpan(
            text: label,
            style: const TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: AppColors.slate,
            ),
            children: [
              if (isRequired)
                const TextSpan(
                  text: ' *',
                  style: TextStyle(
                    color: AppColors.danger,
                    fontWeight: FontWeight.w700,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<T>(
          initialValue: value,
          isExpanded: true,
          onChanged: onChanged,
          validator: validator,
          dropdownColor: Colors.white,
          style: const TextStyle(fontSize: 15, color: AppColors.ink),
          items: [
            for (final item in items)
              DropdownMenuItem(value: item, child: Text(labelBuilder(item))),
          ],
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(fontSize: 15, color: AppColors.muted),
            counterText: '',
            prefixIcon: icon == null
                ? null
                : Icon(icon, size: 20, color: AppColors.muted),
            filled: true,
            fillColor: Colors.white,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 14,
            ),
            border: _border(AppColors.cardBorder),
            enabledBorder: _border(AppColors.cardBorder),
            focusedBorder: _border(AppColors.deepGreen),
          ),
        ),
      ],
    );
  }

  OutlineInputBorder _border(Color color) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(8),
    borderSide: BorderSide(color: color),
  );
}
