import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../common/widgets/common_widgets.dart';
import '../viewmodel/face_scan_viewmodel.dart';

export '../viewmodel/face_scan_viewmodel.dart' show FaceScanMode;

/// Continuous live face-scanning screen backed by the front camera.
///
/// In [FaceScanMode.enroll], capture is fully automatic and walks the user
/// through front/left/right/up/down poses, each captured once held; the
/// screen pops with one embedding per pose once all are collected.
///
/// In [FaceScanMode.attendance], once a single live (non-spoofed) face is
/// stably detected, [onMatch] is invoked with the embedding to verify and
/// mark attendance; the screen then pops with the authenticated user, or
/// shows "Face Recognition Failed" and keeps scanning.
///
/// All camera and detection logic lives in [FaceScanViewModel] — this widget
/// only renders its state.
class FaceScanScreen extends StatefulWidget {
  final FaceScanMode mode;
  final String title;
  final FaceMatchCallback? onMatch;

  const FaceScanScreen({
    super.key,
    required this.mode,
    this.title = 'Face Verification',
    this.onMatch,
  });

  @override
  State<FaceScanScreen> createState() => _FaceScanScreenState();
}

class _FaceScanScreenState extends State<FaceScanScreen>
    with WidgetsBindingObserver {
  static const double _frameDiameter = 250;

  late final FaceScanViewModel _viewModel;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _viewModel = FaceScanViewModel(mode: widget.mode, onMatch: widget.onMatch);
    _listenForCompletion();
    _viewModel.init();
  }

  /// Pops with whichever result this scan mode produces. Neither future ever
  /// completes with an error, and both are ignored once the screen is gone.
  void _listenForCompletion() {
    if (widget.mode == FaceScanMode.enroll) {
      _viewModel.enrollmentCompleted.then((embeddings) {
        if (mounted) Navigator.pop(context, embeddings);
      });
    } else {
      _viewModel.attendanceMatched.then((user) {
        if (mounted) Navigator.pop(context, user);
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _viewModel.handleAppLifecycleState(state);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _viewModel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: BackgroundScreen(
        child: SafeArea(
          child: ListenableBuilder(
            listenable: _viewModel,
            builder: (context, _) => SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Column(
                children: [
                  const SizedBox(height: 24),
                  const BrandHeader(),
                  const SizedBox(height: 40),
                  Text(
                    widget.title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _viewModel.statusMessage,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 15,
                      color: _viewModel.statusColor == Colors.white
                          ? Colors.white70
                          : _viewModel.statusColor,
                    ),
                  ),
                  const SizedBox(height: 36),
                  _buildScanFrame(),
                  const SizedBox(height: 28),
                  _buildProgress(),
                  const SizedBox(height: 16),
                  _buildCancelLink(),
                  const SizedBox(height: 24),
                  const AppVersionLabel(),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The dashed ring from the design, with the live preview circle-clipped
  /// inside it — or a placeholder silhouette until the camera is up.
  Widget _buildScanFrame() {
    final controller = _viewModel.controller;
    return SizedBox(
      width: _frameDiameter,
      height: _frameDiameter,
      child: CustomPaint(
        painter: DashedCirclePainter(color: _viewModel.statusColor),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: ClipOval(
            child: ColoredBox(
              color: Colors.white.withValues(alpha: 0.08),
              child: _viewModel.isCameraReady
                  ? _buildPreview(controller!)
                  : _buildPlaceholder(),
            ),
          ),
        ),
      ),
    );
  }

  /// The preview is letterboxed by default; cover the circle with it instead
  /// so no background shows through the clip.
  Widget _buildPreview(CameraController controller) {
    return FittedBox(
      fit: BoxFit.cover,
      clipBehavior: Clip.hardEdge,
      child: SizedBox(
        width: controller.value.previewSize?.height ?? _frameDiameter,
        height: controller.value.previewSize?.width ?? _frameDiameter,
        child: CameraPreview(controller),
      ),
    );
  }

  Widget _buildPlaceholder() {
    return Center(
      child: _viewModel.status == ScanStatus.error
          ? Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                _viewModel.errorMessage ?? 'Camera unavailable',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white),
              ),
            )
          : Icon(
              Icons.person_outline,
              size: 110,
              color: Colors.white.withValues(alpha: 0.45),
            ),
    );
  }

  Widget _buildProgress() {
    final percent = _viewModel.scanPercent;
    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: _viewModel.scanProgress,
            minHeight: 7,
            backgroundColor: Colors.white.withValues(alpha: 0.25),
            valueColor: const AlwaysStoppedAnimation(AppColors.lime),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          _viewModel.status == ScanStatus.singleFace
              ? 'Scanning... $percent%'
              : _viewModel.statusMessage,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: AppColors.lime,
          ),
        ),
      ],
    );
  }

  Widget _buildCancelLink() {
    return AppLinkText(
      label: 'Cancel Scan',
      onTap: () => Navigator.maybePop(context),
    );
  }
}
