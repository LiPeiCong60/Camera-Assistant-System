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
    if (image.planes.length == 2) {
      return _encodeTwoPlaneNv21(image, expectedSize);
    }
    if (image.planes.length < 3) {
      return null;
    }

    return _encodeThreePlaneYuv420AsNv21(image, expectedSize);
  }

  static Uint8List? encodeCameraImageAsJpeg(
    CameraImage image, {
    required int rotationDegrees,
    int maxSide = 640,
    int quality = 62,
  }) {
    var rgb = _cameraImageToRgb(image);
    if (rgb == null) {
      return null;
    }

    switch (rotationDegrees % 360) {
      case 90:
        rgb = img.copyRotate(rgb, angle: 90);
        break;
      case 180:
        rgb = img.copyRotate(rgb, angle: 180);
        break;
      case 270:
        rgb = img.copyRotate(rgb, angle: -90);
        break;
    }

    final longestSide = math.max(rgb.width, rgb.height);
    if (longestSide > maxSide) {
      final scale = maxSide / longestSide;
      rgb = img.copyResize(
        rgb,
        width: math.max(2, (rgb.width * scale).round()),
        height: math.max(2, (rgb.height * scale).round()),
        interpolation: img.Interpolation.average,
      );
    }

    return Uint8List.fromList(img.encodeJpg(rgb, quality: quality));
  }

  static Uint8List? encodeCameraImageAsPreviewJpeg(
    CameraImage image, {
    required int rotationDegrees,
    int maxSide = 420,
    int quality = 48,
  }) {
    final rotation = rotationDegrees % 360;
    final normalizedRotation = rotation < 0 ? rotation + 360 : rotation;
    final rotateSideways =
        normalizedRotation == 90 || normalizedRotation == 270;
    final rotatedWidth = rotateSideways ? image.height : image.width;
    final rotatedHeight = rotateSideways ? image.width : image.height;
    if (rotatedWidth <= 0 || rotatedHeight <= 0) {
      return null;
    }

    final longestSide = math.max(rotatedWidth, rotatedHeight);
    final scale = longestSide > maxSide ? maxSide / longestSide : 1.0;
    final outputWidth = math.max(2, (rotatedWidth * scale).round());
    final outputHeight = math.max(2, (rotatedHeight * scale).round());
    final output = img.Image(width: outputWidth, height: outputHeight);

    for (var y = 0; y < outputHeight; y += 1) {
      final rotatedY = _scaleCoordinate(y, rotatedHeight, outputHeight);
      for (var x = 0; x < outputWidth; x += 1) {
        final rotatedX = _scaleCoordinate(x, rotatedWidth, outputWidth);
        final sourceX = switch (normalizedRotation) {
          90 => rotatedY,
          180 => image.width - 1 - rotatedX,
          270 => image.width - 1 - rotatedY,
          _ => rotatedX,
        };
        final sourceY = switch (normalizedRotation) {
          90 => image.height - 1 - rotatedX,
          180 => image.height - 1 - rotatedY,
          270 => rotatedX,
          _ => rotatedY,
        };
        final rgb = _readCameraImagePixelRgb(image, sourceX, sourceY);
        if (rgb == null) {
          return null;
        }
        output.setPixelRgb(
          x,
          y,
          (rgb >> 16) & 0xff,
          (rgb >> 8) & 0xff,
          rgb & 0xff,
        );
      }
    }

    return Uint8List.fromList(img.encodeJpg(output, quality: quality));
  }

  static String describeCameraImage(CameraImage image) {
    final planes = image.planes
        .map(
          (plane) =>
              'len=${plane.bytes.length},row=${plane.bytesPerRow},pixel=${plane.bytesPerPixel ?? 0}',
        )
        .join(';');
    return 'format=${image.format.group.name},size=${image.width}x${image.height},planes=${image.planes.length}[$planes]';
  }

  static int _scaleCoordinate(int index, int sourceSize, int outputSize) {
    final value = ((index + 0.5) * sourceSize / outputSize).floor();
    if (value < 0) {
      return 0;
    }
    if (value >= sourceSize) {
      return sourceSize - 1;
    }
    return value;
  }

  static int? _readCameraImagePixelRgb(CameraImage image, int x, int y) {
    if (x < 0 || y < 0 || x >= image.width || y >= image.height) {
      return null;
    }
    if (image.format.group == ImageFormatGroup.bgra8888 &&
        image.planes.isNotEmpty) {
      final plane = image.planes[0];
      final pixelStride = plane.bytesPerPixel ?? 4;
      final index = y * plane.bytesPerRow + x * pixelStride;
      if (pixelStride < 3 || index + 2 >= plane.bytes.length) {
        return null;
      }
      return _packRgb(
        plane.bytes[index + 2],
        plane.bytes[index + 1],
        plane.bytes[index],
      );
    }
    if (image.planes.length == 1) {
      return _readOnePlaneNv21PixelRgb(image, x, y);
    }
    if (image.planes.length == 2) {
      return _readTwoPlaneNv21PixelRgb(image, x, y);
    }
    if (image.planes.length >= 3) {
      return _readThreePlaneYuv420PixelRgb(image, x, y);
    }
    return null;
  }

  static int? _readOnePlaneNv21PixelRgb(CameraImage image, int x, int y) {
    final plane = image.planes[0];
    final ySize = image.width * image.height;
    final expectedSize = ySize * 3 ~/ 2;
    if (plane.bytes.length < expectedSize) {
      return null;
    }
    final yIndex = y * image.width + x;
    final vuIndex = ySize + (y ~/ 2) * image.width + (x ~/ 2) * 2;
    if (vuIndex + 1 >= plane.bytes.length) {
      return null;
    }
    return _yuvToRgbPacked(
      plane.bytes[yIndex],
      plane.bytes[vuIndex + 1],
      plane.bytes[vuIndex],
    );
  }

  static int? _readTwoPlaneNv21PixelRgb(CameraImage image, int x, int y) {
    final yPlane = image.planes[0];
    final vuPlane = image.planes[1];
    final yPixelStride = yPlane.bytesPerPixel ?? 1;
    final vuPixelStride = vuPlane.bytesPerPixel ?? 2;
    final yIndex = y * yPlane.bytesPerRow + x * yPixelStride;
    final vuIndex = (y ~/ 2) * vuPlane.bytesPerRow + (x ~/ 2) * vuPixelStride;
    if (yIndex >= yPlane.bytes.length || vuIndex + 1 >= vuPlane.bytes.length) {
      return null;
    }
    return _yuvToRgbPacked(
      yPlane.bytes[yIndex],
      vuPlane.bytes[vuIndex + 1],
      vuPlane.bytes[vuIndex],
    );
  }

  static int? _readThreePlaneYuv420PixelRgb(CameraImage image, int x, int y) {
    final yPlane = image.planes[0];
    final uPlane = image.planes[1];
    final vPlane = image.planes[2];
    final yPixelStride = yPlane.bytesPerPixel ?? 1;
    final uPixelStride = uPlane.bytesPerPixel ?? 1;
    final vPixelStride = vPlane.bytesPerPixel ?? 1;
    final yIndex = y * yPlane.bytesPerRow + x * yPixelStride;
    final uIndex = (y ~/ 2) * uPlane.bytesPerRow + (x ~/ 2) * uPixelStride;
    final vIndex = (y ~/ 2) * vPlane.bytesPerRow + (x ~/ 2) * vPixelStride;
    if (yIndex >= yPlane.bytes.length ||
        uIndex >= uPlane.bytes.length ||
        vIndex >= vPlane.bytes.length) {
      return null;
    }
    return _yuvToRgbPacked(
      yPlane.bytes[yIndex],
      uPlane.bytes[uIndex],
      vPlane.bytes[vIndex],
    );
  }

  static img.Image? _cameraImageToRgb(CameraImage image) {
    if (image.format.group == ImageFormatGroup.bgra8888 &&
        image.planes.isNotEmpty) {
      return _bgra8888ToRgb(image);
    }
    if (image.planes.length == 1) {
      return _onePlaneNv21ToRgb(image);
    }
    if (image.planes.length == 2) {
      return _twoPlaneNv21ToRgb(image);
    }
    if (image.planes.length >= 3) {
      return _threePlaneYuv420ToRgb(image);
    }
    return null;
  }

  static img.Image? _bgra8888ToRgb(CameraImage image) {
    final plane = image.planes[0];
    final pixelStride = plane.bytesPerPixel ?? 4;
    if (pixelStride < 3) {
      return null;
    }
    final out = img.Image(width: image.width, height: image.height);
    for (var y = 0; y < image.height; y += 1) {
      final rowStart = y * plane.bytesPerRow;
      for (var x = 0; x < image.width; x += 1) {
        final index = rowStart + x * pixelStride;
        if (index + 2 >= plane.bytes.length) {
          return null;
        }
        out.setPixelRgb(
          x,
          y,
          plane.bytes[index + 2],
          plane.bytes[index + 1],
          plane.bytes[index],
        );
      }
    }
    return out;
  }

  static img.Image? _onePlaneNv21ToRgb(CameraImage image) {
    final plane = image.planes[0];
    final ySize = image.width * image.height;
    final expectedSize = ySize * 3 ~/ 2;
    if (plane.bytes.length < expectedSize) {
      return null;
    }
    final out = img.Image(width: image.width, height: image.height);
    for (var y = 0; y < image.height; y += 1) {
      for (var x = 0; x < image.width; x += 1) {
        final yIndex = y * image.width + x;
        final vuIndex = ySize + (y ~/ 2) * image.width + (x ~/ 2) * 2;
        if (vuIndex + 1 >= plane.bytes.length) {
          return null;
        }
        _setYuvPixel(
          out,
          x,
          y,
          plane.bytes[yIndex],
          plane.bytes[vuIndex + 1],
          plane.bytes[vuIndex],
        );
      }
    }
    return out;
  }

  static img.Image? _twoPlaneNv21ToRgb(CameraImage image) {
    final yPlane = image.planes[0];
    final vuPlane = image.planes[1];
    final yPixelStride = yPlane.bytesPerPixel ?? 1;
    final vuPixelStride = vuPlane.bytesPerPixel ?? 2;
    final out = img.Image(width: image.width, height: image.height);
    for (var y = 0; y < image.height; y += 1) {
      final yRowStart = y * yPlane.bytesPerRow;
      final vuRowStart = (y ~/ 2) * vuPlane.bytesPerRow;
      for (var x = 0; x < image.width; x += 1) {
        final yIndex = yRowStart + x * yPixelStride;
        final vuIndex = vuRowStart + (x ~/ 2) * vuPixelStride;
        if (yIndex >= yPlane.bytes.length ||
            vuIndex + 1 >= vuPlane.bytes.length) {
          return null;
        }
        _setYuvPixel(
          out,
          x,
          y,
          yPlane.bytes[yIndex],
          vuPlane.bytes[vuIndex + 1],
          vuPlane.bytes[vuIndex],
        );
      }
    }
    return out;
  }

  static img.Image? _threePlaneYuv420ToRgb(CameraImage image) {
    final yPlane = image.planes[0];
    final uPlane = image.planes[1];
    final vPlane = image.planes[2];
    final yPixelStride = yPlane.bytesPerPixel ?? 1;
    final uPixelStride = uPlane.bytesPerPixel ?? 1;
    final vPixelStride = vPlane.bytesPerPixel ?? 1;
    final out = img.Image(width: image.width, height: image.height);
    for (var y = 0; y < image.height; y += 1) {
      final yRowStart = y * yPlane.bytesPerRow;
      final uRowStart = (y ~/ 2) * uPlane.bytesPerRow;
      final vRowStart = (y ~/ 2) * vPlane.bytesPerRow;
      for (var x = 0; x < image.width; x += 1) {
        final yIndex = yRowStart + x * yPixelStride;
        final uIndex = uRowStart + (x ~/ 2) * uPixelStride;
        final vIndex = vRowStart + (x ~/ 2) * vPixelStride;
        if (yIndex >= yPlane.bytes.length ||
            uIndex >= uPlane.bytes.length ||
            vIndex >= vPlane.bytes.length) {
          return null;
        }
        _setYuvPixel(
          out,
          x,
          y,
          yPlane.bytes[yIndex],
          uPlane.bytes[uIndex],
          vPlane.bytes[vIndex],
        );
      }
    }
    return out;
  }

  static void _setYuvPixel(
    img.Image out,
    int x,
    int y,
    int yValue,
    int uValue,
    int vValue,
  ) {
    final rgb = _yuvToRgbPacked(yValue, uValue, vValue);
    out.setPixelRgb(x, y, (rgb >> 16) & 0xff, (rgb >> 8) & 0xff, rgb & 0xff);
  }

  static int _yuvToRgbPacked(int yValue, int uValue, int vValue) {
    final yf = yValue.toDouble();
    final uf = uValue.toDouble() - 128.0;
    final vf = vValue.toDouble() - 128.0;
    final r = _clampColor((yf + 1.402 * vf).round());
    final g = _clampColor((yf - 0.344136 * uf - 0.714136 * vf).round());
    final b = _clampColor((yf + 1.772 * uf).round());
    return _packRgb(r, g, b);
  }

  static int _packRgb(int r, int g, int b) {
    return (r << 16) | (g << 8) | b;
  }

  static int _clampColor(int value) {
    if (value < 0) {
      return 0;
    }
    if (value > 255) {
      return 255;
    }
    return value;
  }

  static Uint8List? _encodeTwoPlaneNv21(CameraImage image, int expectedSize) {
    final yPlane = image.planes[0];
    final vuPlane = image.planes[1];
    final output = Uint8List(expectedSize);
    final lumaOffset = _copyLumaPlane(image, yPlane, output, 0);
    if (lumaOffset == null) {
      return null;
    }
    var offset = lumaOffset;

    final chromaHeight = image.height ~/ 2;
    for (var row = 0; row < chromaHeight; row += 1) {
      final rowStart = row * vuPlane.bytesPerRow;
      final rowEnd = rowStart + image.width;
      if (rowEnd > vuPlane.bytes.length ||
          offset + image.width > output.length) {
        return null;
      }
      output.setRange(offset, offset + image.width, vuPlane.bytes, rowStart);
      offset += image.width;
    }
    return offset == expectedSize ? output : null;
  }

  static Uint8List? _encodeThreePlaneYuv420AsNv21(
    CameraImage image,
    int expectedSize,
  ) {
    final yPlane = image.planes[0];
    final uPlane = image.planes[1];
    final vPlane = image.planes[2];
    final output = Uint8List(expectedSize);
    final lumaOffset = _copyLumaPlane(image, yPlane, output, 0);
    if (lumaOffset == null) {
      return null;
    }
    var offset = lumaOffset;

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
        if (uIndex >= uPlane.bytes.length ||
            vIndex >= vPlane.bytes.length ||
            offset + 1 >= output.length) {
          return null;
        }
        output[offset] = vPlane.bytes[vIndex];
        output[offset + 1] = uPlane.bytes[uIndex];
        offset += 2;
      }
    }

    return offset == expectedSize ? output : null;
  }

  static int? _copyLumaPlane(
    CameraImage image,
    Plane plane,
    Uint8List output,
    int offset,
  ) {
    final pixelStride = plane.bytesPerPixel ?? 1;
    for (var row = 0; row < image.height; row += 1) {
      final rowStart = row * plane.bytesPerRow;
      if (pixelStride == 1) {
        final rowEnd = rowStart + image.width;
        if (rowEnd > plane.bytes.length ||
            offset + image.width > output.length) {
          return null;
        }
        output.setRange(offset, offset + image.width, plane.bytes, rowStart);
        offset += image.width;
        continue;
      }
      for (var col = 0; col < image.width; col += 1) {
        final index = rowStart + col * pixelStride;
        if (index >= plane.bytes.length || offset >= output.length) {
          return null;
        }
        output[offset] = plane.bytes[index];
        offset += 1;
      }
    }
    return offset;
  }
}
