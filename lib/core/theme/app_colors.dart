import 'package:flutter/material.dart';

/// The palette shared by every screen. Defined once here so a colour is never
/// re-typed as a raw hex literal in a widget.
class AppColors {
  const AppColors._();

  // --- Brand backdrop (the green screens) ---
  static const Color gradientTop = Color(0xFF114319);
  static const Color gradientBottom = Color(0xFF1D6122);

  /// Accent used for primary actions and highlights on the green backdrop.
  static const Color lime = Color(0xFFE2FF6B);

  /// Label colour on top of [lime].
  static const Color onLime = Color(0xFF0D4A1C);

  // --- Light surfaces (the dashboard) ---
  static const Color deepGreen = Color(0xFF14532D);
  static const Color pageGrey = Color(0xFFF7F8F7);
  static const Color cardBorder = Color(0xFFE6E8E6);
  static const Color ink = Color(0xFF111827);
  static const Color slate = Color(0xFF374151);
  static const Color muted = Color(0xFF6B7280);

  // --- Status ---
  static const Color success = Color(0xFF15803D);
  static const Color warning = Color(0xFFF59E0B);
  static const Color danger = Color(0xFFEF4444);
}
