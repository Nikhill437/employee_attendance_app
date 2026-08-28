import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

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
    this.title = 'Scan Face',
    this.onMatch,
  });

  @override
  State<FaceScanScreen> createState() => _FaceScanScreenState();
}

class _FaceScanScreenState extends State<FaceScanScreen>
    with WidgetsBindingObserver {
  late final FaceScanViewModel _viewModel;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _viewModel = FaceScanViewModel(
      mode: widget.mode,
      onMatch: widget.onMatch,
    );
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
      backgroundColor: Colors.black,
      appBar: AppBar(title: Text(widget.title)),
      body: ListenableBuilder(
        listenable: _viewModel,
        builder: (context, _) => _viewModel.isCameraReady
            ? _buildScanner()
            : _buildCameraPlaceholder(),
      ),
    );
  }

  Widget _buildCameraPlaceholder() {
    return Center(
      child: _viewModel.status == ScanStatus.error
          ? Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                _viewModel.errorMessage ?? 'Camera unavailable',
                style: const TextStyle(color: Colors.white),
                textAlign: TextAlign.center,
              ),
            )
          : const CircularProgressIndicator(),
    );
  }

  Widget _buildScanner() {
    return Stack(
      alignment: Alignment.center,
      children: [
        Center(child: CameraPreview(_viewModel.controller!)),
        Center(
          child: Container(
            width: 260,
            height: 320,
            decoration: BoxDecoration(
              border: Border.all(color: _viewModel.statusColor, width: 3),
              borderRadius: BorderRadius.circular(160),
            ),
          ),
        ),
        Positioned(top: 20, left: 20, right: 20, child: _buildStatusBanner()),
      ],
    );
  }

  Widget _buildStatusBanner() {
    final matched = _viewModel.matchedUser;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Text(
            _viewModel.statusMessage,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _viewModel.statusColor,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (_viewModel.status == ScanStatus.success && matched != null) ...[
            const SizedBox(height: 4),
            Text(
              '${matched.name} • ${matched.employeeId}',
              style: const TextStyle(color: Colors.white, fontSize: 13),
            ),
          ],
        ],
      ),
    );
  }
}
