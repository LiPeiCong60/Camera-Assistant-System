import 'package:flutter/material.dart';

import '../../models/normalized_geometry.dart';
import 'overlay_scene.dart';

class CameraOverlayPainter extends CustomPainter {
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
    if (settings.showTemplate) {
      _paintTemplate(canvas, size);
    }
    if (settings.showBodyBox) {
      _paintBodyBox(canvas, size);
    }
    if (settings.showSkeleton) {
      _paintSkeleton(canvas, size);
    }
  }

  void _paintTemplate(Canvas canvas, Size size) {
    final templatePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = const Color(0xFFD4A017);

    for (final segment in scene.templateSegments) {
      canvas.drawLine(
        _offsetFromPoint(segment.start, size),
        _offsetFromPoint(segment.end, size),
        templatePaint,
      );
    }
  }

  void _paintBodyBox(Canvas canvas, Size size) {
    final rectPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.6
      ..color = const Color(0xFF00D084);

    final rect = Rect.fromLTWH(
      _resolveBodyBoxLeft(size),
      scene.bodyBox.top * size.height,
      scene.bodyBox.width * size.width,
      scene.bodyBox.height * size.height,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(24)),
      rectPaint,
    );
  }

  void _paintSkeleton(Canvas canvas, Size size) {
    if (scene.skeletonPoints.length < 11) {
      return;
    }

    final segmentPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFF42C6FF);
    final pointPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = const Color(0xFF42C6FF);

    final points = scene.skeletonPoints
        .map(
          (point) =>
              _offsetFromPoint(point, size, mirrored: mirrorDynamicOverlays),
        )
        .toList(growable: false);
    const skeletonEdges = <List<int>>[
      <int>[0, 1],
      <int>[0, 2],
      <int>[1, 3],
      <int>[2, 4],
      <int>[1, 5],
      <int>[2, 6],
      <int>[5, 6],
      <int>[5, 7],
      <int>[6, 8],
      <int>[7, 9],
      <int>[8, 10],
    ];

    for (final edge in skeletonEdges) {
      canvas.drawLine(points[edge[0]], points[edge[1]], segmentPaint);
    }
    for (final point in points) {
      canvas.drawCircle(point, 4.5, pointPaint);
    }
  }

  double _resolveBodyBoxLeft(Size size) {
    final normalizedLeft = mirrorDynamicOverlays
        ? 1 - scene.bodyBox.left - scene.bodyBox.width
        : scene.bodyBox.left;
    return normalizedLeft * size.width;
  }

  Offset _offsetFromPoint(
    NormalizedPoint point,
    Size size, {
    bool mirrored = false,
  }) {
    final normalizedX = mirrored ? 1 - point.x : point.x;
    return Offset(normalizedX * size.width, point.y * size.height);
  }

  @override
  bool shouldRepaint(covariant CameraOverlayPainter oldDelegate) {
    return oldDelegate.scene != scene ||
        oldDelegate.settings != settings ||
        oldDelegate.mirrorDynamicOverlays != mirrorDynamicOverlays;
  }
}
