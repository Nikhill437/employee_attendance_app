import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;

import '../../../core/base/base_view_model.dart';
import '../../../core/services/face_recognition_service.dart';
import '../../../core/services/live_face_detector.dart';
import '../../../data/models/auth/auth_user_model.dart';

enum FaceScanMode { enroll, attendance }

/// One head pose captured during enrollment, so the stored profile has
/// embeddings from several angles instead of a single front-on shot.
enum EnrollPose { front, left, right, up, down }

const List<EnrollPose> kEnrollSequence = [
  EnrollPose.front,
  EnrollPose.left,
  EnrollPose.right,
  EnrollPose.up,
  EnrollPose.down,
];

const Map<EnrollPose, String> kPoseInstruction = {
  EnrollPose.front: 'Look straight at the camera',
  EnrollPose.left: 'Slowly turn your head to the left',
  EnrollPose.right: 'Slowly turn your head to the right',
  EnrollPose.up: 'Slowly tilt your head up',
  EnrollPose.down: 'Slowly tilt your head down',
};

enum ScanStatus {
  initializing,
  noFace,
  multipleFaces,
  faceObstructed,
  eyesClosed,
  singleFace,
  capturing,
  poseCaptured,
  success,
  notRecognized,
  livenessFailed,
  error,

  /// The captured photo failed the post-capture quality check — see
  /// FaceScanViewModel._validateCapturedPhoto. Distinct statuses (rather
  /// than reusing e.g. [faceObstructed]) so each has its own precise
  /// message, even though several of them can also be reached live.
  faceOutOfFrame,
  faceTooSmall,
  poseInvalid,
}

/// Verifies a captured embedding for [FaceScanMode.attendance]. Returns the
/// authenticated user on a match, or null to keep scanning.
typedef FaceMatchCallback =
    Future<AuthUser?> Function(List<double> embedding);

/// Owns the camera, the live-detection loop, and the capture/verify state
/// machine behind the face scan screen. The view only renders what this
/// exposes and reacts to [enrollmentCompleted] / [attendanceMatched].
class FaceScanViewModel extends BaseViewModel {
  static const _stableFramesRequired = 6;

  // headEulerAngleY (left/right yaw) is only guaranteed in ML Kit's
  // "accurate" detector mode per its docs; the live preview here runs in
  // "fast" mode for performance, so it isn't reliable enough to gate on.
  // Left/right turns instead require a longer deliberate hold so the user
  // has time to actually turn before the shot is taken. headEulerAngleX
  // (pitch) carries no such caveat, so up/down poses are angle-verified.
  static const _turnHoldFramesRequired = 14;
  static const double _pitchThreshold = 10.0;

  // ML Kit's classification confidence that each eye is open; requires
  // enableClassification on the detector (see LiveFaceDetector). Both eyes
  // must clear this for a frame to count towards the capture hold, so a
  // blink can't sneak a closed-eyes shot into enrollment or attendance.
  static const double _eyeOpenThreshold = 0.5;

  final FaceScanMode mode;
  final FaceMatchCallback? onMatch;
  final LiveFaceDetector _liveDetector;
  final FaceRecognitionService _faceService;

  FaceScanViewModel({
    required this.mode,
    this.onMatch,
    LiveFaceDetector? liveDetector,
    FaceRecognitionService? faceService,
  }) : _liveDetector = liveDetector ?? LiveFaceDetector(),
       _faceService = faceService ?? FaceRecognitionService(),
       assert(
         mode != FaceScanMode.attendance || onMatch != null,
         'onMatch is required for FaceScanMode.attendance',
       );

  CameraController? _controller;
  CameraDescription? _camera;

  ScanStatus _status = ScanStatus.initializing;
  String? _errorMessage;
  AuthUser? _matchedUser;
  int _stableSingleFaceFrames = 0;
  bool _busyDetecting = false;
  bool _busyCapturing = false;
  bool _streamActive = false;

  int _enrollStep = 0;
  final List<List<double>> _enrollEmbeddings = [];

  /// Completed multi-pose enrollment, set once all poses are captured.
  final Completer<List<List<double>>> _enrollmentCompleter = Completer();

  /// Resolves with the authenticated user once attendance verification
  /// succeeds.
  final Completer<AuthUser> _attendanceCompleter = Completer();

  CameraController? get controller => _controller;
  bool get isCameraReady => _controller?.value.isInitialized ?? false;
  ScanStatus get status => _status;
  String? get errorMessage => _errorMessage;
  AuthUser? get matchedUser => _matchedUser;

