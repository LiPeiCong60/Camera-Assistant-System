part of '../device_link_page.dart';

class _MobilePushTools {
  const _MobilePushTools._();

  static const Map<DeviceOrientation, int> _orientationDegrees =
      <DeviceOrientation, int>{
        DeviceOrientation.portraitUp: 0,
        DeviceOrientation.landscapeLeft: 90,
        DeviceOrientation.portraitDown: 180,
        DeviceOrientation.landscapeRight: 270,
      };

  static bool requiresMirrorCorrection(CameraLensDirection direction) {
    return direction == CameraLensDirection.front;
  }

  static int resolveRotationDegrees({
    required DeviceOrientation? deviceOrientation,
    required CameraLensDirection? lensDirection,
    required int? sensorOrientation,
    required int fallbackRotationDegrees,
  }) {
    if (deviceOrientation == null ||
        lensDirection == null ||
        sensorOrientation == null) {
      return fallbackRotationDegrees >= 0 ? fallbackRotationDegrees : 0;
    }

    final deviceDegrees = _orientationDegrees[deviceOrientation] ?? 0;
    if (lensDirection == CameraLensDirection.front) {
      return (sensorOrientation + deviceDegrees) % 360;
    }
    return (sensorOrientation - deviceDegrees + 360) % 360;
  }

  static String buildNv21ConfigJson({
    required CameraImage image,
    required int rotationDegrees,
  }) {
    return jsonEncode(<String, dynamic>{
      'type': 'config',
      'format': 'nv21',
      'width': image.width,
      'height': image.height,
      'rotation_degrees': rotationDegrees,
    });
  }

  static Uint8List? encodeCameraImageAsNv21(CameraImage image) {
    final expectedSize = image.width * image.height * 3 ~/ 2;
    if (image.planes.length == 1 &&
        image.planes.first.bytes.length == expectedSize) {
      return image.planes.first.bytes;
    }
    if (image.planes.length < 3) {
      return null;
    }

    final yPlane = image.planes[0];
    final uPlane = image.planes[1];
    final vPlane = image.planes[2];
    final output = Uint8List(expectedSize);
    var offset = 0;

    for (var row = 0; row < image.height; row += 1) {
      final rowStart = row * yPlane.bytesPerRow;
      final yPixelStride = yPlane.bytesPerPixel ?? 1;
      if (yPixelStride == 1) {
        final rowEnd = rowStart + image.width;
        if (rowEnd > yPlane.bytes.length) {
          return null;
        }
        output.setRange(offset, offset + image.width, yPlane.bytes, rowStart);
        offset += image.width;
        continue;
      }
      for (var col = 0; col < image.width; col += 1) {
        final index = rowStart + col * yPixelStride;
        if (index >= yPlane.bytes.length) {
          return null;
        }
        output[offset] = yPlane.bytes[index];
        offset += 1;
      }
    }

    final uvWidth = image.width ~/ 2;
    final uvHeight = image.height ~/ 2;
    final uPixelStride = uPlane.bytesPerPixel ?? 1;
    final vPixelStride = vPlane.bytesPerPixel ?? 1;
    for (var row = 0; row < uvHeight; row += 1) {
      final uRowStart = row * uPlane.bytesPerRow;
      final vRowStart = row * vPlane.bytesPerRow;
      for (var col = 0; col < uvWidth; col += 1) {
        final uIndex = uRowStart + col * uPixelStride;
        final vIndex = vRowStart + col * vPixelStride;
        if (uIndex >= uPlane.bytes.length || vIndex >= vPlane.bytes.length) {
          return null;
        }
        output[offset] = vPlane.bytes[vIndex];
        output[offset + 1] = uPlane.bytes[uIndex];
        offset += 2;
      }
    }

    return output;
  }
}
