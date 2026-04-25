package com.cameraassistant.mobile_client

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.ImageFormat
import android.graphics.Matrix
import android.graphics.Rect
import android.graphics.YuvImage
import com.google.mediapipe.framework.image.BitmapImageBuilder
import com.google.mediapipe.tasks.core.BaseOptions
import com.google.mediapipe.tasks.vision.core.RunningMode
import com.google.mediapipe.tasks.vision.poselandmarker.PoseLandmarker
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

class MediaPipePoseBridge(private val context: Context) {
    private val executor = Executors.newSingleThreadExecutor()
    private val closed = AtomicBoolean(false)
    private var poseLandmarker: PoseLandmarker? = null
    private var lastTimestampMs = 0L

    fun isAvailable(): Boolean {
        return try {
            ensurePoseLandmarker()
            true
        } catch (_: Throwable) {
            false
        }
    }

    fun detectPose(arguments: Any?, result: MethodChannel.Result) {
        if (closed.get()) {
            result.error("closed", "MediaPipe pose detector is closed.", null)
            return
        }
        val args = arguments as? Map<*, *>
        val bytes = args?.get("bytes") as? ByteArray
        val width = (args?.get("width") as? Number)?.toInt() ?: 0
        val height = (args?.get("height") as? Number)?.toInt() ?: 0
        val rotationDegrees = (args?.get("rotationDegrees") as? Number)?.toInt() ?: 0
        val timestampMs = (args?.get("timestampMs") as? Number)?.toLong()
            ?: System.currentTimeMillis()

        if (bytes == null || width <= 0 || height <= 0) {
            result.error("bad_arguments", "Invalid NV21 frame arguments.", null)
            return
        }

        executor.execute {
            try {
                val detector = ensurePoseLandmarker()
                val bitmap = nv21ToUprightBitmap(bytes, width, height, rotationDegrees)
                val mpImage = BitmapImageBuilder(bitmap).build()
                val safeTimestamp = nextTimestamp(timestampMs)
                val poseResult = detector.detectForVideo(mpImage, safeTimestamp)
                result.success(
                    mapOf(
                        "width" to bitmap.width,
                        "height" to bitmap.height,
                        "timestampMs" to safeTimestamp,
                        "landmarks" to poseResult.landmarks().firstOrNull()
                            ?.mapIndexed { index, landmark ->
                                mapOf(
                                    "index" to index,
                                    "x" to landmark.x().toDouble(),
                                    "y" to landmark.y().toDouble(),
                                    "z" to landmark.z().toDouble(),
                                    "visibility" to landmark.visibility().orElse(0.0f).toDouble(),
                                    "presence" to landmark.presence().orElse(0.0f).toDouble(),
                                )
                            }.orEmpty(),
                    )
                )
            } catch (error: Throwable) {
                result.error("mediapipe_pose_failed", error.message, null)
            }
        }
    }

    fun close() {
        if (closed.compareAndSet(false, true)) {
            executor.execute {
                poseLandmarker?.close()
                poseLandmarker = null
            }
            executor.shutdown()
        }
    }

    @Synchronized
    private fun ensurePoseLandmarker(): PoseLandmarker {
        val existing = poseLandmarker
        if (existing != null) {
            return existing
        }
        val baseOptions = BaseOptions.builder()
            .setModelAssetPath("pose_landmarker_lite.task")
            .build()
        val options = PoseLandmarker.PoseLandmarkerOptions.builder()
            .setBaseOptions(baseOptions)
            .setRunningMode(RunningMode.VIDEO)
            .setNumPoses(1)
            .setMinPoseDetectionConfidence(0.35f)
            .setMinPosePresenceConfidence(0.35f)
            .setMinTrackingConfidence(0.35f)
            .build()
        return PoseLandmarker.createFromOptions(context, options).also {
            poseLandmarker = it
        }
    }

    @Synchronized
    private fun nextTimestamp(timestampMs: Long): Long {
        val safe = if (timestampMs <= lastTimestampMs) lastTimestampMs + 1 else timestampMs
        lastTimestampMs = safe
        return safe
    }

    private fun nv21ToUprightBitmap(
        bytes: ByteArray,
        width: Int,
        height: Int,
        rotationDegrees: Int,
    ): Bitmap {
        val yuvImage = YuvImage(bytes, ImageFormat.NV21, width, height, null)
        val jpeg = ByteArrayOutputStream()
        yuvImage.compressToJpeg(Rect(0, 0, width, height), 82, jpeg)
        val rawBitmap = BitmapFactory.decodeByteArray(jpeg.toByteArray(), 0, jpeg.size())
            ?: throw IllegalStateException("Unable to decode camera frame.")
        val normalizedRotation = ((rotationDegrees % 360) + 360) % 360
        if (normalizedRotation == 0) {
            return rawBitmap
        }
        val matrix = Matrix().apply {
            postRotate(normalizedRotation.toFloat())
        }
        val rotated = Bitmap.createBitmap(
            rawBitmap,
            0,
            0,
            rawBitmap.width,
            rawBitmap.height,
            matrix,
            true,
        )
        if (rotated != rawBitmap) {
            rawBitmap.recycle()
        }
        return rotated
    }
}
