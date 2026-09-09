import 'package:flutter/material.dart';

/// An underlined text link ("Cancel Scan", "Forget Password?").
///
/// Uses opaque hit testing and its own padding so the tap target covers more
/// than the glyphs themselves.
class AppLinkText extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final double fontSize;

  const AppLinkText({
    super.key,
    required this.label,
    required this.onTap,
    this.fontSize = 15,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: fontSize,
            color: Colors.white,
            fontWeight: FontWeight.w600,
            decoration: TextDecoration.underline,
            decorationColor: Colors.white,
          ),
        ),
      ),
    );
  }
}
