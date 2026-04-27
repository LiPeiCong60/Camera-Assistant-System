import 'package:flutter/material.dart';

import '../../models/normalized_geometry.dart';
import 'overlay_scene.dart';

class CameraOverlayPainter extends CustomPainter {
  static const List<List<int>> _liveSkeletonEdges = <List<int>>[
    <int>[0, 1],
    <int>[0, 2],
    <int>[1, 2],
    <int>[1, 3],
    <int>[3, 5],
    <int>[2, 4],
    <int>[4, 6],
    <int>[1, 7],
    <int>[2, 8],
    <int>[7, 8],
    <int>[7, 9],
    <int>[9, 11],
    <int>[8, 10],
    <int>[10, 12],
  ];

  const CameraOverlayPainter({
    required this.scene,
    required this.settings,
    this.mirrorDynamicOverlays = false,
  });

  final OverlayScene scene;
  final OverlaySettings settings;
  final bool mirrorDynamicOverlays;

  @override
  void paint(Canvas canvas, Size size) {
    if (settings.showTemplateBox) {
      _paintTemplateBox(canvas, size);
    }
    if (settings.showTemplate) {
      _paintTemplateLines(canvas, size);
    }
    if (settings.showBodyBox) {
      _paintBodyBox(canvas, size);
    }
    if (settings.showSkeleton) {
      _paintSkeleton(canvas, size);
    }
  }

  void _paintTemplateBox(Canvas canvas, Size size) {
    if (scene.hasTemplateBox) {
      final boxRect = _rectFromNormalizedRect(scene.templateBox, size);
      if (boxRect.width > 0 && boxRect.height > 0) {
        final boxPaint = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.4
          ..color = const Color(0xFFD4A017);
        canvas.drawRRect(
          RRect.fromRectAndRadius(boxRect, const Radius.circular(22)),
          boxPaint,
        );
      }
    }
  }

  void _paintTemplateLines(Canvas canvas, Size size) {
    final templateLinePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = const Color(0xFFD4A017);

    for (final segment in scene.templateSegments) {
      canvas.drawLine(
        _offsetFromPoint(segment.start, size),
        _offsetFromPoint(segment.end, size),
        templateLinePaint,
      );
    }

    if (scene.hasTemplate) {
      final jointPaint = Paint()
        ..style = PaintingStyle.fill
        ..color = const Color(0xFFE0A458);
      for (final segment in scene.templateSegments) {
        canvas.drawCircle(
          _offsetFromPoint(segment.start, size),
          3.2,
          jointPaint,
        );
        canvas.drawCircle(_offsetFromPoint(segment.end, size), 3.2, jointPaint);
      }
    }
  }

  Rect _rectFromNormalizedRect(NormalizedRect rect, Size size) {
    final left = _clamp01(rect.left) * size.width;
    final top = _clamp01(rect.top) * size.height;
    final right = _clamp01(rect.left + rect.width) * size.width;
    final bottom = _clamp01(rect.top + rect.height) * size.height;
    return Rect.fromLTRB(
      left < right ? left : right,
      top < bottom ? top : bottom,
      right > left ? right : left,
      bottom > top ? bottom : top,
    );
  }

  void _paintBodyBox(Canvas canvas, Size size) {
    if (!scene.hasBodyBox) {
      return;
    }
    final rectPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.6
      ..color = const Color(0xFF00D084);

    final left = _resolveBodyBoxLeft(size);
    final top = _clamp01(scene.bodyBox.top) * size.height;
    final normalizedRight = mirrorDynamicOverlays
        ? 1 - scene.bodyBox.left
        : scene.bodyBox.left + scene.bodyBox.width;
    final right = _clamp01(normalizedRight) * size.width;
    final bottom =
        _clamp01(scene.bodyBox.top + scene.bodyBox.height) * size.height;
    final rect = Rect.fromLTRB(left, top, right, bottom);
    if (rect.width <= 0 || rect.height <= 0) {
      return;
    }
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(24)),
      rectPaint,
    );
  }

  void _paintSkeleton(Canvas canvas, Size size) {
    if (!scene.hasSkeleton) {
      return;
    }

    final segmentPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = const Color(0xFF42C6FF).withValues(alpha: 0.92);

    for (final edge in _liveSkeletonEdges) {
      if (edge[0] >= scene.skeletonPoints.length ||
          edge[1] >= scene.skeletonPoints.length) {
        continue;
      }
      final start = scene.skeletonPoints[edge[0]];
      final end = scene.skeletonPoints[edge[1]];
      if (!_isDrawablePoint(start) || !_isDrawablePoint(end)) {
        continue;
      }
      canvas.drawLine(
        _offsetFromPoint(start, size, mirrored: mirrorDynamicOverlays),
        _offsetFromPoint(end, size, mirrored: mirrorDynamicOverlays),
        segmentPaint,
      );
    }
  }

  bool _isDrawablePoint(NormalizedPoint point) {
    return point.x.isFinite && point.y.isFinite;
  }

  double _resolveBodyBoxLeft(Size size) {
    final normalizedLeft = mirrorDynamicOverlays
        ? 1 - scene.bodyBox.left - scene.bodyBox.width
        : scene.bodyBox.left;
    return _clamp01(normalizedLeft) * size.width;
  }

  Offset _offsetFromPoint(
    NormalizedPoint point,
    Size size, {
    bool mirrored = false,
  }) {
    final normalizedX = _clamp01(mirrored ? 1 - point.x : point.x);
    final normalizedY = _clamp01(point.y);
    return Offset(normalizedX * size.width, normalizedY * size.height);
  }

  double _clamp01(double value) => value.clamp(0.0, 1.0);

  @override
  bool shouldRepaint(covariant CameraOverlayPainter oldDelegate) {
    return oldDelegate.scene != scene ||
        oldDelegate.settings != settings ||
        oldDelegate.mirrorDynamicOverlays != mirrorDynamicOverlays;
  }
}
