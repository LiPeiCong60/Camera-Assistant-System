class AiTaskSummary {
  const AiTaskSummary({
    required this.id,
    required this.taskCode,
    required this.taskType,
    required this.status,
    required this.requestPayload,
    required this.responsePayload,
    required this.createdAt,
    this.resultSummary,
    this.resultScore,
    this.targetBoxNorm,
    this.recommendedPanDelta,
    this.recommendedTiltDelta,
    this.errorMessage,
    this.providerMetadata = const <String, dynamic>{},
  });

  final int id;
  final String taskCode;
  final String taskType;
  final String status;
  final Map<String, dynamic> requestPayload;
  final Map<String, dynamic> responsePayload;
  final String? resultSummary;
  final num? resultScore;
  final List<double>? targetBoxNorm;
  final double? recommendedPanDelta;
  final double? recommendedTiltDelta;
  final String? errorMessage;
  final Map<String, dynamic> providerMetadata;
  final DateTime createdAt;

  factory AiTaskSummary.fromJson(Map<String, dynamic> json) {
    final responsePayload =
        json['response_payload'] as Map<String, dynamic>? ??
        <String, dynamic>{};
    return AiTaskSummary(
      id: json['id'] as int,
      taskCode: json['task_code'] as String? ?? '',
      taskType: json['task_type'] as String? ?? 'analyze_photo',
      status: json['status'] as String? ?? 'pending',
      requestPayload:
          json['request_payload'] as Map<String, dynamic>? ??
          <String, dynamic>{},
      responsePayload: responsePayload,
      resultSummary: json['result_summary'] as String?,
      resultScore:
          _readNum(json['result_score']) ?? _readNum(responsePayload['score']),
      targetBoxNorm: _readTargetBoxNorm(
        json['target_box_norm'] ?? responsePayload['target_box_norm'],
      ),
      recommendedPanDelta:
          (_readNum(json['recommended_pan_delta']) ??
                  _readNum(responsePayload['recommended_pan_delta']))
              ?.toDouble(),
      recommendedTiltDelta:
          (_readNum(json['recommended_tilt_delta']) ??
                  _readNum(responsePayload['recommended_tilt_delta']))
              ?.toDouble(),
      errorMessage: json['error_message'] as String?,
      providerMetadata:
          responsePayload['provider_metadata'] as Map<String, dynamic>? ??
          <String, dynamic>{},
      createdAt: DateTime.parse(
        json['created_at'] as String? ?? DateTime.now().toIso8601String(),
      ),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'task_code': taskCode,
      'task_type': taskType,
      'status': status,
      'request_payload': requestPayload,
      'response_payload': responsePayload,
      'result_summary': resultSummary,
      'result_score': resultScore,
      'target_box_norm': targetBoxNorm,
      'recommended_pan_delta': recommendedPanDelta,
      'recommended_tilt_delta': recommendedTiltDelta,
      'error_message': errorMessage,
      'created_at': createdAt.toIso8601String(),
    };
  }

  static List<double>? _readTargetBoxNorm(dynamic value) {
    if (value is! List<dynamic> || value.length != 4) {
      return null;
    }
    final numbers = value
        .map((item) => _readNum(item)?.toDouble())
        .toList(growable: false);
    if (numbers.any((item) => item == null)) {
      return null;
    }
    return numbers.cast<double>();
  }

  static num? _readNum(dynamic value) {
    if (value is num) {
      return value;
    }
    if (value is String) {
      return num.tryParse(value.trim());
    }
    return null;
  }
}
