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
  static const List<List<int>> _templateSkeletonEdges = <List<int>>[
    <int>[11, 12],
    <int>[11, 13],
    <int>[13, 15],
    <int>[12, 14],
    <int>[14, 16],
    <int>[11, 23],
    <int>[12, 24],
    <int>[23, 24],
    <int>[23, 25],
    <int>[25, 27],
    <int>[24, 26],
    <int>[26, 28],
  ];
  static const Map<String, String> _legacyPoseAliases = <String, String>{
    'head': 'head',
    'nose': 'head',
    'left_shoulder': 'left_shoulder',
    'right_shoulder': 'right_shoulder',
    'left_hip': 'left_hip',
    'right_hip': 'right_hip',
    'left_knee': 'left_knee',
    'right_knee': 'right_knee',
    'left_ankle': 'left_ankle',
    'right_ankle': 'right_ankle',
  };
  static const List<List<String>> _legacyTemplateEdges = <List<String>>[
    <String>['head', 'left_shoulder'],
    <String>['head', 'right_shoulder'],
    <String>['left_shoulder', 'right_shoulder'],
    <String>['left_shoulder', 'left_hip'],
    <String>['right_shoulder', 'right_hip'],
    <String>['left_hip', 'right_hip'],
    <String>['left_hip', 'left_knee'],
    <String>['right_hip', 'right_knee'],
    <String>['left_knee', 'left_ankle'],
    <String>['right_knee', 'right_ankle'],
  ];

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

  bool get hasBodyBox => bodyBox.width > 0 && bodyBox.height > 0;

  bool get hasSkeleton => skeletonPoints.length >= 15;

  bool get hasTemplate => templateSegments.isNotEmpty;

  factory OverlayScene.empty() {
    return const OverlayScene(
      bodyBox: NormalizedRect(left: 0, top: 0, width: 0, height: 0),
      skeletonPoints: <NormalizedPoint>[],
      templateSegments: <OverlaySegment>[],
    );
  }

  factory OverlayScene.fromTargetBox(NormalizedRect bodyBox) {
    final centerX = bodyBox.left + bodyBox.width / 2;
    final top = bodyBox.top;
    final bottom = bodyBox.top + bodyBox.height;
    final shoulderY = top + bodyBox.height * 0.18;
    final elbowY = top + bodyBox.height * 0.34;
    final wristY = top + bodyBox.height * 0.46;
    final hipY = top + bodyBox.height * 0.52;
    final kneeY = top + bodyBox.height * 0.76;
    final ankleY = top + bodyBox.height * 0.92;
    final shoulderOffset = bodyBox.width * 0.18;
    final elbowOffset = bodyBox.width * 0.28;
    final wristOffset = bodyBox.width * 0.34;
    final hipOffset = bodyBox.width * 0.16;
    final kneeOffset = bodyBox.width * 0.14;
    final ankleOffset = bodyBox.width * 0.12;

    return OverlayScene(
      bodyBox: bodyBox,
      skeletonPoints: <NormalizedPoint>[
        NormalizedPoint(centerX, top + bodyBox.height * 0.05),
        NormalizedPoint(centerX - shoulderOffset, shoulderY),
        NormalizedPoint(centerX + shoulderOffset, shoulderY),
        NormalizedPoint(centerX - elbowOffset, elbowY),
        NormalizedPoint(centerX + elbowOffset, elbowY),
        NormalizedPoint(centerX - wristOffset, wristY),
        NormalizedPoint(centerX + wristOffset, wristY),
        NormalizedPoint(centerX - hipOffset, hipY),
        NormalizedPoint(centerX + hipOffset, hipY),
        NormalizedPoint(centerX - kneeOffset, kneeY),
        NormalizedPoint(centerX + kneeOffset, kneeY),
        NormalizedPoint(centerX - ankleOffset, ankleY),
        NormalizedPoint(centerX + ankleOffset, ankleY),
        NormalizedPoint(centerX - ankleOffset * 1.15, bottom),
        NormalizedPoint(centerX + ankleOffset * 1.15, bottom),
      ],
      templateSegments: const <OverlaySegment>[],
    );
  }

  factory OverlayScene.fromTemplateData(Map<String, dynamic> templateData) {
    final bboxNorm = templateData['bbox_norm'];
    final templateSegments = <OverlaySegment>[];
    NormalizedRect? bodyBox;
    if (bboxNorm is List<dynamic> && bboxNorm.length == 4) {
      final left = _toDouble(bboxNorm[0]);
      final top = _toDouble(bboxNorm[1]);
      final width = _toDouble(bboxNorm[2]);
      final height = _toDouble(bboxNorm[3]);
      if (left != null && top != null && width != null && height != null) {
        bodyBox = NormalizedRect(
          left: _clamp01(left),
          top: _clamp01(top),
          width: _clamp01(width),
          height: _clamp01(height),
        );
        if (bodyBox.width > 0 && bodyBox.height > 0) {
          templateSegments.addAll(_templateSegmentsFromRect(bodyBox));
        }
      }
    }

    final imagePoints = _templatePointsInImageSpace(
      templateData,
      bodyBox: bodyBox,
    );
    if (imagePoints.isNotEmpty) {
      templateSegments.addAll(_templateSegmentsFromSkeleton(imagePoints));
    } else {
      templateSegments.addAll(_legacyTemplateSegments(templateData['pose_points']));
    }

    return OverlayScene(
      bodyBox: const NormalizedRect(left: 0, top: 0, width: 0, height: 0),
      skeletonPoints: const <NormalizedPoint>[],
      templateSegments: templateSegments,
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

  static List<OverlaySegment> _templateSegmentsFromRect(NormalizedRect rect) {
    final leftTop = NormalizedPoint(rect.left, rect.top);
    final rightTop = NormalizedPoint(rect.left + rect.width, rect.top);
    final leftBottom = NormalizedPoint(rect.left, rect.top + rect.height);
    final rightBottom = NormalizedPoint(
      rect.left + rect.width,
      rect.top + rect.height,
    );
    return <OverlaySegment>[
      OverlaySegment(leftTop, rightTop),
      OverlaySegment(leftTop, leftBottom),
      OverlaySegment(rightTop, rightBottom),
      OverlaySegment(leftBottom, rightBottom),
    ];
  }

  static List<OverlaySegment> _templateSegmentsFromSkeleton(
    Map<int, NormalizedPoint> points,
  ) {
    final segments = <OverlaySegment>[];
    for (final edge in _templateSkeletonEdges) {
      final start = points[edge[0]];
      final end = points[edge[1]];
      if (start == null || end == null) {
        continue;
      }
      segments.add(OverlaySegment(start, end));
    }
    return segments;
  }

  static Map<int, NormalizedPoint> _templatePointsInImageSpace(
    Map<String, dynamic> templateData, {
    required NormalizedRect? bodyBox,
  }) {
    final imagePoints = _readTemplatePointMap(templateData['pose_points_image']);
    if (imagePoints.isNotEmpty) {
      return imagePoints;
    }

    final bboxPoints = _readTemplatePointMap(templateData['pose_points_bbox']);
    if (bboxPoints.isNotEmpty && bodyBox != null) {
      return bboxPoints.map((int key, NormalizedPoint point) {
        return MapEntry<int, NormalizedPoint>(
          key,
          NormalizedPoint(
            bodyBox.left + bodyBox.width * point.x,
            bodyBox.top + bodyBox.height * point.y,
          ),
        );
      });
    }

    return <int, NormalizedPoint>{};
  }

  static List<OverlaySegment> _legacyTemplateSegments(Object? raw) {
    if (raw is! Map) {
      return const <OverlaySegment>[];
    }

    final points = <String, NormalizedPoint>{};
    for (final MapEntry<dynamic, dynamic> entry in raw.entries) {
      final alias = _legacyPoseAliases['${entry.key}'];
      final value = entry.value;
      if (alias == null || value is! List || value.length < 2) {
        continue;
      }
      final x = _toDouble(value[0]);
      final y = _toDouble(value[1]);
      if (x == null || y == null) {
        continue;
      }
      points[alias] = NormalizedPoint(_clamp01(x), _clamp01(y));
    }

    final segments = <OverlaySegment>[];
    for (final edge in _legacyTemplateEdges) {
      final start = points[edge[0]];
      final end = points[edge[1]];
      if (start == null || end == null) {
        continue;
      }
      segments.add(OverlaySegment(start, end));
    }
    return segments;
  }

  static Map<int, NormalizedPoint> _readTemplatePointMap(Object? raw) {
    if (raw is! Map) {
      return <int, NormalizedPoint>{};
    }

    final result = <int, NormalizedPoint>{};
    for (final MapEntry<dynamic, dynamic> entry in raw.entries) {
      final index = int.tryParse('${entry.key}');
      final value = entry.value;
      if (index == null || value is! List || value.length < 2) {
        continue;
      }
      final x = _toDouble(value[0]);
      final y = _toDouble(value[1]);
      if (x == null || y == null) {
        continue;
      }
      result[index] = NormalizedPoint(_clamp01(x), _clamp01(y));
    }
    return result;
  }

  static double? _toDouble(Object? value) {
    if (value is num) {
      return value.toDouble();
    }
    return double.tryParse('$value');
  }

  static double _clamp01(double value) => value.clamp(0.0, 1.0);
}
