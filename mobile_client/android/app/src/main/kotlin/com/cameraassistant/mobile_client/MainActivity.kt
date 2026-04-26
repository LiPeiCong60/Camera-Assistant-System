package com.cameraassistant.mobile_client

import android.content.ContentValues
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

class MainActivity : FlutterActivity() {
    private var poseBridge: MediaPipePoseBridge? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val bridge = MediaPipePoseBridge(this)
        poseBridge = bridge
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "camera_assistant/pose_detector",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "isAvailable" -> result.success(bridge.isAvailable())
                "detectPose" -> bridge.detectPose(call.arguments, result)
                "close" -> {
                    bridge.close()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "camera_assistant/gallery_saver",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "saveImage" -> saveImageToGallery(call.arguments, result)
                else -> result.notImplemented()
            }
        }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        poseBridge?.close()
        poseBridge = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    private fun saveImageToGallery(arguments: Any?, result: MethodChannel.Result) {
        try {
            val args = arguments as? Map<*, *>
            val bytes = args?.get("bytes") as? ByteArray
            val fileName = (args?.get("fileName") as? String)
                ?.takeIf { it.isNotBlank() }
                ?: "cloud_shadow_capture.jpg"
            if (bytes == null || bytes.isEmpty()) {
                result.error("invalid_bytes", "Image bytes are empty.", null)
                return
            }

            val resolver = applicationContext.contentResolver
            val mimeType = when (fileName.substringAfterLast('.', "jpg").lowercase()) {
                "png" -> "image/png"
                "webp" -> "image/webp"
                else -> "image/jpeg"
            }

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val values = ContentValues().apply {
                    put(MediaStore.Images.Media.DISPLAY_NAME, fileName)
                    put(MediaStore.Images.Media.MIME_TYPE, mimeType)
                    put(MediaStore.Images.Media.RELATIVE_PATH, Environment.DIRECTORY_PICTURES + "/云影随行")
                    put(MediaStore.Images.Media.IS_PENDING, 1)
                }
                val uri = resolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values)
                if (uri == null) {
                    result.error("insert_failed", "Unable to create gallery item.", null)
                    return
                }
                resolver.openOutputStream(uri)?.use { stream ->
                    stream.write(bytes)
                } ?: run {
                    result.error("open_failed", "Unable to open gallery item.", null)
                    return
                }
                values.clear()
                values.put(MediaStore.Images.Media.IS_PENDING, 0)
                resolver.update(uri, values, null, null)
                result.success(uri.toString())
                return
            }

            val picturesDir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_PICTURES)
            val appDir = File(picturesDir, "云影随行")
            if (!appDir.exists()) {
                appDir.mkdirs()
            }
            val target = File(appDir, fileName)
            FileOutputStream(target).use { stream -> stream.write(bytes) }
            val values = ContentValues().apply {
                put(MediaStore.Images.Media.DATA, target.absolutePath)
                put(MediaStore.Images.Media.DISPLAY_NAME, fileName)
                put(MediaStore.Images.Media.MIME_TYPE, mimeType)
            }
            resolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values)
            result.success(target.absolutePath)
        } catch (error: Exception) {
            result.error("save_failed", error.message ?: "Save image failed.", null)
        }
    }
}
