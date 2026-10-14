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
  final ValueChanged<String>? onChanged;
  final TextInputType? keyboardType;
  final int minLines;
  final int maxLines;

  /// Runs on every tap, regardless of [readOnly] — e.g. opening a date
  /// picker alongside still-typable text (see [readOnly]'s own doc comment).
  final VoidCallback? onTap;

  /// True blocks the keyboard entirely, so [onTap] (typically a picker) is
  /// the only way to set the field. False (the default) leaves it typable
  /// even when [onTap] is also set — e.g. Date of Birth, where the
  /// supervisor can either type a date directly or tap the calendar
  /// [suffixIcon] to pick one instead.
  final bool readOnly;

  /// An icon shown at the field's trailing edge, separate from the leading
  /// [icon] — typically a tappable calendar/picker affordance that doesn't
  /// block typing the way [readOnly] would.
  final Widget? suffixIcon;

  /// Restricts what can be typed — e.g. letters-only for a name field —
  /// rather than just rejecting it after the fact on submit.
  final List<TextInputFormatter>? inputFormatters;

  /// Hard cap on input length, enforced as the user types.
  final int? maxLength;

  /// Marks the label with a red "*" — purely visual, the validator is still
  /// what actually enforces the field.
  final bool isRequired;

  /// False greys the field out and blocks editing — e.g. every field but
  /// Department when editing an existing worker.
  final bool enabled;

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
    this.readOnly = false,
    this.suffixIcon,
    this.onChanged,
    this.inputFormatters,
    this.maxLength,
    this.isRequired = false,
    this.enabled = true,
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
          onChanged: onChanged,
          keyboardType: keyboardType,
          minLines: minLines,
          maxLines: maxLines,
          readOnly: readOnly,
          enabled: enabled,
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
            suffixIcon: suffixIcon,
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
