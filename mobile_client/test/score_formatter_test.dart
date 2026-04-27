import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_client/utils/score_formatter.dart';

void main() {
  test('normalizes AI scores to the 0-100 display scale', () {
    expect(ScoreFormatter.formatHundred(0.85), '85');
    expect(ScoreFormatter.formatHundred(8.5), '85');
    expect(ScoreFormatter.formatHundred(85), '85');
  });
}
