import 'ai_task_summary.dart';

class BatchPickResult {
  const BatchPickResult({required this.task, required this.bestCaptureId});

  final AiTaskSummary task;
  final int? bestCaptureId;

  factory BatchPickResult.fromJson(Map<String, dynamic> json) {
    return BatchPickResult(
      task: AiTaskSummary.fromJson(
        json['task'] as Map<String, dynamic>? ?? <String, dynamic>{},
      ),
      bestCaptureId: json['best_capture_id'] as int?,
    );
  }
}
