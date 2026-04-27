class ScoreFormatter {
  const ScoreFormatter._();

  static String? formatHundred(num? rawScore) {
    if (rawScore == null) {
      return null;
    }
    final normalized = _normalize(rawScore);
    final rounded = normalized.round();
    if ((normalized - rounded).abs() < 0.05) {
      return '$rounded';
    }
    return normalized.toStringAsFixed(1);
  }

  static double _normalize(num rawScore) {
    final value = rawScore.toDouble();
    if (value <= 1 && value >= 0) {
      return value * 100;
    }
    if (value > 1 && value <= 10) {
      return value * 10;
    }
    return value.clamp(0, 100).toDouble();
  }
}
