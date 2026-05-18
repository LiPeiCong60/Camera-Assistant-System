class DeviceTemplateSummary {
  const DeviceTemplateSummary({
    required this.id,
    required this.name,
    required this.imagePath,
    required this.createdAt,
    required this.bboxNorm,
    required this.posePointCount,
    this.templateData = const <String, dynamic>{},
    this.selected = false,
  });

  final String id;
  final String name;
  final String imagePath;
  final String createdAt;
  final List<double> bboxNorm;
  final int posePointCount;
  final Map<String, dynamic> templateData;
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
      templateData: json['template_data'] is Map
          ? Map<String, dynamic>.from(json['template_data'] as Map)
          : const <String, dynamic>{},
      selected: json['selected'] as bool? ?? false,
    );
  }
}
