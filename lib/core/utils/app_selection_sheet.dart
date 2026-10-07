import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Shows [items] in a bottom sheet and resolves to the one the user taps, or
/// null if the sheet is dismissed. [selected] gets a check mark. Every
/// dropdown in the app opens through this, so they all look and behave alike.
Future<T?> showAppSelectionSheet<T>({
  required BuildContext context,
  required String title,
  required List<T> items,
  required String Function(T item) labelBuilder,
  T? selected,
}) {
  return showModalBottomSheet<T>(
    context: context,
    backgroundColor: Colors.white,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: (sheetContext) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.7,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 8),
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.cardBorder,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink,
                ),
              ),
            ),
            const Divider(height: 1, color: AppColors.cardBorder),
            if (items.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No options available',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.muted),
                ),
              )
            else
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: const EdgeInsets.only(bottom: 8),
                  itemCount: items.length,
                  separatorBuilder: (_, _) =>
                      const Divider(height: 1, color: AppColors.cardBorder),
                  itemBuilder: (context, index) {
                    final item = items[index];
                    final isSelected = selected != null && item == selected;
                    return ListTile(
                      title: Text(
                        labelBuilder(item),
                        style: TextStyle(
                          fontSize: 15,
                          // fontWeight: isSelected
                          //     ? FontWeight.w700
                          //     : FontWeight.w500,
                          color: isSelected
                              ? AppColors.deepGreen
                              : AppColors.ink,
                        ),
                      ),
                      trailing: isSelected
                          ? const Icon(Icons.check, color: AppColors.deepGreen)
                          : null,
                      onTap: () => Navigator.pop(sheetContext, item),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    ),
  );
}
