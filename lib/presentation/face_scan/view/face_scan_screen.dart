import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

import 'employee_model.dart';
import 'face_recognition_service.dart';
import 'live_face_detector.dart';

enum FaceScanMode { enroll, attendance }

/// One head pose captured during enrollment, so the stored profile has
/// embeddings from several angles instead of a single front-on shot.
enum _EnrollPose { front, left, right, up, down }

const List<_EnrollPose> _enrollSequence = [
  _EnrollPose.front,
  _EnrollPose.left,
  _EnrollPose.right,
  _EnrollPose.up,
  _EnrollPose.down,
];

const Map<_EnrollPose, String> _poseInstruction = {
  _EnrollPose.front: 'Look straight at the camera',
  _EnrollPose.left: 'Slowly turn your head to the left',
  _EnrollPose.right: 'Slowly turn your head to the right',
  _EnrollPose.up: 'Slowly tilt your head up',
  _EnrollPose.down: 'Slowly tilt your head down',
};

enum _ScanStatus {
  initializing,
  noFace,
  multipleFaces,
  singleFace,
  capturing,
  poseCaptured,
  success,
  notRecognized,
  livenessFailed,
  error,
}

/// Continuous live face-scanning screen backed by the front camera.
///
/// In [FaceScanMode.enroll], capture is fully automatic and walks through
/// [_enrollSequence]: the user is prompted through front/left/right/up/down
/// poses, each captured once held, and the screen pops with one embedding
/// per pose via [Navigator.pop] once all are collected.
///
/// In [FaceScanMode.attendance], capture is automatic: once a single live
/// (non-spoofed) face is stably detected, [onMatch] is invoked with the
/// embedding to look up (and mark) attendance; the screen then pops with the
/// matched [Employee], or shows "Face Recognition Failed" and keeps
/// scanning.
class FaceScanScreen extends StatefulWidget {
  final FaceScanMode mode;
  final String title;
  final Future<Employee?> Function(List<double> embedding)? onMatch;

  const FaceScanScreen({
    super.key,
    required this.mode,
    this.title = 'Scan Face',
    this.onMatch,
  }) : assert(
         mode != FaceScanMode.attendance || onMatch != null,
         'onMatch is required for FaceScanMode.attendance',
       );

  @override
  State<FaceScanScreen> createState() => _FaceScanScreenState();
}

