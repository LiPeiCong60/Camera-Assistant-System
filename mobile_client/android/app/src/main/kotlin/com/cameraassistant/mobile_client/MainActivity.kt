package com.cameraassistant.mobile_client

import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel

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
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        poseBridge?.close()
        poseBridge = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
