import '../../models/normalized_geometry.dart';

class OverlaySettings {
  const OverlaySettings({
    this.showBodyBox = true,
    this.showSkeleton = true,
    this.showTemplateBox = true,
    this.showTemplate = true,
  });

  final bool showBodyBox;
  final bool showSkeleton;
  final bool showTemplateBox;
  final bool showTemplate;

  OverlaySettings copyWith({
    bool? showBodyBox,
    bool? showSkeleton,
    bool? showTemplateBox,
    bool? showTemplate,
  }) {
    return OverlaySettings(
      showBodyBox: showBodyBox ?? this.showBodyBox,
      showSkeleton: showSkeleton ?? this.showSkeleton,
      showTemplateBox: showTemplateBox ?? this.showTemplateBox,
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
    <int>[7, 0],
    <int>[0, 8],
    <int>[0, 11],
    <int>[0, 12],
    <int>[9, 10],
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
    required this.templateBox,
    required this.templateSegments,
    required this.templateHeadBox,
  });

  final NormalizedRect bodyBox;
  final List<NormalizedPoint> skeletonPoints;
  final NormalizedRect templateBox;
  final List<OverlaySegment> templateSegments;
  final NormalizedRect templateHeadBox;

  OverlayScene copyWith({
    NormalizedRect? bodyBox,
    List<NormalizedPoint>? skeletonPoints,
    NormalizedRect? templateBox,
    List<OverlaySegment>? templateSegments,
    NormalizedRect? templateHeadBox,
  }) {
    return OverlayScene(
      bodyBox: bodyBox ?? this.bodyBox,
      skeletonPoints: skeletonPoints ?? this.skeletonPoints,
      templateBox: templateBox ?? this.templateBox,
      templateSegments: templateSegments ?? this.templateSegments,
      templateHeadBox: templateHeadBox ?? this.templateHeadBox,
    );
  }

  bool get hasBodyBox => bodyBox.width > 0 && bodyBox.height > 0;

  bool get hasSkeleton => skeletonPoints.length >= 15;

  bool get hasTemplate => templateSegments.isNotEmpty;

  bool get hasTemplateBox => templateBox.width > 0 && templateBox.height > 0;

  bool get hasTemplateHeadBox =>
      templateHeadBox.width > 0 && templateHeadBox.height > 0;

  factory OverlayScene.empty() {
    return const OverlayScene(
      bodyBox: NormalizedRect(left: 0, top: 0, width: 0, height: 0),
      skeletonPoints: <NormalizedPoint>[],
      templateBox: NormalizedRect(left: 0, top: 0, width: 0, height: 0),
      templateSegments: <OverlaySegment>[],
      templateHeadBox: NormalizedRect(left: 0, top: 0, width: 0, height: 0),
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
      templateBox: const NormalizedRect(left: 0, top: 0, width: 0, height: 0),
      templateSegments: const <OverlaySegment>[],
      templateHeadBox: NormalizedRect(
        left: _clamp01(centerX - bodyBox.width * 0.16),
        top: _clamp01(top + bodyBox.height * 0.01),
        width: _clampDimension(
          bodyBox.width * 0.32,
          centerX - bodyBox.width * 0.16,
        ),
        height: _clampDimension(
          bodyBox.height * 0.16,
          top + bodyBox.height * 0.01,
        ),
      ),
    );
  }