  /// Fires with one embedding per pose when enrollment finishes.
  Future<List<List<double>>> get enrollmentCompleted =>
      _enrollmentCompleter.future;

  /// Fires with the authenticated user when attendance verification succeeds.
  Future<AuthUser> get attendanceMatched => _attendanceCompleter.future;

  EnrollPose get currentPose => kEnrollSequence[_enrollStep];

  /// How far the current capture has got, 0..1 — the stable-hold counter as a
  /// fraction of the frames this pose needs. Drives the progress bar.
  double get scanProgress {
    switch (_status) {
      case ScanStatus.capturing:
      case ScanStatus.poseCaptured:
      case ScanStatus.success:
        return 1;
      case ScanStatus.initializing:
      case ScanStatus.noFace:
      case ScanStatus.multipleFaces:
      case ScanStatus.faceObstructed:
      case ScanStatus.eyesClosed:
      case ScanStatus.notRecognized:
      case ScanStatus.livenessFailed:
      case ScanStatus.error:
      case ScanStatus.faceOutOfFrame:
      case ScanStatus.faceTooSmall:
      case ScanStatus.poseInvalid:
        return 0;
      case ScanStatus.singleFace:
        return (_stableSingleFaceFrames / _holdFramesRequired).clamp(0.0, 1.0);
    }
  }

  int get scanPercent => (scanProgress * 100).round();

  String get enrollStepLabel =>
      'Step ${_enrollStep + 1}/${kEnrollSequence.length}: '
      '${kPoseInstruction[currentPose]}';

