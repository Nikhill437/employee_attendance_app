import 'package:flutter/material.dart';

/// The eStove lock-up and tagline that opens every green screen.
class BrandHeader extends StatelessWidget {
  final double? logoWidth;
  final double? logoHeight;

  /// Hidden on screens where the lock-up alone is the header.
  final bool showTagline;

  const BrandHeader({
    super.key,
    this.logoWidth,
    this.logoHeight,
    this.showTagline = true,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Image(
          image: AssetImage('assets/logo/logo.png'),
          fit: BoxFit.contain,
        ),
        SizedBox(height: 10),
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
