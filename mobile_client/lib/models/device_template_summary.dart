class DeviceTemplateSummary {
  const DeviceTemplateSummary({
    required this.id,
    required this.name,
    required this.imagePath,
    required this.createdAt,
    required this.bboxNorm,
    required this.posePointCount,
    this.selected = false,
  });

  final String id;
  final String name;
  final String imagePath;
  final String createdAt;
  final List<double> bboxNorm;
  final int posePointCount;
  final bool selected;

  factory DeviceTemplateSummary.fromJson(Map<String, dynamic> json) {
    return DeviceTemplateSummary(
      id: (json['template_id'] ?? '').toString(),
      name: json['name'] as String? ?? '',
      imagePath: json['image_path'] as String? ?? '',
      createdAt: json['created_at'] as String? ?? '',
      bboxNorm: (json['bbox_norm'] as List<dynamic>? ?? const <dynamic>[])
          .whereType<num>()
          .map((value) => value.toDouble())
          .toList(growable: false),
      posePointCount: (json['pose_point_count'] as num?)?.toInt() ?? 0,
      selected: json['selected'] as bool? ?? false,
    );
  }
}
