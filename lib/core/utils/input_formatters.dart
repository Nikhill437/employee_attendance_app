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
}
