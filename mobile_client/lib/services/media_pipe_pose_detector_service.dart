import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/services.dart';

class MediaPipePoseDetectorService {
  MediaPipePoseDetectorService();

  static const MethodChannel _channel = MethodChannel(
    'camera_assistant/pose_detector',
  );

  bool _disabled = false;

  bool get isSupportedPlatform => Platform.isAndroid && !_disabled;

  Future<bool> isAvailable() async {
    if (!isSupportedPlatform) {
      return false;
    }
    try {
      return await _channel.invokeMethod<bool>('isAvailable') ?? false;
    } on PlatformException {
      _disabled = true;
      return false;
    } on MissingPluginException {
      _disabled = true;
      return false;
    }
  }

  Future<MediaPipePoseResult?> detect({
    required CameraImage image,
    required int rotationDegrees,
    required int timestampMs,
  }) async {
    if (!isSupportedPlatform ||
        image.planes.length != 1 ||
        image.format.group != ImageFormatGroup.nv21) {
      return null;
    }
    try {
      final raw = await _channel
          .invokeMapMethod<String, dynamic>('detectPose', {
            'bytes': Uint8List.fromList(image.planes.first.bytes),
            'width': image.width,
            'height': image.height,
            'rotationDegrees': rotationDegrees,
            'timestampMs': timestampMs,
          });
      if (raw == null) {
        return null;
      }
      return MediaPipePoseResult.fromJson(raw);
    } on PlatformException {
      _disabled = true;
      return null;
    } on MissingPluginException {
      _disabled = true;
      return null;
    }
  }

  Future<void> close() async {
    if (!Platform.isAndroid) {
      return;
    }
    try {
      await _channel.invokeMethod<void>('close');
    } catch (_) {
      // Ignore native cleanup errors during route disposal.
    }
  }
}

class MediaPipePoseResult {
  const MediaPipePoseResult({
    required this.width,
    required this.height,
    required this.timestampMs,
    required this.landmarks,
  });

  final int width;
  final int height;
  final int timestampMs;
  final List<MediaPipePoseLandmark> landmarks;

  bool get hasPose => landmarks.isNotEmpty;

  factory MediaPipePoseResult.fromJson(Map<String, dynamic> json) {
    final rawLandmarks = json['landmarks'] as List<dynamic>? ?? const [];
    return MediaPipePoseResult(
      width: (json['width'] as num?)?.toInt() ?? 0,
      height: (json['height'] as num?)?.toInt() ?? 0,
      timestampMs: (json['timestampMs'] as num?)?.toInt() ?? 0,
      landmarks: rawLandmarks
          .whereType<Map<dynamic, dynamic>>()
          .map(
            (item) => MediaPipePoseLandmark.fromJson(
              item.map((key, value) => MapEntry('$key', value)),
            ),
          )
          .toList(growable: false),
    );
  }
}

class MediaPipePoseLandmark {
  const MediaPipePoseLandmark({
    required this.index,
    required this.x,
    required this.y,
    required this.z,
    required this.visibility,
    required this.presence,
  });

  final int index;
  final double x;
  final double y;
  final double z;
  final double visibility;
  final double presence;

  double get confidence {
    if (visibility <= 0 && presence <= 0) {
      return 1;
    }
    if (visibility <= 0) {
      return presence;
    }
    if (presence <= 0) {
      return visibility;
    }
    return visibility < presence ? visibility : presence;
  }

  factory MediaPipePoseLandmark.fromJson(Map<String, dynamic> json) {
    return MediaPipePoseLandmark(
      index: (json['index'] as num?)?.toInt() ?? 0,
      x: (json['x'] as num?)?.toDouble() ?? 0,
      y: (json['y'] as num?)?.toDouble() ?? 0,
      z: (json['z'] as num?)?.toDouble() ?? 0,
      visibility: (json['visibility'] as num?)?.toDouble() ?? 0,
      presence: (json['presence'] as num?)?.toDouble() ?? 0,
    );
  }
}
