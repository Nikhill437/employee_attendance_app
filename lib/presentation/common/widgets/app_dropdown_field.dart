import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/app_selection_sheet.dart';

/// A labelled dropdown matching [AppFormField]'s look (same label, red
/// "*" for required, border and fill). Tapping it opens the options in a
/// bottom sheet (see showAppSelectionSheet) instead of a popup menu.
/// Works inside a Form: [validator] runs with the current [value].
class AppDropdownField<T> extends StatefulWidget {
  final String label;
  final String hint;
  final IconData? icon;
  final bool isRequired;
  final T? value;
  final List<T> items;
  final String Function(T item) labelBuilder;
  final ValueChanged<T?> onChanged;
  final FormFieldValidator<T?>? validator;

  /// False shows the field greyed out and stops it opening.
  final bool enabled;

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
    this.enabled = true,
  });

  @override
  State<AppDropdownField<T>> createState() => _AppDropdownFieldState<T>();
}

class _AppDropdownFieldState<T> extends State<AppDropdownField<T>> {
  Future<void> _open(FormFieldState<T> field) async {
    final picked = await showAppSelectionSheet<T>(
      context: context,
      title: widget.label,
      items: widget.items,
      labelBuilder: widget.labelBuilder,
      selected: widget.value,
    );
    if (picked == null) return;
    field.didChange(picked);
    widget.onChanged(picked);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text.rich(
          TextSpan(
            text: widget.label,
            style: const TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: AppColors.slate,
            ),
            children: [
              if (widget.isRequired)
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
        FormField<T>(
          initialValue: widget.value,
          // Reads the current value from the widget, not the field's own
          // state, so a value set from outside (e.g. the supervisor's
          // department loaded after build) is validated correctly.
          validator: (_) => widget.validator?.call(widget.value),
          builder: (field) {
            final value = widget.value;
            final borderColor = field.hasError
                ? AppColors.danger
                : AppColors.cardBorder;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: !widget.enabled || widget.items.isEmpty
                      ? null
                      : () => _open(field),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      color: widget.enabled
                          ? Colors.white
                          : const Color(0xFFF2F3F2),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: borderColor),
                    ),
                    child: Row(
                      children: [
                        if (widget.icon != null) ...[
                          Icon(widget.icon, size: 20, color: AppColors.muted),
                          const SizedBox(width: 10),
                        ],
                        Expanded(
                          child: Text(
                            value == null
                                ? widget.hint
                                : widget.labelBuilder(value),
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 15,
                              color: value == null
                                  ? AppColors.muted
                                  : AppColors.ink,
                            ),
                          ),
                        ),
                        const Icon(
                          Icons.keyboard_arrow_down_rounded,
                          color: AppColors.muted,
                        ),
                      ],
                    ),
                  ),
                ),
                if (field.hasError)
                  Padding(
                    padding: const EdgeInsets.only(left: 14, top: 6),
                    child: Text(
                      field.errorText!,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.danger,
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}
