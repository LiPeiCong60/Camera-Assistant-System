import 'package:flutter_test/flutter_test.dart';

import 'package:mobile_client/models/ai_task_summary.dart';

void main() {
  test('parses target_box_norm object format', () {
    final task = AiTaskSummary.fromJson(<String, dynamic>{
      'id': 1,
      'target_box_norm': <String, dynamic>{
        'x': 0.56,
        'y': '0.18',
        'w': 0.28,
        'h': 0.58,
        'label': 'recommended_person_position',
      },
    });

    expect(task.targetBoxNorm, <double>[0.56, 0.18, 0.28, 0.58]);
  });

  test('keeps compatibility with target_box_norm array format', () {
    final task = AiTaskSummary.fromJson(<String, dynamic>{
      'id': 2,
      'response_payload': <String, dynamic>{
        'target_box_norm': <dynamic>[0.1, 0.2, 0.3, 0.4],
      },
    });

    expect(task.targetBoxNorm, <double>[0.1, 0.2, 0.3, 0.4]);
  });
}
