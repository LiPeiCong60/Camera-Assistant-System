import '../../models/normalized_geometry.dart';

class OverlaySettings {
  const OverlaySettings({
    this.showBodyBox = true,
    this.showSkeleton = true,
    this.showTemplate = true,
  });

  final bool showBodyBox;
  final bool showSkeleton;
  final bool showTemplate;

  OverlaySettings copyWith({
    bool? showBodyBox,
    bool? showSkeleton,
    bool? showTemplate,
  }) {
    return OverlaySettings(
      showBodyBox: showBodyBox ?? this.showBodyBox,
      showSkeleton: showSkeleton ?? this.showSkeleton,
      showTemplate: showTemplate ?? this.showTemplate,
    );
  }
}

class OverlaySegment {
  const OverlaySegment(this.start, this.end);

  final NormalizedPoint start;
  final NormalizedPoint end;
}

class OverlayScene {
  const OverlayScene({
    required this.bodyBox,
    required this.skeletonPoints,
    required this.templateSegments,
  });

  final NormalizedRect bodyBox;
  final List<NormalizedPoint> skeletonPoints;
  final List<OverlaySegment> templateSegments;

  OverlayScene copyWith({
    NormalizedRect? bodyBox,
    List<NormalizedPoint>? skeletonPoints,
    List<OverlaySegment>? templateSegments,
  }) {
    return OverlayScene(
      bodyBox: bodyBox ?? this.bodyBox,
      skeletonPoints: skeletonPoints ?? this.skeletonPoints,
      templateSegments: templateSegments ?? this.templateSegments,
    );
  }

  factory OverlayScene.fromTargetBox(NormalizedRect bodyBox) {
    final centerX = bodyBox.left + bodyBox.width / 2;
    final top = bodyBox.top;
    final bottom = bodyBox.top + bodyBox.height;
    final shoulderY = top + bodyBox.height * 0.18;
    final elbowY = top + bodyBox.height * 0.34;
    final hipY = top + bodyBox.height * 0.52;
    final kneeY = top + bodyBox.height * 0.76;
    final shoulderOffset = bodyBox.width * 0.18;
    final elbowOffset = bodyBox.width * 0.28;
    final hipOffset = bodyBox.width * 0.16;
    final kneeOffset = bodyBox.width * 0.14;

    return OverlayScene(
      bodyBox: bodyBox,
      skeletonPoints: <NormalizedPoint>[
        NormalizedPoint(centerX, top + bodyBox.height * 0.05),
        NormalizedPoint(centerX - shoulderOffset, shoulderY),
        NormalizedPoint(centerX + shoulderOffset, shoulderY),
        NormalizedPoint(centerX - elbowOffset, elbowY),
        NormalizedPoint(centerX + elbowOffset, elbowY),
        NormalizedPoint(centerX - hipOffset, hipY),
        NormalizedPoint(centerX + hipOffset, hipY),
        NormalizedPoint(centerX - kneeOffset, kneeY),
        NormalizedPoint(centerX + kneeOffset, kneeY),
        NormalizedPoint(centerX - kneeOffset * 1.1, bottom),
        NormalizedPoint(centerX + kneeOffset * 1.1, bottom),
      ],
      templateSegments: <OverlaySegment>[
        OverlaySegment(
          NormalizedPoint(bodyBox.left, bodyBox.top),
          NormalizedPoint(bodyBox.left + bodyBox.width, bodyBox.top),
        ),
        OverlaySegment(
          NormalizedPoint(bodyBox.left, bodyBox.top),
          NormalizedPoint(bodyBox.left, bodyBox.top + bodyBox.height),
        ),
        OverlaySegment(
          NormalizedPoint(bodyBox.left + bodyBox.width, bodyBox.top),
          NormalizedPoint(
            bodyBox.left + bodyBox.width,
            bodyBox.top + bodyBox.height,
          ),
        ),
        OverlaySegment(
          NormalizedPoint(bodyBox.left, bodyBox.top + bodyBox.height),
          NormalizedPoint(
            bodyBox.left + bodyBox.width,
            bodyBox.top + bodyBox.height,
          ),
        ),
        OverlaySegment(
          NormalizedPoint(bodyBox.left + bodyBox.width * 0.18, shoulderY),
          NormalizedPoint(bodyBox.left + bodyBox.width * 0.82, shoulderY),
        ),
      ],
    );
  }

  factory OverlayScene.fromTemplateData(Map<String, dynamic> templateData) {
    final bboxNorm = templateData['bbox_norm'];
    final posePoints = templateData['pose_points'];

    final bodyBox = bboxNorm is List<dynamic> && bboxNorm.length == 4
        ? NormalizedRect(
            left: (bboxNorm[0] as num).toDouble(),
            top: (bboxNorm[1] as num).toDouble(),
            width: (bboxNorm[2] as num).toDouble(),
            height: (bboxNorm[3] as num).toDouble(),
          )
        : const NormalizedRect(
            left: 0.34,
            top: 0.14,
            width: 0.32,
            height: 0.68,
          );

    final skeletonPoints = <NormalizedPoint>[];
    if (posePoints is Map<String, dynamic>) {
      final sortedKeys = posePoints.keys.toList()..sort();
      for (final key in sortedKeys) {
        final value = posePoints[key];
        if (value is List<dynamic> && value.length >= 2) {
          skeletonPoints.add(
            NormalizedPoint(
              (value[0] as num).toDouble(),
              (value[1] as num).toDouble(),
            ),
          );
        }
      }
    }

    final baseScene = OverlayScene.fromTargetBox(bodyBox);
    return baseScene.copyWith(
      skeletonPoints: skeletonPoints.isEmpty
          ? baseScene.skeletonPoints
          : skeletonPoints,
    );
  }

  factory OverlayScene.previewSample() {
    return OverlayScene(
      bodyBox: const NormalizedRect(
        left: 0.36,
        top: 0.16,
        width: 0.28,
        height: 0.6,
      ),
      skeletonPoints: const <NormalizedPoint>[
        NormalizedPoint(0.5, 0.18),
        NormalizedPoint(0.47, 0.26),
        NormalizedPoint(0.53, 0.26),
        NormalizedPoint(0.42, 0.34),
        NormalizedPoint(0.58, 0.34),
        NormalizedPoint(0.46, 0.42),
        NormalizedPoint(0.54, 0.42),
        NormalizedPoint(0.44, 0.56),
        NormalizedPoint(0.56, 0.56),
        NormalizedPoint(0.42, 0.72),
        NormalizedPoint(0.58, 0.72),
      ],
      templateSegments: const <OverlaySegment>[
        OverlaySegment(
          NormalizedPoint(0.31, 0.11),
          NormalizedPoint(0.69, 0.11),
        ),
        OverlaySegment(
          NormalizedPoint(0.31, 0.11),
          NormalizedPoint(0.31, 0.82),
        ),
        OverlaySegment(
          NormalizedPoint(0.69, 0.11),
          NormalizedPoint(0.69, 0.82),
        ),
        OverlaySegment(
          NormalizedPoint(0.31, 0.82),
          NormalizedPoint(0.69, 0.82),
        ),
        OverlaySegment(
          NormalizedPoint(0.39, 0.32),
          NormalizedPoint(0.61, 0.32),
        ),
      ],
    );
  }
}
