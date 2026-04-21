class CaptureSessionSummary {
  const CaptureSessionSummary({
    required this.id,
    required this.sessionCode,
    required this.userId,
    required this.mode,
    required this.status,
    required this.startedAt,
    this.deviceId,
    this.templateId,
    this.endedAt,
    this.metadata = const <String, dynamic>{},
  });

  final int id;
  final String sessionCode;
  final int userId;
  final int? deviceId;
  final int? templateId;
  final String mode;
  final String status;
  final DateTime startedAt;
  final DateTime? endedAt;
  final Map<String, dynamic> metadata;

  factory CaptureSessionSummary.fromJson(Map<String, dynamic> json) {
    return CaptureSessionSummary(
      id: json['id'] as int,
      sessionCode: json['session_code'] as String? ?? '',
      userId: json['user_id'] as int? ?? 0,
      deviceId: json['device_id'] as int?,
      templateId: json['template_id'] as int?,
      mode: json['mode'] as String? ?? 'mobile_only',
      status: json['status'] as String? ?? 'opened',
      startedAt: DateTime.parse(
        json['started_at'] as String? ?? DateTime.now().toIso8601String(),
      ),
      endedAt: json['ended_at'] == null
          ? null
          : DateTime.parse(json['ended_at'] as String),
      metadata:
          json['metadata'] as Map<String, dynamic>? ?? <String, dynamic>{},
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'session_code': sessionCode,
      'user_id': userId,
      'device_id': deviceId,
      'template_id': templateId,
      'mode': mode,
      'status': status,
      'started_at': startedAt.toIso8601String(),
      'ended_at': endedAt?.toIso8601String(),
      'metadata': metadata,
    };
  }
}
