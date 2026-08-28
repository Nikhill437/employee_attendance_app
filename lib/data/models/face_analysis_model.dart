/// Result of running InspireFace on a single captured frame.
class FaceAnalysis {
  final int faceCount;
  final List<double>? embedding;

  /// 0..1 confidence that the detected face is a live person rather than a
  /// photo/video/mask, or null if InspireFace didn't return one for this
  /// frame.
  final double? livenessConfidence;

  const FaceAnalysis({
    required this.faceCount,
    required this.embedding,
    required this.livenessConfidence,
  });

  /// An analysis for a frame InspireFace could not read at all.
  const FaceAnalysis.empty()
    : faceCount = 0,
      embedding = null,
      livenessConfidence = null;

  factory FaceAnalysis.fromMap(Map<String, dynamic> map) {
    return FaceAnalysis(
      faceCount: map['faceCount'] as int? ?? 0,
      embedding: (map['embedding'] as List?)?.cast<double>(),
      livenessConfidence: map['livenessConfidence'] as double?,
    );
  }

  /// True when exactly one face was found and an embedding was extracted for
  /// it — the only shape the enrollment and login flows can act on.
  bool get hasSingleUsableFace => faceCount == 1 && embedding != null;
}
