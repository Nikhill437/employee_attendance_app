import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';

/// White rounded panel that every dashboard section sits in.
class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;

  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: child,
    );
  }
}

/// The small upper-case caption that titles each card.
class SectionLabel extends StatelessWidget {
  final String text;

  const SectionLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 11.5,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.6,
        color: AppColors.muted,
      ),
    );
  }
}

/// A coloured bullet followed by a caption, as used by the status rows.
class DotLabel extends StatelessWidget {
  final String text;
  final Color color;
  final double fontSize;

  const DotLabel({
    super.key,
    required this.text,
    required this.color,
    this.fontSize = 13,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.circle, size: 8, color: color),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            text,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: fontSize, color: AppColors.slate),
          ),
        ),
      ],
    );
  }
}
