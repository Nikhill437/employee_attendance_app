import 'package:flutter/material.dart';

import '../../../data/models/worker_model.dart';

/// The small colour-coded chip naming how a worker is paid.
class PayTypeChip extends StatelessWidget {
  final PayType payType;

  const PayTypeChip({super.key, required this.payType});

  @override
  Widget build(BuildContext context) {
    final (background, foreground) = switch (payType) {
      PayType.daily => (const Color(0xFFE3F0FD), const Color(0xFF1565C0)),
      PayType.monthly => (const Color(0xFFF2E7FA), const Color(0xFF6A1B9A)),
      PayType.taskBased => (const Color(0xFFFDECD9), const Color(0xFFC2570B)),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        payType.label,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
          color: foreground,
        ),
      ),
    );
  }
}
