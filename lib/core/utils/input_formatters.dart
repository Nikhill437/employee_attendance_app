import 'package:flutter/services.dart';

/// Shared [TextInputFormatter] sets, reused wherever the same input rule
/// applies on more than one screen.
class AppInputFormatters {
  const AppInputFormatters._();

  /// National ID formatting: letters and digits only, letters forced to
  /// uppercase as the user types — applied identically on enrollment and on
  /// the attendance ID lookup so a worker's typed ID always matches what was
  /// stored for them at enrollment.
  static List<TextInputFormatter> get alphanumericUppercase => [
    FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9]')),
    TextInputFormatter.withFunction(
      (oldValue, newValue) =>
          newValue.copyWith(text: newValue.text.toUpperCase()),
    ),
  ];

  /// Date of birth formatting: digits only as typed (any `/` the user types
  /// is stripped first), auto-inserting `/` after the day and month digit
  /// pairs so the result always reads DD/MM/YYYY — the same format
  /// DateTimeFormatter.dateOfBirth produces when a date is picked instead
  /// of typed, so the enrollment form's own parser can read either back.
  static List<TextInputFormatter> get dateOfBirth => [
    FilteringTextInputFormatter.digitsOnly,
    LengthLimitingTextInputFormatter(8),
    TextInputFormatter.withFunction((oldValue, newValue) {
      final digits = newValue.text;
      final buffer = StringBuffer();
      for (var i = 0; i < digits.length; i++) {
        if (i == 2 || i == 4) buffer.write('/');
        buffer.write(digits[i]);
      }
      final formatted = buffer.toString();
      return TextEditingValue(
        text: formatted,
        selection: TextSelection.collapsed(offset: formatted.length),
      );
    }),
  ];
}
