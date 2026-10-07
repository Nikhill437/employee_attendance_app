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

  /// Shown when there's no local [image] — a full URL for an attachment that
  /// lives on the server. [imageHeaders] goes with it (e.g. the auth token).
  final String? imageUrl;
  final Map<String, String>? imageHeaders;
  final VoidCallback onCapture;

  /// False blocks capturing/retaking — still shows the existing image (if
  /// any) and its full-screen preview, just not editable.
  final bool enabled;

  const AppImageCaptureField({
    super.key,
    required this.label,
    required this.hint,
    required this.onCapture,
    this.isRequired = false,
    this.image,
    this.imageUrl,
    this.imageHeaders,
    this.enabled = true,
  });

  bool get _hasImage => image != null || imageUrl != null;

  ImageProvider get _provider => image != null
      ? FileImage(image!)
      : NetworkImage(imageUrl!, headers: imageHeaders);

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
          child: _hasImage ? _buildPreview(context) : _buildCaptureTarget(),
        ),
      ],
    );
  }

  Widget _buildCaptureTarget() {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: enabled ? onCapture : null,
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
              child: Image(
                image: _provider,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) =>
                    _buildUnavailable(),
              ),
            ),
          ),
        ),
        if (enabled)
          Positioned(right: 8, top: 8, child: _RetakeChip(onTap: onCapture)),
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
            InteractiveViewer(child: Image(image: _provider)),
            IconButton(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close, color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }

  /// Shown when a stored attachment can't be loaded, instead of a blank box.
  Widget _buildUnavailable() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.broken_image_outlined, size: 28, color: AppColors.muted),
            SizedBox(height: 8),
            Text(
              'Attachment unavailable',
              style: TextStyle(fontSize: 13, color: AppColors.muted),
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
        height: 40,
        width: 100,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(6),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.refresh, size: 16, color: Colors.white),
            SizedBox(width: 4),
            Text('Retake', style: TextStyle(fontSize: 14, color: Colors.white)),
          ],
        ),
      ),
    );
  }
}