class _FaceScanScreenState extends State<FaceScanScreen>
    with WidgetsBindingObserver {
  static const _stableFramesRequired = 6;

  // headEulerAngleY (left/right yaw) is only guaranteed in ML Kit's
  // "accurate" detector mode per its docs; the live preview here runs in
  // "fast" mode for performance, so it isn't reliable enough to gate on.
  // Left/right turns instead require a longer deliberate hold so the user
  // has time to actually turn before the shot is taken. headEulerAngleX
  // (pitch) carries no such caveat, so up/down poses are angle-verified.
  static const _turnHoldFramesRequired = 14;
  static const double _pitchThreshold = 10.0;

  CameraController? _controller;
  CameraDescription? _camera;
  final LiveFaceDetector _liveDetector = LiveFaceDetector();
  final FaceRecognitionService _faceService = FaceRecognitionService();

  _ScanStatus _status = _ScanStatus.initializing;
  String? _errorMessage;
  Employee? _matchedEmployee;
  int _stableSingleFaceFrames = 0;
  bool _busyDetecting = false;
  bool _busyCapturing = false;
  bool _streamActive = false;

  int _enrollStep = 0;
  final List<List<double>> _enrollEmbeddings = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  Future<void> _init() async {
    try {
      final cameras = await availableCameras();
      _camera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );
      _controller = CameraController(
        _camera!,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: LiveFaceDetector.preferredFormat,
      );
      await _controller!.initialize();
      if (!mounted) return;
      setState(() => _status = _ScanStatus.noFace);
      await _startStream();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _status = _ScanStatus.error;
        _errorMessage = 'Camera error: $e';
      });
    }
  }

  Future<void> _startStream() async {
    if (_controller == null || _streamActive) return;
    _streamActive = true;
    await _controller!.startImageStream(_onFrame);
  }

  Future<void> _stopStream() async {
    if (_controller == null || !_streamActive) return;
    _streamActive = false;
    await _controller!.stopImageStream();
  }

  void _onFrame(CameraImage image) {
    if (_busyDetecting || _busyCapturing || !mounted) return;
    _busyDetecting = true;
    _processFrame(image).whenComplete(() => _busyDetecting = false);
  }

  _EnrollPose get _currentPose => _enrollSequence[_enrollStep];

  int get _holdFramesRequired {
    if (widget.mode != FaceScanMode.enroll) return _stableFramesRequired;
    switch (_currentPose) {
      case _EnrollPose.left:
      case _EnrollPose.right:
        return _turnHoldFramesRequired;
      case _EnrollPose.front:
      case _EnrollPose.up:
      case _EnrollPose.down:
        return _stableFramesRequired;
    }
  }

  /// For poses with a machine-checkable angle (currently only pitch, see
  /// the class-level note on why yaw isn't used here), require the angle
  /// threshold in addition to a stable hold. Poses without a checkable
  /// angle just need the hold.
  bool _poseAngleSatisfied(Face face) {
    if (widget.mode != FaceScanMode.enroll) return true;
    final pitch = face.headEulerAngleX;
    switch (_currentPose) {
      case _EnrollPose.up:
        return pitch != null && pitch >= _pitchThreshold;
      case _EnrollPose.down:
        return pitch != null && pitch <= -_pitchThreshold;
      case _EnrollPose.front:
      case _EnrollPose.left:
      case _EnrollPose.right:
        return true;
    }
  }

  Future<void> _processFrame(CameraImage image) async {
    final inputImage = _liveDetector.inputImageFromCameraImage(
      image: image,
      camera: _camera!,
      deviceOrientation: _controller!.value.deviceOrientation,
    );
    if (inputImage == null) return;

    final faces = await _liveDetector.detect(inputImage);
    if (!mounted || _busyCapturing) return;

    if (faces.isEmpty) {
      _stableSingleFaceFrames = 0;
      if (_status != _ScanStatus.noFace) {
        setState(() => _status = _ScanStatus.noFace);
      }
      return;
    }
    if (faces.length > 1) {
      _stableSingleFaceFrames = 0;
      if (_status != _ScanStatus.multipleFaces) {
        setState(() => _status = _ScanStatus.multipleFaces);
      }
      return;
    }

    if (_poseAngleSatisfied(faces.first)) {
      _stableSingleFaceFrames++;
    } else {
      _stableSingleFaceFrames = 0;
    }
    setState(() => _status = _ScanStatus.singleFace);

    if (_stableSingleFaceFrames >= _holdFramesRequired) {
      _stableSingleFaceFrames = 0;
      unawaited(_captureAndProcess());
    }
  }

  Future<void> _captureAndProcess() async {
    if (_busyCapturing || _controller == null) return;
    setState(() {
      _busyCapturing = true;
      _status = _ScanStatus.capturing;
    });

    File? photoFile;
    try {
      await _stopStream();
      final photo = await _controller!.takePicture();
      photoFile = File(photo.path);

      final analysis = await _faceService.getFaceAnalysis(photoFile);

      if (analysis.faceCount != 1 || analysis.embedding == null) {
        await _resumeAfterFailure(
          status: _ScanStatus.error,
          message: 'Could not get a clear face. Please try again.',
        );
        return;
      }

      if (!_faceService.isLive(analysis.livenessConfidence)) {
        await _resumeAfterFailure(status: _ScanStatus.livenessFailed);
        return;
      }

      if (widget.mode == FaceScanMode.enroll) {
        _enrollEmbeddings.add(analysis.embedding!);
        _enrollStep++;
        if (_enrollStep >= _enrollSequence.length) {
          if (!mounted) return;
          Navigator.pop(context, _enrollEmbeddings);
          return;
        }
        await _resumeAfterPoseCapture();
        return;
      }

      final matched = await widget.onMatch!(analysis.embedding!);
      if (!mounted) return;

      if (matched != null) {
        setState(() {
          _status = _ScanStatus.success;
          _matchedEmployee = matched;
          _busyCapturing = false;
        });
        await Future.delayed(const Duration(milliseconds: 1600));
        if (!mounted) return;
        Navigator.pop(context, matched);
      } else {
        await _resumeAfterFailure(status: _ScanStatus.notRecognized);
      }
    } catch (e) {
      await _resumeAfterFailure(status: _ScanStatus.error, message: 'Error: $e');
    } finally {
      photoFile?.delete().ignore();
    }
  }

  Future<void> _resumeAfterPoseCapture() async {
    if (!mounted) return;
    setState(() {
      _status = _ScanStatus.poseCaptured;
      _busyCapturing = false;
    });
    await Future.delayed(const Duration(milliseconds: 700));
    if (!mounted) return;
    setState(() => _status = _ScanStatus.noFace);
    await _startStream();
  }

  Future<void> _resumeAfterFailure({
    required _ScanStatus status,
    String? message,
  }) async {
    if (!mounted) return;
    setState(() {
      _status = status;
      _errorMessage = message;
      _busyCapturing = false;
    });
    await Future.delayed(const Duration(milliseconds: 1600));
    if (!mounted) return;
    setState(() => _status = _ScanStatus.noFace);
    await _startStream();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      _stopStream();
    } else if (state == AppLifecycleState.resumed) {
      _startStream();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopStream();
    _controller?.dispose();
    _liveDetector.dispose();
    super.dispose();
  }

  String get _enrollStepLabel =>
      'Step ${_enrollStep + 1}/${_enrollSequence.length}: '
      '${_poseInstruction[_currentPose]}';

  String get _statusMessage {
    switch (_status) {
      case _ScanStatus.initializing:
        return 'Starting camera...';
      case _ScanStatus.noFace:
        return widget.mode == FaceScanMode.enroll
            ? _enrollStepLabel
            : 'Please position your face inside the frame';
      case _ScanStatus.multipleFaces:
        return 'Only one face should be visible';
      case _ScanStatus.singleFace:
        return widget.mode == FaceScanMode.enroll
            ? _enrollStepLabel
            : 'Face detected — hold still...';
      case _ScanStatus.capturing:
        return 'Verifying...';
      case _ScanStatus.poseCaptured:
        return 'Captured ✓';
      case _ScanStatus.success:
        return widget.mode == FaceScanMode.enroll
            ? 'Face profile captured'
            : 'Attendance Marked Successfully';
      case _ScanStatus.notRecognized:
        return 'Face Recognition Failed';
      case _ScanStatus.livenessFailed:
        return 'Liveness check failed — use a live camera, not a photo';
      case _ScanStatus.error:
        return _errorMessage ?? 'Something went wrong';
    }
  }

  Color get _statusColor {
    switch (_status) {
      case _ScanStatus.success:
      case _ScanStatus.poseCaptured:
        return Colors.greenAccent;
      case _ScanStatus.notRecognized:
      case _ScanStatus.livenessFailed:
      case _ScanStatus.error:
      case _ScanStatus.multipleFaces:
        return Colors.redAccent;
      case _ScanStatus.singleFace:
        return Colors.lightGreenAccent;
      default:
        return Colors.white;
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(title: Text(widget.title)),
      body: (controller == null || !controller.value.isInitialized)
          ? Center(
              child: _status == _ScanStatus.error
                  ? Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        _errorMessage ?? 'Camera unavailable',
                        style: const TextStyle(color: Colors.white),
                        textAlign: TextAlign.center,
                      ),
                    )
                  : const CircularProgressIndicator(),
            )
          : Stack(
              alignment: Alignment.center,
              children: [
                Center(child: CameraPreview(controller)),
                Center(
                  child: Container(
                    width: 260,
                    height: 320,
                    decoration: BoxDecoration(
                      border: Border.all(color: _statusColor, width: 3),
                      borderRadius: BorderRadius.circular(160),
                    ),
                  ),
                ),
                Positioned(
                  top: 20,
                  left: 20,
                  right: 20,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      vertical: 10,
                      horizontal: 16,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      children: [
                        Text(
                          _statusMessage,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: _statusColor,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (_status == _ScanStatus.success &&
                            _matchedEmployee != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            '${_matchedEmployee!.name} • ${_matchedEmployee!.employeeId}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
