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
    final staticTransform = PreviewTransform(viewportSize: size);
    final dynamicTransform = PreviewTransform(
      viewportSize: size,
      mirrorX: mirrorDynamicOverlays,
    );
    if (settings.showTemplateBox) {
      _paintTemplateBox(canvas, staticTransform);
    }
    if (settings.showTemplate) {
      _paintTemplateLines(canvas, staticTransform);
    }
    if (settings.showBodyBox) {
      _paintBodyBox(canvas, dynamicTransform);
    }
    if (settings.showSkeleton) {
      _paintSkeleton(canvas, dynamicTransform);
    }
  }

  void _paintTemplateBox(Canvas canvas, PreviewTransform transform) {
    if (scene.hasTemplateBox) {
      final boxRect = transform.rectToViewport(scene.templateBox);
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

  void _paintTemplateLines(Canvas canvas, PreviewTransform transform) {
    final templateLinePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = const Color(0xFFD4A017);

    for (final segment in scene.templateSegments) {
      canvas.drawLine(
        transform.pointToViewport(segment.start),
        transform.pointToViewport(segment.end),
        templateLinePaint,
      );
    }

    if (scene.hasTemplate) {
      final jointPaint = Paint()
        ..style = PaintingStyle.fill
        ..color = const Color(0xFFE0A458);
      for (final segment in scene.templateSegments) {
        canvas.drawCircle(
          transform.pointToViewport(segment.start),
          3.2,
          jointPaint,
        );
        canvas.drawCircle(
          transform.pointToViewport(segment.end),
          3.2,
          jointPaint,
        );
      }
    }
  }

  void _paintBodyBox(Canvas canvas, PreviewTransform transform) {
    if (!scene.hasBodyBox) {
      return;
    }
    final rectPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.6
      ..color = const Color(0xFF00D084);

    final rect = transform.rectToViewport(scene.bodyBox);
    if (rect.width <= 0 || rect.height <= 0) {
      return;
    }
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(24)),
      rectPaint,
    );
  }

  void _paintSkeleton(Canvas canvas, PreviewTransform transform) {
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
        transform.pointToViewport(start),
        transform.pointToViewport(end),
        segmentPaint,
      );
    }
  }

  bool _isDrawablePoint(NormalizedPoint point) {
    return point.x.isFinite && point.y.isFinite;
  }

  @override
  bool shouldRepaint(covariant CameraOverlayPainter oldDelegate) {
    return oldDelegate.scene != scene ||
        oldDelegate.settings != settings ||
        oldDelegate.mirrorDynamicOverlays != mirrorDynamicOverlays;
  }
}
