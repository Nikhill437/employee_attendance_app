import 'package:flutter/services.dart';

import '../../data/models/face_analysis_model.dart';

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
    if (result == null) return const FaceAnalysis.empty();
    return FaceAnalysis.fromMap(result);
  }
}
