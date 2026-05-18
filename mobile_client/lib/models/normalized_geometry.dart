import 'dart:ui';

class NormalizedPoint {
  const NormalizedPoint(this.x, this.y);

  final double x;
  final double y;
}

class NormalizedRect {
  const NormalizedRect({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  final double left;
  final double top;
  final double width;
  final double height;
}

class PreviewTransform {
  const PreviewTransform({required this.viewportSize, this.mirrorX = false});

  final Size viewportSize;
  final bool mirrorX;

  Offset pointToViewport(NormalizedPoint point) {
    final normalizedX = _clamp01(mirrorX ? 1 - point.x : point.x);
    final normalizedY = _clamp01(point.y);
    return Offset(
      normalizedX * viewportSize.width,
      normalizedY * viewportSize.height,
    );
  }

  Rect rectToViewport(NormalizedRect rect) {
    final normalizedLeft = mirrorX ? 1 - rect.left - rect.width : rect.left;
    final normalizedRight = mirrorX ? 1 - rect.left : rect.left + rect.width;
    final left = _clamp01(normalizedLeft) * viewportSize.width;
    final top = _clamp01(rect.top) * viewportSize.height;
    final right = _clamp01(normalizedRight) * viewportSize.width;
    final bottom = _clamp01(rect.top + rect.height) * viewportSize.height;
    return Rect.fromLTRB(
      left < right ? left : right,
      top < bottom ? top : bottom,
      right > left ? right : left,
      bottom > top ? bottom : top,
    );
  }

  double _clamp01(double value) {
    if (!value.isFinite) {
      return 0.0;
    }
    return value.clamp(0.0, 1.0);
  }
}
