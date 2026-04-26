import 'ai_task_summary.dart';

class CaptureRecord {
  const CaptureRecord({
    required this.id,
    required this.sessionId,
    required this.userId,
    required this.captureType,
    required this.fileUrl,
    required this.storageProvider,
    required this.isAiSelected,
    required this.createdAt,
    this.thumbnailUrl,
    this.width,
    this.height,
    this.score,
    this.latestAiTask,
    this.metadata = const <String, dynamic>{},
  });

  final int id;
  final int sessionId;
  final int userId;
  final String captureType;
  final String fileUrl;
  final String? thumbnailUrl;
  final String storageProvider;
  final bool isAiSelected;
  final int? width;
  final int? height;
  final num? score;
  final AiTaskSummary? latestAiTask;
  final DateTime createdAt;
  final Map<String, dynamic> metadata;

  factory CaptureRecord.fromJson(Map<String, dynamic> json) {
    return CaptureRecord(
      id: json['id'] as int,
      sessionId: json['session_id'] as int,
      userId: json['user_id'] as int? ?? 0,
      captureType: json['capture_type'] as String? ?? 'single',
      fileUrl: json['file_url'] as String? ?? '',
      thumbnailUrl: json['thumbnail_url'] as String?,
      storageProvider: json['storage_provider'] as String? ?? 'local',
      isAiSelected: json['is_ai_selected'] as bool? ?? false,
      width: json['width'] as int?,
      height: json['height'] as int?,
      score: json['score'] as num?,
      latestAiTask: json['latest_ai_task'] is Map<String, dynamic>
          ? AiTaskSummary.fromJson(
              json['latest_ai_task'] as Map<String, dynamic>,
            )
          : null,
      createdAt: DateTime.parse(
        json['created_at'] as String? ?? DateTime.now().toIso8601String(),
      ),
      metadata:
          json['metadata'] as Map<String, dynamic>? ?? <String, dynamic>{},
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'session_id': sessionId,
      'user_id': userId,
      'capture_type': captureType,
      'file_url': fileUrl,
      'thumbnail_url': thumbnailUrl,
      'storage_provider': storageProvider,
      'is_ai_selected': isAiSelected,
      'width': width,
      'height': height,
      'score': score,
      'latest_ai_task': latestAiTask?.toJson(),
      'created_at': createdAt.toIso8601String(),
      'metadata': metadata,
    };
  }
}
