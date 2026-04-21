class TemplateSummary {
  const TemplateSummary({
    required this.id,
    required this.name,
    required this.templateType,
    required this.templateData,
    required this.status,
    required this.isRecommendedDefault,
    this.previewImageUrl,
    this.recommendedSortOrder = 0,
  });

  final int id;
  final String name;
  final String templateType;
  final Map<String, dynamic> templateData;
  final String status;
  final bool isRecommendedDefault;
  final String? previewImageUrl;
  final int recommendedSortOrder;

  factory TemplateSummary.fromJson(Map<String, dynamic> json) {
    return TemplateSummary(
      id: json['id'] as int,
      name: json['name'] as String? ?? '',
      templateType: json['template_type'] as String? ?? 'pose',
      templateData:
          json['template_data'] as Map<String, dynamic>? ?? <String, dynamic>{},
      status: json['status'] as String? ?? 'active',
      isRecommendedDefault: json['is_recommended_default'] as bool? ?? false,
      previewImageUrl: json['preview_image_url'] as String?,
      recommendedSortOrder: json['recommended_sort_order'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'name': name,
      'template_type': templateType,
      'template_data': templateData,
      'status': status,
      'is_recommended_default': isRecommendedDefault,
      'preview_image_url': previewImageUrl,
      'recommended_sort_order': recommendedSortOrder,
    };
  }
}
