import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import '../../data/models/employee_model.dart';
import '../../data/models/face_analysis_model.dart';
import 'inspireface_bridge.dart';

class FaceRecognitionService {
  static final FaceRecognitionService _instance =
      FaceRecognitionService._internal();
  factory FaceRecognitionService() => _instance;
  FaceRecognitionService._internal();

  // Similarity threshold — tune this based on real-world testing (0.55–0.75
  // is typical for cosine similarity, but InspireFace also exposes its own
  // recommended threshold; validate against actual enrollment photos before
  // trusting this default).
  static const double matchThreshold = 0.65;

  // Minimum lead the best candidate must have over the runner-up for a 1:N
  // (walk-up) identification to accept it — on top of matchThreshold, not
  // instead of it. verify()'s single threshold is enough for 1:1 (there's
  // only one candidate), but identify() compares against every enrolled
  // worker, so two similar-looking people can both clear matchThreshold;
  // this margin is what stops that from picking one of them at random.
  // Same caveat as matchThreshold: needs validation against real enrollment
  // photos at production roster size before being trusted.
  static const double identifyMargin = 0.08;

  // Below this, a detected face is treated as a spoof attempt (photo/video)
  // rather than a live person. InspireFace-specific; needs validation
  // against real spoof attempts (printed photo, phone screen replay) before
  // being trusted as a security boundary.
  static const double livenessThreshold = 0.75;

  /// Runs face detection + embedding + liveness on [imageFile] via
  /// InspireFace (native, on-device).
  Future<FaceAnalysis> getFaceAnalysis(File imageFile) async {
    final bytes = await imageFile.readAsBytes();
    var original = img.decodeImage(bytes);
    if (original == null) return const FaceAnalysis.empty();
    // decodeImage does not bake EXIF rotation into the pixel buffer, and
    // InspireFace expects an already-upright image — without this, capture
    // from front cameras that write rotated JPEGs would be misread.
    original = img.bakeOrientation(original);

    final normalized = Uint8List.fromList(img.encodePng(original));
    return InspireFaceBridge.analyze(normalized);
  }

  /// True unless InspireFace positively flagged the frame as not-live.
  /// Missing liveness data (null) fails closed — we can't otherwise tell a
  /// printed photo from a real face, and the whole point of this check is
  /// to not silently skip that protection.
  bool isLive(double? livenessConfidence) {
    if (livenessConfidence == null) return false;
    return livenessConfidence >= livenessThreshold;
  }

  /// Cosine similarity between two embeddings. Closer to 1 = more similar.
  double cosineSimilarity(List<double> a, List<double> b) {
    double dot = 0, normA = 0, normB = 0;
    for (int i = 0; i < a.length; i++) {
      dot += a[i] * b[i];
      normA += a[i] * a[i];
      normB += b[i] * b[i];
    }
    if (normA == 0 || normB == 0) return 0;
    return dot / (sqrt(normA) * sqrt(normB));
  }

  /// Best similarity between [embedding] and any of an employee's enrolled
  /// pose embeddings — whichever captured angle is closest to the live
  /// frame wins.
  double bestSimilarity(List<double> embedding, List<List<double>> enrolledEmbeddings) {
    double best = -1;
    for (final enrolled in enrolledEmbeddings) {
      final score = cosineSimilarity(embedding, enrolled);
      if (score > best) best = score;
    }
    return best;
  }

  /// Verifies [embedding] against a single claimed identity's multi-pose
  /// profile (1:1 — the employee looked up by employeeId at login), rather
  /// than searching across every enrolled employee. Comparing only against
  /// the claimed identity removes the false-accept risk that walk-up
  /// (1:N) identification carries.
  bool verify(List<double> embedding, List<List<double>> enrolledEmbeddings) {
    final score = bestSimilarity(embedding, enrolledEmbeddings);
    debugPrint(
      'FaceRecognitionService: verify similarity=$score '
      '(threshold=$matchThreshold)',
    );
    return score >= matchThreshold;
  }

  /// Identifies which of [candidates] (every enrolled worker, each with one
  /// or more pose embeddings) [embedding] belongs to — 1:N, searched across
  /// everyone rather than verified against one claimed identity. Returns
  /// null when no candidate clears [matchThreshold], or the best candidate
  /// doesn't lead the runner-up by at least [identifyMargin] (too close to
  /// call safely). A candidate with no enrolled embeddings is skipped
  /// rather than scored.
  Employee? identify(List<double> embedding, List<Employee> candidates) {
    Employee? best;
    double bestScore = -1;
    double secondScore = -1;
    for (final candidate in candidates) {
      if (candidate.faceEmbeddings.isEmpty) continue;
      final score = bestSimilarity(embedding, candidate.faceEmbeddings);
      if (score > bestScore) {
        secondScore = bestScore;
        bestScore = score;
        best = candidate;
      } else if (score > secondScore) {
        secondScore = score;
      }
    }
    debugPrint(
      'FaceRecognitionService: identify best=$bestScore second=$secondScore '
      '(threshold=$matchThreshold, margin=$identifyMargin)',
    );
    if (best == null || bestScore < matchThreshold) return null;
    if (bestScore - secondScore < identifyMargin) return null;
    return best;
  }

  void dispose() {}
}
