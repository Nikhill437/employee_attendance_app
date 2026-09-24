import 'package:flutter/material.dart';

import '../../presentation/common/widgets/app_bottom_nav_bar.dart';
import 'app_routes.dart';

/// The route each bottom-nav section opens, or null while that section has
/// no screen of its own yet.
extension AppSectionRoute on AppSection {
  String? get routeName => switch (this) {
    AppSection.dashboard => AppRoutes.dashboard,
    AppSection.workers => AppRoutes.workerList,
    AppSection.settings => AppRoutes.settings,
    AppSection.reports => AppRoutes.workerHistory,
  };
}

/// Handles a bottom-nav tap consistently across every screen that shows one.
///
/// Tapping the section already on screen does nothing. Tapping another
/// resets the stack back to its root and pushes that section's screen, so
/// the highlighted tab always matches what's actually displayed — a screen
/// can declare a fixed `current` (its own section) instead of tracking
/// mutable, easily-stale state. Tapping a section with no screen yet says so
/// instead of silently doing nothing.
void switchToSection(
  BuildContext context,
  AppSection current,
  AppSection target,
) {
  if (target == current) return;

  final routeName = target.routeName;
  if (routeName == null) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('${target.label} is coming soon')));
    return;
  }

  Navigator.pushNamedAndRemoveUntil(
    context,
    routeName,
    (route) => route.isFirst,
  );
}
