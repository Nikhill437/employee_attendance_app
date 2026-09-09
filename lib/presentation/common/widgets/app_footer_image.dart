import 'package:flutter/material.dart';

/// The decorative palm strip along the bottom of the form screens.
class AppFooterImage extends StatelessWidget {
  const AppFooterImage({super.key});

  @override
  Widget build(BuildContext context) {
    return const IgnorePointer(
      child: Image(image: AssetImage('assets/bg/footer.png'), width: 420),
    );
  }
}
