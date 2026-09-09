import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../../../core/routes/section_navigation.dart';
import '../../../core/theme/app_colors.dart';
import '../../common/widgets/common_widgets.dart';
import '../viewmodel/face_scan_viewmodel.dart';

/// Step 2 of enrollment: captures the worker's multi-pose face profile.
///
/// Pops with one embedding per pose — the same result [FaceScanScreen]
/// returns in [FaceScanMode.enroll], so it is a drop-in for that step.
class FaceCaptureScreen extends StatefulWidget {
  const FaceCaptureScreen({super.key});

  @override
  State<FaceCaptureScreen> createState() => _FaceCaptureScreenState();
}

class _FaceCaptureScreenState extends State<FaceCaptureScreen>
    with WidgetsBindingObserver {
  static const List<String> _steps = ['Details', 'Face Capture', 'Complete'];
  static const List<String> _quickTips = [
    'Remove glasses or hats',
    'Look directly at the camera',
    'Keep still during capture',
  ];
  static const double _frameSize = 250;

  /// Null until the supervisor taps the capture button, so the camera only
  /// starts when they are ready.
  FaceScanViewModel? _viewModel;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _viewModel?.handleAppLifecycleState(state);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _viewModel?.dispose();
    super.dispose();
  }

  /// Starts a capture, discarding any previous attempt — a view model owns a
  /// single run, so retaking means a fresh one.
  void _startCapture() {
    _viewModel?.dispose();

    final viewModel = FaceScanViewModel(mode: FaceScanMode.enroll);
    viewModel.enrollmentCompleted.then((embeddings) {
      if (mounted) Navigator.pop(context, embeddings);
    });

    setState(() => _viewModel = viewModel);
    viewModel.init();
  }

  @override
  Widget build(BuildContext context) {
    final viewModel = _viewModel;
    return Scaffold(
      backgroundColor: AppColors.pageGrey,
      body: Column(
        children: [
          const AppScreenHeader(
            title: 'Face Capture',
            subtitle: 'Step 2 of 3',
            showBack: true,
          ),
          Expanded(
            child: viewModel == null
                ? _buildContent()
                : ListenableBuilder(
                    listenable: viewModel,
                    builder: (context, _) => _buildContent(),
                  ),
          ),
        ],
      ),
      bottomNavigationBar: AppBottomNavBar(
        current: AppSection.workers,
        onSectionSelected: (target) =>
            switchToSection(context, AppSection.workers, target),
      ),
    );
  }

  Widget _buildContent() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        const AppCard(
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          child: AppStepIndicator(steps: _steps, currentStep: 1),
        ),
        const SizedBox(height: 16),
        _buildPreviewCard(),
        const SizedBox(height: 16),
        _buildGuidancePanel(),
        const SizedBox(height: 18),
        _buildQuickTips(),
        const SizedBox(height: 24),
        _buildCaptureButton(),
        const SizedBox(height: 10),
        Center(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _startCapture,
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              child: Text(
                'Retake Photo',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppColors.ink,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// The dashed ring, holding the live preview once the camera is running and
  /// a placeholder silhouette before that.
  Widget _buildPreviewCard() {
    final controller = _viewModel?.controller;
    final isReady = _viewModel?.isCameraReady ?? false;

    return AppCard(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Center(
        child: SizedBox(
          width: _frameSize,
          height: _frameSize,
          child: CustomPaint(
            painter: const DashedCirclePainter(
              color: AppColors.deepGreen,
              strokeWidth: 2.5,
              dashCount: 60,
              dashFraction: 0.5,
            ),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: ClipOval(
                child: isReady
                    ? _buildPreview(controller!)
                    : const Icon(
                        Icons.person_outline,
                        size: 150,
                        color: Color(0xFFE0E4E0),
                      ),
              ),
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
        width: controller.value.previewSize?.height ?? _frameSize,
        height: controller.value.previewSize?.width ?? _frameSize,
        child: CameraPreview(controller),
      ),
    );
  }

  /// Static guidance before capture; once running it shows the view model's
  /// live pose instruction instead.
  Widget _buildGuidancePanel() {
    final viewModel = _viewModel;
    final headline = viewModel == null
        ? "Position the worker's face within the frame."
        : viewModel.statusMessage;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFE7F3E9),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            headline,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Ensure good lighting and a neutral expression for fast, '
            'accurate face verification.',
            style: TextStyle(fontSize: 13.5, color: AppColors.muted),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickTips() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionLabel('QUICK TIPS'),
        const SizedBox(height: 10),
        for (final tip in _quickTips)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                const Icon(Icons.check, size: 17, color: AppColors.success),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    tip,
                    style: const TextStyle(
                      fontSize: 14.5,
                      color: AppColors.ink,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildCaptureButton() {
    return Center(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _startCapture,
        child: Container(
          width: 66,
          height: 66,
          decoration: const BoxDecoration(
            color: AppColors.lime,
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.photo_camera_outlined,
            size: 28,
            color: AppColors.onLime,
          ),
        ),
      ),
    );
  }
}
