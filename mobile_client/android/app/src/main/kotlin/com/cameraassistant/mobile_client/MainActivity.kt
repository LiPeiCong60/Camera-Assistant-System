package com.cameraassistant.mobile_client

import android.content.ContentValues
import android.content.Intent
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
                "saveImageFile" -> saveImageFileToGallery(call.arguments, result)
                "saveVideo" -> saveVideoToGallery(call.arguments, result)
                "openGallery" -> openGallery(result)
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

    private fun saveImageFileToGallery(arguments: Any?, result: MethodChannel.Result) {
        try {
            val args = arguments as? Map<*, *>
            val path = (args?.get("path") as? String)?.takeIf { it.isNotBlank() }
            val source = path?.let { File(it) }
            if (source == null || !source.exists() || !source.isFile) {
                result.error("invalid_file", "Image file does not exist.", null)
                return
            }
            val fileName = (args?.get("fileName") as? String)
                ?.takeIf { it.isNotBlank() }
                ?: source.name.ifBlank { "cloud_shadow_capture.jpg" }
            val mimeType = when (fileName.substringAfterLast('.', "jpg").lowercase()) {
                "png" -> "image/png"
                "webp" -> "image/webp"
                else -> "image/jpeg"
            }
            saveFileToGallery(
                source = source,
                fileName = fileName,
                mimeType = mimeType,
                collection = MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
                relativePath = Environment.DIRECTORY_PICTURES + "/云影随行",
                result = result,
            )
        } catch (error: Exception) {
            result.error("save_failed", error.message ?: "Save image failed.", null)
        }
    }

    private fun saveVideoToGallery(arguments: Any?, result: MethodChannel.Result) {
        try {
            val args = arguments as? Map<*, *>
            val path = (args?.get("path") as? String)?.takeIf { it.isNotBlank() }
            val source = path?.let { File(it) }
            if (source == null || !source.exists() || !source.isFile) {
                result.error("invalid_file", "Video file does not exist.", null)
                return
            }
            val fileName = (args?.get("fileName") as? String)
                ?.takeIf { it.isNotBlank() }
                ?: source.name.ifBlank { "cloud_shadow_video.mp4" }
            val mimeType = when (fileName.substringAfterLast('.', "mp4").lowercase()) {
                "mov" -> "video/quicktime"
                "3gp" -> "video/3gpp"
                "webm" -> "video/webm"
                else -> "video/mp4"
            }
            saveFileToGallery(
                source = source,
                fileName = fileName,
                mimeType = mimeType,
                collection = MediaStore.Video.Media.EXTERNAL_CONTENT_URI,
                relativePath = Environment.DIRECTORY_MOVIES + "/云影随行",
                result = result,
            )
        } catch (error: Exception) {
            result.error("save_failed", error.message ?: "Save video failed.", null)
        }
    }

    private fun saveFileToGallery(
        source: File,
        fileName: String,
        mimeType: String,
        collection: android.net.Uri,
        relativePath: String,
        result: MethodChannel.Result,
    ) {
        val resolver = applicationContext.contentResolver
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val values = ContentValues().apply {
                put(MediaStore.MediaColumns.DISPLAY_NAME, fileName)
                put(MediaStore.MediaColumns.MIME_TYPE, mimeType)
                put(MediaStore.MediaColumns.RELATIVE_PATH, relativePath)
                put(MediaStore.MediaColumns.IS_PENDING, 1)
            }
            val uri = resolver.insert(collection, values)
            if (uri == null) {
                result.error("insert_failed", "Unable to create gallery item.", null)
                return
            }
            resolver.openOutputStream(uri)?.use { output ->
                source.inputStream().use { input -> input.copyTo(output) }
            } ?: run {
                result.error("open_failed", "Unable to open gallery item.", null)
                return
            }
            values.clear()
            values.put(MediaStore.MediaColumns.IS_PENDING, 0)
            resolver.update(uri, values, null, null)
            result.success(uri.toString())
            return
        }

        val baseDir = if (mimeType.startsWith("video/")) {
            Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_MOVIES)
        } else {
            Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_PICTURES)
        }
        val appDir = File(baseDir, "云影随行")
        if (!appDir.exists()) {
            appDir.mkdirs()
        }
        val target = File(appDir, fileName)
        source.inputStream().use { input ->
            FileOutputStream(target).use { output -> input.copyTo(output) }
        }
        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DATA, target.absolutePath)
            put(MediaStore.MediaColumns.DISPLAY_NAME, fileName)
            put(MediaStore.MediaColumns.MIME_TYPE, mimeType)
        }
        resolver.insert(collection, values)
        result.success(target.absolutePath)
    }

    private fun openGallery(result: MethodChannel.Result) {
        try {
            val intent = Intent(Intent.ACTION_VIEW, MediaStore.Images.Media.EXTERNAL_CONTENT_URI).apply {
                type = "image/*"
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            if (intent.resolveActivity(packageManager) == null) {
                result.success(false)
                return
            }
            startActivity(intent)
            result.success(true)
        } catch (error: Exception) {
            result.error("open_failed", error.message ?: "Open gallery failed.", null)
        }
    }
}
