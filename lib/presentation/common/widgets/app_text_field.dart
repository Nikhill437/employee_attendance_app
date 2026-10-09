import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A labelled, white-filled form field as used on the green screens.
class AppTextField extends StatelessWidget {
  final String label;
  final String hint;
  final IconData icon;
  final TextEditingController controller;
  final FormFieldValidator<String>? validator;
  final TextInputType? keyboardType;
  final TextInputAction textInputAction;
  final ValueChanged<String>? onSubmitted;
  final bool obscureText;

  /// Trailing action inside the field, e.g. a show/hide password toggle.
  final Widget? suffixIcon;

  /// Restricts what can be typed — e.g. alphanumeric-only for an ID field.
  final List<TextInputFormatter>? inputFormatters;

  /// Hard cap on input length, enforced as the user types (and on paste).
  /// Hidden counter — same as AppFormField — so this doesn't clutter the
  /// field with a "0/20" display.
  final int? maxLength;

  const AppTextField({
    super.key,
    required this.label,
    required this.hint,
    required this.icon,
    required this.controller,
    this.validator,
    this.keyboardType,
    this.textInputAction = TextInputAction.next,
    this.onSubmitted,
    this.obscureText = false,
    this.inputFormatters,
    this.maxLength,
    this.suffixIcon,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label, style: const TextStyle(color: Colors.white, fontSize: 14)),
        const SizedBox(height: 5),
        TextFormField(
          controller: controller,
          validator: validator,
          keyboardType: keyboardType,
          textInputAction: textInputAction,
          onFieldSubmitted: onSubmitted,
          obscureText: obscureText,
          inputFormatters: inputFormatters,
          maxLength: maxLength,
          autocorrect: false,
          enableSuggestions: false,
          style: const TextStyle(color: Colors.black),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: Colors.grey),
            prefixIcon: Icon(icon, color: Colors.grey),
            suffixIcon: suffixIcon,
            filled: true,
            fillColor: Colors.white,
            // The field already looks complete without the "0/20" character
            // counter cluttering it.
            counterText: '',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
            ),
          ),
        ),
      ],
    );
  }
}
