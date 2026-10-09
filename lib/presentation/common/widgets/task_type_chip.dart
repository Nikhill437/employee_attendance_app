import 'package:flutter/material.dart';

import '../../../data/models/department_model.dart';

/// The small colour-coded chip naming a worker's currently assigned task's
/// type.
class TaskTypeChip extends StatelessWidget {
  final TaskType taskType;

  const TaskTypeChip({super.key, required this.taskType});

  @override
  Widget build(BuildContext context) {
    final (background, foreground) = switch (taskType) {
      TaskType.daily => (const Color(0xFFE3F0FD), const Color(0xFF1565C0)),
      TaskType.monthly => (const Color(0xFFF2E7FA), const Color(0xFF6A1B9A)),
      TaskType.taskBased => (
        const Color(0xFFFDECD9),
        const Color(0xFFC2570B),
      ),
      TaskType.hourBased => (
        const Color(0xFFE3F6E8),
        const Color(0xFF2E9E4F),
      ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        taskType.label,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
          color: foreground,
        ),
      ),
    );
  }
}
