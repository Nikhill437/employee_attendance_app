import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';

/// Full-screen gradient backdrop shared by the auth screens.
///
/// Deliberately not a [Scaffold] itself — it is meant to sit *inside* one, as
/// the body wrapping the screen's content, so the hosting screen keeps its
/// own app bar, snack bars and insets. Give the host
/// `backgroundColor: Colors.transparent` so nothing paints over the gradient.
class BackgroundScreen extends StatelessWidget {
  /// The screen content drawn on top of the gradient.
  final Widget? child;

  const BackgroundScreen({super.key, this.child});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.gradientTop, AppColors.gradientBottom],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: SizedBox.expand(child: child),
    );
  }
}
