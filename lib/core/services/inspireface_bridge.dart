import 'package:flutter/services.dart';

/// Result of running InspireFace on a single captured frame.
class FaceAnalysis {
  final int faceCount;
  final List<double>? embedding;

  /// 0..1 confidence that the detected face is a live person rather than a
  /// photo/video/mask, or null if InspireFace didn't return one for this
  /// frame.
  final double? livenessConfidence;

  FaceAnalysis({
    required this.faceCount,
    required this.embedding,
    required this.livenessConfidence,
  });
}

/// Thin wrapper around the native InspireFace MethodChannel (Android only
/// for now — InspireFace has no Flutter package, so this talks to a Kotlin
/// bridge that wraps their Android SDK). Detection, alignment, embedding
/// extraction, and liveness scoring all happen natively inside InspireFace's
/// Session.
class InspireFaceBridge {
  static const MethodChannel _channel = MethodChannel(
    'employee_attendance_app/inspireface',
  );

  /// Runs InspireFace on [imageBytes] (an upright, EXIF-baked image).
  static Future<FaceAnalysis> analyze(Uint8List imageBytes) async {
    final result = await _channel.invokeMapMethod<String, dynamic>(
      'extractEmbedding',
      {'imageBytes': imageBytes},
    );
    if (result == null) {
      return FaceAnalysis(faceCount: 0, embedding: null, livenessConfidence: null);
    }

    final embedding = (result['embedding'] as List?)?.cast<double>();
    return FaceAnalysis(
      faceCount: result['faceCount'] as int? ?? 0,
      embedding: embedding,
      livenessConfidence: result['livenessConfidence'] as double?,
    );
  }
}
