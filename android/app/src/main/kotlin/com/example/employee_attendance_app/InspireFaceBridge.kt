package com.example.employee_attendance_app

import android.content.Context
import android.graphics.BitmapFactory
import android.os.Handler
import android.os.Looper
import com.insightface.sdk.inspireface.InspireFace
import com.insightface.sdk.inspireface.base.CustomParameter
import com.insightface.sdk.inspireface.base.Session
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

/**
 * Bridges Dart calls to InspireFace's Android SDK (JNI-wrapped, so this goes
 * through a MethodChannel rather than Dart FFI). Detection, alignment,
 * embedding extraction, and liveness confidence all happen inside
 * InspireFace's Session — the Dart side just hands over a normalized
 * (EXIF-baked, upright) image and gets an embedding + liveness score back.
 */
class InspireFaceBridge(private val context: Context) : MethodChannel.MethodCallHandler {

    companion object {
        const val CHANNEL = "employee_attendance_app/inspireface"
        private var launched = false
        private var session: Session? = null
        private var sessionParam: CustomParameter? = null
    }

    private val worker = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "extractEmbedding" -> {
                val bytes = call.argument<ByteArray>("imageBytes")
                if (bytes == null) {
                    result.error("BAD_ARGS", "imageBytes is required", null)
                    return
                }
                worker.execute { handleExtractEmbedding(bytes, result) }
            }
            else -> result.notImplemented()
        }
    }

    private fun ensureReady(): Pair<Session, CustomParameter> {
        if (!launched) {
            val ok = InspireFace.GlobalLaunch(context, InspireFace.PIKACHU)
            if (ok != true) {
                throw IllegalStateException("InspireFace.GlobalLaunch failed")
            }
            launched = true
        }
        var s = session
        var p = sessionParam
        if (s == null || p == null) {
            p = InspireFace.CreateCustomParameter()
                .enableRecognition(true)
                .enableLiveness(true)
            // (parameter, detMode, maxDetectNum, detectPixelLevel, unused)
            // maxDetectNum=1: this app only ever wants a single enrolled/scanned face.
            s = InspireFace.CreateSession(
                p,
                InspireFace.DETECT_MODE_ALWAYS_DETECT,
                1,
                -1,
                -1,
            )
            session = s
            sessionParam = p
        }
        return Pair(s, p)
    }

    private fun handleExtractEmbedding(bytes: ByteArray, result: MethodChannel.Result) {
        try {
            val (session, param) = ensureReady()
            val bitmap = BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
                ?: throw IllegalArgumentException("Could not decode image bytes")

            val stream = InspireFace.CreateImageStreamFromBitmap(
                bitmap,
                InspireFace.CAMERA_ROTATION_0,
            )
            try {
                val faces = InspireFace.ExecuteFaceTrack(session, stream)
                val faceCount = faces.detectedNum

                if (faceCount != 1) {
                    mainHandler.post {
                        result.success(
                            mapOf(
                                "faceCount" to faceCount,
                                "embedding" to null,
                                "livenessConfidence" to null,
                            ),
                        )
                    }
                    return
                }

                val feature = InspireFace.ExtractFaceFeature(session, stream, faces.tokens[0])
                val embedding = feature.data.map { it.toDouble() }

                // Populates the session's liveness result for this frame;
                // GetRGBLivenessConfidence below only returns meaningful data
                // after this pipeline step has run.
                InspireFace.MultipleFacePipelineProcess(session, stream, faces, param)
                val liveness = InspireFace.GetRGBLivenessConfidence(session)
                val livenessConfidence = liveness?.confidence?.firstOrNull()?.toDouble()

                mainHandler.post {
                    result.success(
                        mapOf(
                            "faceCount" to faceCount,
                            "embedding" to embedding,
                            "livenessConfidence" to livenessConfidence,
                        ),
                    )
                }
            } finally {
                InspireFace.ReleaseImageStream(stream)
            }
        } catch (e: Exception) {
            mainHandler.post {
                result.error("INSPIREFACE_ERROR", e.message, null)
            }
        }
    }
}
