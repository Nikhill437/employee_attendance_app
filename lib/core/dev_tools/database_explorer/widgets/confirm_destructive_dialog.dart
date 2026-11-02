import 'package:flutter/material.dart';

/// Shows a confirmation dialog before running a destructive SQL statement
/// (any write or schema-changing query). Returns `true` if the user
/// confirmed, `false`/`null` otherwise.
Future<bool> confirmDestructiveQuery(BuildContext context, String sql) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Confirm database change'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'This statement will modify the database and cannot be '
            'undone automatically:',
          ),
          const SizedBox(height: 12),
          Container(
            width: double.maxFinite,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(sql, style: const TextStyle(fontFamily: 'monospace')),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Run anyway'),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}
