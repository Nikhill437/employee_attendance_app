import 'package:flutter/material.dart';

/// The eStove lock-up and tagline that opens every green screen.
class BrandHeader extends StatelessWidget {
  final double logoWidth;
  final double logoHeight;

  /// Hidden on screens where the lock-up alone is the header.
  final bool showTagline;

  const BrandHeader({
    super.key,
    this.logoWidth = 180,
    this.logoHeight = 120,
    this.showTagline = true,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Image(
          image: const AssetImage('assets/logo/top-branding.png'),
          width: logoWidth,
          height: logoHeight,
        ),
        if (showTagline)
          const Text(
            'SMART ATTENDANCE SYSTEM',
            style: TextStyle(
              fontSize: 13,
              letterSpacing: 1.2,
              color: Colors.white70,
            ),
          ),
      ],
    );
  }
}
