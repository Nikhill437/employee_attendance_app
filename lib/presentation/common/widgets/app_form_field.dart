import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_colors.dart';

/// A labelled, outlined field for the light-background forms.
///
/// [AppTextField] is its counterpart on the green screens; this one keeps a
/// dark label and a hairline border to sit on white cards.
class AppFormField extends StatelessWidget {
  final String label;
  final String hint;
  final IconData? icon;
  final TextEditingController controller;
  final FormFieldValidator<String>? validator;
  final TextInputType? keyboardType;
  final int minLines;
  final int maxLines;

  /// When set the field is read-only and taps run this instead of the
  /// keyboard — used by the date picker.
  final VoidCallback? onTap;

  /// Restricts what can be typed — e.g. letters-only for a name field —
  /// rather than just rejecting it after the fact on submit.
  final List<TextInputFormatter>? inputFormatters;

  /// Hard cap on input length, enforced as the user types.
  final int? maxLength;

  /// Marks the label with a red "*" — purely visual, the validator is still
  /// what actually enforces the field.
  final bool isRequired;

  const AppFormField({
    super.key,
    required this.label,
    required this.hint,
    required this.controller,
    this.icon,
    this.validator,
    this.keyboardType,
    this.minLines = 1,
    this.maxLines = 1,
    this.onTap,
    this.inputFormatters,
    this.maxLength,
    this.isRequired = false,
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
        TextFormField(
          controller: controller,
          validator: validator,
          keyboardType: keyboardType,
          minLines: minLines,
          maxLines: maxLines,
          readOnly: onTap != null,
          onTap: onTap,
          inputFormatters: inputFormatters,
          maxLength: maxLength,
          style: const TextStyle(fontSize: 15, color: AppColors.ink),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(fontSize: 15, color: AppColors.muted),
            // The field already looks complete without the "0/100"
            // character counter cluttering every field that sets maxLength.
            counterText: '',
            prefixIcon: icon == null
                ? null
                : Padding(
                    // Keeps the icon at the top of a multi-line field rather
                    // than floating in its vertical centre.
                    padding: EdgeInsets.only(bottom: maxLines > 1 ? 44 : 0),
                    child: Icon(icon, size: 20, color: AppColors.muted),
                  ),
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
