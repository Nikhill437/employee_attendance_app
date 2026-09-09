import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Draws a dashed ring. Flutter has no dashed border, so the circle is
/// stroked as a series of arcs with equal gaps between them.
class DashedCirclePainter extends CustomPainter {
  final Color color;
  final double strokeWidth;
  final int dashCount;

  /// Share of each segment that is drawn; the remainder is the gap.
  final double dashFraction;

  const DashedCirclePainter({
    required this.color,
    this.strokeWidth = 4,
    this.dashCount = 46,
    this.dashFraction = 0.55,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    final inset = strokeWidth / 2;
    final rect = Rect.fromLTWH(
      inset,
      inset,
      size.width - strokeWidth,
      size.height - strokeWidth,
    );
    final segment = 2 * math.pi / dashCount;
    for (var i = 0; i < dashCount; i++) {
      canvas.drawArc(rect, i * segment, segment * dashFraction, false, paint);
    }
  }

  @override
  bool shouldRepaint(DashedCirclePainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.strokeWidth != strokeWidth ||
      oldDelegate.dashCount != dashCount ||
      oldDelegate.dashFraction != dashFraction;
}
