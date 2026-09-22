import 'dart:io';

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';

/// A labelled capture-and-preview box matching [AppFormField]'s look (same
/// label, red "*" for required). Before capture it's a tap target that
/// calls [onCapture]; once [image] is set it shows a thumbnail — tapping
/// the thumbnail opens a full-screen preview, and the "Retake" chip
/// re-triggers [onCapture].
class AppImageCaptureField extends StatelessWidget {
  final String label;
  final String hint;
  final bool isRequired;
  final File? image;
  final VoidCallback onCapture;

  const AppImageCaptureField({
    super.key,
    required this.label,
    required this.hint,
    required this.onCapture,
    this.isRequired = false,
    this.image,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text.rich(
          TextSpan(
            text: label,
            style: const TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: AppColors.slate,
            ),
            children: [
              if (isRequired)
                const TextSpan(
                  text: ' *',
                  style: TextStyle(
                    color: AppColors.danger,
                    fontWeight: FontWeight.w700,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 160,
          child: image == null ? _buildCaptureTarget() : _buildPreview(context),
        ),
      ],
    );
  }

  Widget _buildCaptureTarget() {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onCapture,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.cardBorder),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.camera_alt_outlined,
                size: 28,
                color: AppColors.muted,
              ),
              const SizedBox(height: 8),
              Text(
                hint,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, color: AppColors.muted),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPreview(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            onTap: () => _openFullPreview(context),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.file(image!, fit: BoxFit.cover),
            ),
          ),
        ),
        Positioned(
          right: 8,
          top: 8,
          child: _RetakeChip(onTap: onCapture),
        ),
      ],
    );
  }

  void _openFullPreview(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: const EdgeInsets.all(16),
        child: Stack(
          alignment: Alignment.topRight,
          children: [
            InteractiveViewer(child: Image.file(image!)),
            IconButton(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close, color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }
}

class _RetakeChip extends StatelessWidget {
  final VoidCallback onTap;

  const _RetakeChip({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(6),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.refresh, size: 14, color: Colors.white),
            SizedBox(width: 4),
            Text('Retake', style: TextStyle(fontSize: 12, color: Colors.white)),
          ],
        ),
      ),
    );
  }
}