  Future<void> init() async {
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
      if (isDisposed) return;
      _setStatus(ScanStatus.noFace);
      await startStream();
    } catch (e) {
      _fail('Camera error: $e');
    }
  }

  Future<void> startStream() async {
    if (_controller == null || _streamActive || isDisposed) return;
    _streamActive = true;
    await _controller!.startImageStream(_onFrame);
  }

  Future<void> stopStream() async {
    if (_controller == null || !_streamActive) return;
    _streamActive = false;
    await _controller!.stopImageStream();
  }

  void handleAppLifecycleState(AppLifecycleState state) {
    if (!isCameraReady) return;
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      stopStream();
    } else if (state == AppLifecycleState.resumed) {
      startStream();
    }
  }

  void _onFrame(CameraImage image) {
    if (_busyDetecting || _busyCapturing || isDisposed) return;
    _busyDetecting = true;
    _processFrame(image).whenComplete(() => _busyDetecting = false);
  }

  int get _holdFramesRequired {
    if (mode != FaceScanMode.enroll) return _stableFramesRequired;
    switch (currentPose) {
      case EnrollPose.left:
      case EnrollPose.right:
        return _turnHoldFramesRequired;
      case EnrollPose.front:
      case EnrollPose.up:
      case EnrollPose.down:
        return _stableFramesRequired;
    }
  }

  /// For poses with a machine-checkable angle (currently only pitch, see
  /// the class-level note on why yaw isn't used here), require the angle
  /// threshold in addition to a stable hold. Poses without a checkable
  /// angle just need the hold.
  bool _poseAngleSatisfied(Face face) {
    if (mode != FaceScanMode.enroll) return true;
    final pitch = face.headEulerAngleX;
    switch (currentPose) {
      case EnrollPose.up:
        return pitch != null && pitch >= _pitchThreshold;
      case EnrollPose.down:
        return pitch != null && pitch <= -_pitchThreshold;
      case EnrollPose.front:
      case EnrollPose.left:
      case EnrollPose.right:
        return true;
    }
  }

  /// Core landmarks that must all resolve for the face to count as clearly
  /// visible. A hand, mask, cloth, or other covering typically makes ML Kit
  /// fail to resolve one or more of these, which is the signal used to block
  /// capture — required for every pose in both enroll and attendance modes.
  static const _requiredLandmarks = [
    FaceLandmarkType.noseBase,
    FaceLandmarkType.leftEye,
    FaceLandmarkType.rightEye,
    FaceLandmarkType.leftMouth,
    FaceLandmarkType.rightMouth,
  ];

  bool _faceFullyVisible(Face face) {
    return _requiredLandmarks.every(
      (type) => face.landmarks[type] != null,
    );
  }

  /// Both eyes must be open — required for every pose in both enroll and
  /// attendance modes. Missing probabilities (classification unavailable)
  /// fail closed, same as the liveness check.
  bool _eyesOpenSatisfied(Face face) {
    final left = face.leftEyeOpenProbability;
    final right = face.rightEyeOpenProbability;
    if (left == null || right == null) return false;
    return left >= _eyeOpenThreshold && right >= _eyeOpenThreshold;
  }

  // --- Post-capture quality validation ---
  //
  // The live loop above only decides *when* to trigger a capture; it never
  // re-checks the frame that's actually captured. Between the last "good"
  // preview frame and the shutter, quality can change (a blink, a hand
  // moving into frame, a step back), and InspireFace's own analysis (see
  // FaceRecognitionService.getFaceAnalysis) only reports face count,
  // embedding, and liveness — nothing about eyes, occlusion, framing, or
  // size. So the captured photo is re-validated here, with the same
  // landmark/eye checks used live plus framing/size/orientation checks the
  // live loop can't reliably do (see below) — this is the one point both
  // FaceCaptureScreen (enroll) and FaceScanScreen (attendance) funnel
  // through via [_captureAndProcess], so fixing it here covers both.

  /// Unlike [_liveDetector] ("fast" mode, tuned for per-frame preview
  /// performance), this one runs "accurate" mode — it only ever processes
  /// one still image per capture attempt, so the extra cost doesn't affect
  /// the live preview's frame rate, and accurate mode is what makes
  /// headEulerAngleY (yaw) reliable enough to gate on (see
  /// _orientationAcceptable and the class-level note on why the live loop
  /// can't use yaw).
  final FaceDetector _captureDetector = FaceDetector(
    options: FaceDetectorOptions(
      performanceMode: FaceDetectorMode.accurate,
      enableClassification: true,
      enableLandmarks: true,
    ),
  );

  /// Required margin between the face's bounding box and the photo's
  /// edges — a face box touching or crossing an edge means part of it
  /// (forehead, chin, an ear) is cut off, even when the core landmarks
  /// [_faceFullyVisible] checks still resolve.
  static const double _frameMarginRatio = 0.03;

  /// The face's bounding box must be at least this fraction of the photo's
  /// width — below it, the face is too small/far for a reliable embedding.
  static const double _minFaceWidthRatio = 0.28;

  static const double _maxYawDegrees = 20.0;
  static const double _maxRollDegrees = 18.0;

  bool _faceWithinFrame(Face face, int imageWidth, int imageHeight) {
    final marginX = imageWidth * _frameMarginRatio;
    final marginY = imageHeight * _frameMarginRatio;
    final box = face.boundingBox;
    return box.left >= marginX &&
        box.top >= marginY &&
        box.right <= imageWidth - marginX &&
        box.bottom <= imageHeight - marginY;
  }

  bool _faceLargeEnough(Face face, int imageWidth) {
    return face.boundingBox.width >= imageWidth * _minFaceWidthRatio;
  }

  /// Enrollment's own left/right poses are intentionally off-axis (that's
  /// the point of capturing them) and are already gated by a deliberate
  /// hold time instead of a yaw threshold (see the class-level note above
  /// _turnHoldFramesRequired) — so this general front-facing check skips
  /// them and only applies to front/up/down poses and every attendance
  /// capture, none of which should be significantly turned or tilted.
  bool _orientationAcceptable(Face face) {
    if (mode == FaceScanMode.enroll &&
        (currentPose == EnrollPose.left || currentPose == EnrollPose.right)) {
      return true;
    }
    final yaw = face.headEulerAngleY;
    final roll = face.headEulerAngleZ;
    if (yaw == null || roll == null) return false;
    return yaw.abs() <= _maxYawDegrees && roll.abs() <= _maxRollDegrees;
  }

  /// Runs every quality check against the just-captured photo, returning
  /// the [ScanStatus] to resume scanning with if it fails any of them, or
  /// null if it passes all of them and recognition should proceed.
  Future<ScanStatus?> _validateCapturedPhoto(File photoFile) async {
    img.Image? decoded;
    try {
      decoded = img.decodeImage(await photoFile.readAsBytes());
    } catch (_) {
      decoded = null;
    }
    if (decoded == null) return ScanStatus.error;
    // Only used below for the frame-margin/size ratio checks, which need
    // to know the upright width/height — the detector itself reads
    // [photoFile] directly (see below), not these decoded pixels.
    decoded = img.bakeOrientation(decoded);

    List<Face> faces;
    try {
      // InputImage.fromFilePath, not fromBytes: ML Kit reads the JPEG (and
      // its EXIF orientation) itself, on whichever pixel format its native
      // Android/iOS implementation actually wants. Building an
      // InputImage.fromBytes here instead — as this used to — meant
      // choosing that format ourselves, and hardcoding bgra8888 broke
      // every capture on Android (PlatformException), since Android's ML
      // Kit only accepts nv21/yv12 for byte-buffer images (see
      // LiveFaceDetector.preferredFormat, which already draws this exact
      // platform line for the live preview).
      faces = await _captureDetector.processImage(
        InputImage.fromFilePath(photoFile.path),
      );
    } catch (_) {
      return ScanStatus.error;
    }
    if (isDisposed) return ScanStatus.error;

    if (faces.isEmpty) return ScanStatus.noFace;
    if (faces.length > 1) return ScanStatus.multipleFaces;

    final face = faces.first;
    if (!_faceFullyVisible(face)) return ScanStatus.faceObstructed;
    if (!_eyesOpenSatisfied(face)) return ScanStatus.eyesClosed;
    if (!_faceWithinFrame(face, decoded.width, decoded.height)) {
      return ScanStatus.faceOutOfFrame;
    }
    if (!_faceLargeEnough(face, decoded.width)) return ScanStatus.faceTooSmall;
    if (!_orientationAcceptable(face)) return ScanStatus.poseInvalid;

    return null;
  }

  Future<void> _processFrame(CameraImage image) async {
    final inputImage = _liveDetector.inputImageFromCameraImage(
      image: image,
      camera: _camera!,
      deviceOrientation: _controller!.value.deviceOrientation,
    );
    if (inputImage == null) return;

    final faces = await _liveDetector.detect(inputImage);
    if (isDisposed || _busyCapturing) return;

    if (faces.isEmpty) {
      _stableSingleFaceFrames = 0;
      _setStatus(ScanStatus.noFace);
      return;
    }
    if (faces.length > 1) {
      _stableSingleFaceFrames = 0;
      _setStatus(ScanStatus.multipleFaces);
      return;
    }

    final face = faces.first;
    if (!_faceFullyVisible(face)) {
      _stableSingleFaceFrames = 0;
      _setStatus(ScanStatus.faceObstructed, force: true);
      return;
    }

    if (!_eyesOpenSatisfied(face)) {
      _stableSingleFaceFrames = 0;
      _setStatus(ScanStatus.eyesClosed, force: true);
      return;
    }

    if (_poseAngleSatisfied(face)) {
      _stableSingleFaceFrames++;
    } else {
      _stableSingleFaceFrames = 0;
    }
    // Force the repaint: the status often stays `singleFace` across frames
    // while the hold counter — and so the progress bar — keeps moving.
    _setStatus(ScanStatus.singleFace, force: true);

    if (_stableSingleFaceFrames >= _holdFramesRequired) {
      _stableSingleFaceFrames = 0;
      unawaited(_captureAndProcess());
    }
  }

  Future<void> _captureAndProcess() async {
    if (_busyCapturing || _controller == null) return;
    _busyCapturing = true;
    _setStatus(ScanStatus.capturing, force: true);

    File? photoFile;
    try {
      await stopStream();
      final photo = await _controller!.takePicture();
      photoFile = File(photo.path);

      final qualityFailure = await _validateCapturedPhoto(photoFile);
      if (qualityFailure != null) {
        await _resumeAfterFailure(status: qualityFailure);
        return;
      }

      final analysis = await _faceService.getFaceAnalysis(photoFile);

      if (!analysis.hasSingleUsableFace) {
        await _resumeAfterFailure(
          status: ScanStatus.error,
          message: 'Could not get a clear face. Please try again.',
        );
        return;
      }

      if (!_faceService.isLive(analysis.livenessConfidence)) {
        await _resumeAfterFailure(status: ScanStatus.livenessFailed);
        return;
      }

      if (mode == FaceScanMode.enroll) {
        await _handleEnrollCapture(analysis.embedding!);
        return;
      }

      await _handleAttendanceCapture(analysis.embedding!);
    } catch (e) {
      await _resumeAfterFailure(status: ScanStatus.error, message: 'Error: $e');
    } finally {
      photoFile?.delete().ignore();
    }
  }

  Future<void> _handleEnrollCapture(List<double> embedding) async {
    _enrollEmbeddings.add(embedding);
    _enrollStep++;
    if (_enrollStep >= kEnrollSequence.length) {
      _busyCapturing = false;
      if (!_enrollmentCompleter.isCompleted) {
        _enrollmentCompleter.complete(List.of(_enrollEmbeddings));
      }
      return;
    }
    await _resumeAfterPoseCapture();
  }

  Future<void> _handleAttendanceCapture(List<double> embedding) async {
    final matched = await onMatch!(embedding);
    if (isDisposed) return;

    if (matched == null) {
      await _resumeAfterFailure(status: ScanStatus.notRecognized);
      return;
    }

    _matchedUser = matched;
    _busyCapturing = false;
    _setStatus(ScanStatus.success, force: true);

    await Future.delayed(const Duration(milliseconds: 1600));
    if (isDisposed) return;
    if (!_attendanceCompleter.isCompleted) {
      _attendanceCompleter.complete(matched);
    }
  }

  Future<void> _resumeAfterPoseCapture() async {
    if (isDisposed) return;
    _busyCapturing = false;
    _setStatus(ScanStatus.poseCaptured, force: true);
    await Future.delayed(const Duration(milliseconds: 700));
    if (isDisposed) return;
    _setStatus(ScanStatus.noFace, force: true);
    await startStream();
  }

  Future<void> _resumeAfterFailure({
    required ScanStatus status,
    String? message,
  }) async {
    if (isDisposed) return;
    _busyCapturing = false;
    _errorMessage = message;
    _setStatus(status, force: true);
    await Future.delayed(const Duration(milliseconds: 1600));
    if (isDisposed) return;
    _setStatus(ScanStatus.noFace, force: true);
    await startStream();
  }

  void _fail(String message) {
    if (isDisposed) return;
    _errorMessage = message;
    _setStatus(ScanStatus.error, force: true);
  }

  /// Repaints only on an actual status change — the detection loop runs on
  /// every preview frame, so unconditional notifying would rebuild the
  /// camera preview continuously.
  void _setStatus(ScanStatus status, {bool force = false}) {
    if (!force && _status == status) return;
    _status = status;
    safeNotify();
  }

  String get statusMessage {
    switch (_status) {
      case ScanStatus.initializing:
        return 'Starting camera...';
      case ScanStatus.noFace:
        return mode == FaceScanMode.enroll
            ? enrollStepLabel
            : 'Please position your face inside the frame';
      case ScanStatus.multipleFaces:
        return 'Keep only one face in the frame';
      case ScanStatus.faceObstructed:
        return 'Face is partially covered — remove any obstruction and try again';
      case ScanStatus.eyesClosed:
        return 'Please open your eyes';
      case ScanStatus.singleFace:
        return mode == FaceScanMode.enroll
            ? enrollStepLabel
            : 'Face detected — hold still...';
      case ScanStatus.capturing:
        return 'Verifying...';
      case ScanStatus.poseCaptured:
        return 'Captured ✓';
      case ScanStatus.success:
        return mode == FaceScanMode.enroll
            ? 'Face profile captured'
            : 'Attendance Marked Successfully';
      case ScanStatus.notRecognized:
        return 'Face Recognition Failed';
      case ScanStatus.livenessFailed:
        return 'Liveness check failed — use a live camera, not a photo';
      case ScanStatus.faceOutOfFrame:
        return 'Show your complete face inside the frame';
      case ScanStatus.faceTooSmall:
        return 'Move closer to the camera';
      case ScanStatus.poseInvalid:
        return 'Face the camera directly';
      case ScanStatus.error:
        return _errorMessage ?? 'Something went wrong';
    }
  }

  Color get statusColor {
    switch (_status) {
      case ScanStatus.success:
      case ScanStatus.poseCaptured:
        return Colors.greenAccent;
      case ScanStatus.notRecognized:
      case ScanStatus.livenessFailed:
      case ScanStatus.error:
      case ScanStatus.multipleFaces:
      case ScanStatus.faceObstructed:
      case ScanStatus.eyesClosed:
      case ScanStatus.faceOutOfFrame:
      case ScanStatus.faceTooSmall:
      case ScanStatus.poseInvalid:
        return Colors.redAccent;
      case ScanStatus.singleFace:
        return Colors.lightGreenAccent;
      default:
        return Colors.white;
    }
  }

  @override
  void dispose() {
    stopStream();
    _controller?.dispose();
    _liveDetector.dispose();
    _captureDetector.close();
    super.dispose();
  }
}