  factory OverlayScene.fromTemplateData(Map<String, dynamic> templateData) {
    final bboxNorm = templateData['bbox_norm'];
    final templateSegments = <OverlaySegment>[];
    NormalizedRect? templateBox;
    if (bboxNorm is List<dynamic> && bboxNorm.length == 4) {
      final left = _toDouble(bboxNorm[0]);
      final top = _toDouble(bboxNorm[1]);
      final width = _toDouble(bboxNorm[2]);
      final height = _toDouble(bboxNorm[3]);
      if (left != null && top != null && width != null && height != null) {
        templateBox = NormalizedRect(
          left: _clamp01(left),
          top: _clamp01(top),
          width: _clamp01(width),
          height: _clamp01(height),
        );
      }
    }

    final imagePoints = _templatePointsInImageSpace(
      templateData,
      bodyBox: templateBox,
    );
    if (imagePoints.isNotEmpty) {
      templateSegments.addAll(_templateSegmentsFromSkeleton(imagePoints));
    } else {
      templateSegments.addAll(
        _legacyTemplateSegments(templateData['pose_points']),
      );
    }
    final templateHeadBox = _templateHeadBox(
      templateData,
      imagePoints: imagePoints,
      bodyBox: templateBox,
    );
    if (templateHeadBox != null) {
      templateSegments.addAll(
        _templateHeadGuideSegments(templateHeadBox, imagePoints: imagePoints),
      );
    }

    return OverlayScene(
      bodyBox: const NormalizedRect(left: 0, top: 0, width: 0, height: 0),
      skeletonPoints: const <NormalizedPoint>[],
      templateBox:
          templateBox ??
          const NormalizedRect(left: 0, top: 0, width: 0, height: 0),
      templateSegments: templateSegments,
      templateHeadBox:
          templateHeadBox ??
          const NormalizedRect(left: 0, top: 0, width: 0, height: 0),
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
      templateBox: const NormalizedRect(
        left: 0.31,
        top: 0.11,
        width: 0.38,
        height: 0.71,
      ),
      templateSegments: const <OverlaySegment>[
        OverlaySegment(
          NormalizedPoint(0.45, 0.18),
          NormalizedPoint(0.55, 0.18),
        ),
        OverlaySegment(
          NormalizedPoint(0.50, 0.18),
          NormalizedPoint(0.50, 0.27),
        ),
        OverlaySegment(
          NormalizedPoint(0.39, 0.32),
          NormalizedPoint(0.61, 0.32),
        ),
      ],
      templateHeadBox: const NormalizedRect(
        left: 0.43,
        top: 0.12,
        width: 0.14,
        height: 0.12,
      ),
    );
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

  static List<OverlaySegment> _templateHeadGuideSegments(
    NormalizedRect headBox, {
    required Map<int, NormalizedPoint> imagePoints,
  }) {
    final hasFacePoints = <int>[
      0,
      1,
      2,
      3,
      4,
      5,
      6,
      7,
      8,
      9,
      10,
    ].any(imagePoints.containsKey);
    if (hasFacePoints) {
      return const <OverlaySegment>[];
    }

    final center = NormalizedPoint(
      headBox.left + headBox.width * 0.5,
      headBox.top + headBox.height * 0.5,
    );
    final horizontalStart = NormalizedPoint(
      _clamp01(center.x - headBox.width * 0.28),
      center.y,
    );
    final horizontalEnd = NormalizedPoint(
      _clamp01(center.x + headBox.width * 0.28),
      center.y,
    );
    final verticalEnd = NormalizedPoint(
      center.x,
      _clamp01(center.y + headBox.height * 0.42),
    );
    final segments = <OverlaySegment>[
      OverlaySegment(horizontalStart, horizontalEnd),
      OverlaySegment(center, verticalEnd),
    ];

    final leftShoulder = imagePoints[11];
    final rightShoulder = imagePoints[12];
    if (leftShoulder != null && rightShoulder != null) {
      segments.add(OverlaySegment(center, leftShoulder));
      segments.add(OverlaySegment(center, rightShoulder));
    }
    return segments;
  }

  static Map<int, NormalizedPoint> _templatePointsInImageSpace(
    Map<String, dynamic> templateData, {
    required NormalizedRect? bodyBox,
  }) {
    final imagePoints = _readTemplatePointMap(
      templateData['pose_points_image'],
    );
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

  static NormalizedRect? _templateHeadBox(
    Map<String, dynamic> templateData, {
    required Map<int, NormalizedPoint> imagePoints,
    required NormalizedRect? bodyBox,
  }) {
    final explicitHeadBox = _rectFromList(templateData['head_bbox_norm']);
    if (explicitHeadBox != null) {
      return explicitHeadBox;
    }

    final headAnchorX = _toDouble(templateData['head_anchor_norm_x']);
    final headAnchorY = _toDouble(templateData['head_anchor_norm_y']);
    final faceAnchorX = _toDouble(templateData['face_anchor_norm_x']);
    final faceAnchorY = _toDouble(templateData['face_anchor_norm_y']);
    final anchorX = headAnchorX ?? faceAnchorX;
    final anchorY = headAnchorY ?? faceAnchorY;
    if (anchorX != null && anchorY != null) {
      final baseWidth = bodyBox == null || bodyBox.width <= 0
          ? 0.18
          : bodyBox.width * 0.42;
      final width = _clampRange(baseWidth, 0.10, 0.24);
      final height = _clampRange(width * 1.12, 0.11, 0.26);
      return _rectAroundPoint(NormalizedPoint(anchorX, anchorY), width, height);
    }

    final facePoints = <NormalizedPoint>[
      for (final index in <int>[0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10])
        if (imagePoints[index] != null) imagePoints[index]!,
    ];
    if (facePoints.isNotEmpty) {
      return _expandedRectFromPoints(
        facePoints,
        minWidth: 0.10,
        minHeight: 0.10,
      );
    }

    final shoulderLeft = imagePoints[11];
    final shoulderRight = imagePoints[12];
    if (shoulderLeft != null && shoulderRight != null) {
      final shoulderCenter = NormalizedPoint(
        (shoulderLeft.x + shoulderRight.x) * 0.5,
        (shoulderLeft.y + shoulderRight.y) * 0.5,
      );
      final shoulderWidth = (shoulderRight.x - shoulderLeft.x).abs();
      final width = _clampRange(shoulderWidth * 0.62, 0.10, 0.24);
      final height = _clampRange(width * 1.12, 0.11, 0.26);
      return _rectAroundPoint(
        NormalizedPoint(shoulderCenter.x, shoulderCenter.y - height * 0.82),
        width,
        height,
      );
    }

    if (bodyBox != null && bodyBox.width > 0 && bodyBox.height > 0) {
      final width = _clampRange(bodyBox.width * 0.38, 0.10, 0.24);
      final height = _clampRange(bodyBox.height * 0.17, 0.11, 0.26);
      final left = bodyBox.left + (bodyBox.width - width) * 0.5;
      final top = bodyBox.top + bodyBox.height * 0.02;
      return NormalizedRect(
        left: _clamp01(left),
        top: _clamp01(top),
        width: _clampDimension(width, left),
        height: _clampDimension(height, top),
      );
    }

    return null;
  }

  static NormalizedRect? _expandedRectFromPoints(
    List<NormalizedPoint> points, {
    required double minWidth,
    required double minHeight,
  }) {
    var minX = 1.0;
    var minY = 1.0;
    var maxX = 0.0;
    var maxY = 0.0;
    for (final point in points) {
      minX = minX < point.x ? minX : point.x;
      minY = minY < point.y ? minY : point.y;
      maxX = maxX > point.x ? maxX : point.x;
      maxY = maxY > point.y ? maxY : point.y;
    }
    final rawWidth = (maxX - minX).abs();
    final rawHeight = (maxY - minY).abs();
    final width = _clampRange(rawWidth * 1.9, minWidth, 0.26);
    final height = _clampRange(rawHeight * 2.2, minHeight, 0.28);
    return _rectAroundPoint(
      NormalizedPoint((minX + maxX) * 0.5, (minY + maxY) * 0.5),
      width,
      height,
    );
  }

  static NormalizedRect _rectAroundPoint(
    NormalizedPoint center,
    double width,
    double height,
  ) {
    final left = center.x - width * 0.5;
    final top = center.y - height * 0.5;
    return NormalizedRect(
      left: _clamp01(left),
      top: _clamp01(top),
      width: _clampDimension(width, left),
      height: _clampDimension(height, top),
    );
  }

  static NormalizedRect? _rectFromList(Object? raw) {
    if (raw is! List || raw.length != 4) {
      return null;
    }
    final left = _toDouble(raw[0]);
    final top = _toDouble(raw[1]);
    final width = _toDouble(raw[2]);
    final height = _toDouble(raw[3]);
    if (left == null || top == null || width == null || height == null) {
      return null;
    }
    return NormalizedRect(
      left: _clamp01(left),
      top: _clamp01(top),
      width: _clampDimension(width, left),
      height: _clampDimension(height, top),
    );
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

  static double _clampRange(double value, double min, double max) {
    return value.clamp(min, max);
  }

  static double _clampDimension(double value, double start) {
    final clampedStart = _clamp01(start);
    return value.clamp(0.0, 1.0 - clampedStart);
  }
}
