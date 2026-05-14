part of '../device_link_page.dart';

extension _DeviceLinkAiResultFormatters on _DeviceLinkPageState {
  String _formatAngleSearchResult(Map<String, dynamic> result) {
    final lines = <String>[];
    _addResultLine(lines, 'AI 判断', _resultValue(result, 'summary'));
    _addResultLine(lines, '最佳照片', _resultValue(result, 'capture_path'));
    _addResultLine(
      lines,
      '评分',
      _formatScore(_resultValue(result, 'best_score')),
    );
    _addResultLine(lines, '扫描数量', _resultValue(result, 'num_scanned'));
    _addResultLine(lines, '云台角度', _formatPanTilt(result));
    _addSuggestions(lines, _resultValue(result, 'suggestions'));
    return lines.isEmpty ? 'AI 已返回自动找角度结果。' : lines.join('\n');
  }

  String _formatBackgroundLockResult(Map<String, dynamic> result) {
    final nested = _resultValue(result, 'result');
    final resultMap = nested is Map
        ? Map<String, dynamic>.from(nested)
        : <String, dynamic>{};
    final source = resultMap.isEmpty ? result : resultMap;
    final lines = <String>[];
    _addResultLine(lines, 'AI 判断', _resultValue(source, 'summary'));
    _addResultLine(lines, '站位建议', _resultValue(source, 'placement'));
    _addResultLine(lines, '拍摄角度', _resultValue(source, 'camera_angle'));
    _addResultLine(lines, '光线判断', _resultValue(source, 'lighting'));
    _addResultLine(lines, '评分', _formatScore(_resultValue(source, 'score')));
    _addResultLine(lines, '扫描数量', _resultValue(result, 'num_scanned'));
    _addResultLine(lines, '锁定角度', _formatPanTilt(result));
    _addSuggestions(lines, _resultValue(source, 'suggestions'));
    return lines.isEmpty ? 'AI 已返回背景锁定结果。' : lines.join('\n');
  }

  String _formatCaptureAnalysis(
    DeviceCaptureAnalysisSummary analysis, {
    String? capturePath,
  }) {
    final lines = <String>[];
    _addResultLine(lines, 'AI 判断', analysis.summary);
    _addResultLine(lines, '抓拍照片', capturePath);
    _addResultLine(lines, '评分', _formatScore(analysis.score));
    _addSuggestions(lines, analysis.suggestions);
    return lines.isEmpty ? '抓拍 AI 分析已完成。' : lines.join('\n');
  }

  String _formatCaptureAnalysisMap(
    Map<String, dynamic> analysis, {
    String? capturePath,
  }) {
    final lines = <String>[];
    _addResultLine(lines, 'AI 判断', _resultValue(analysis, 'summary'));
    _addResultLine(lines, '抓拍照片', capturePath);
    _addResultLine(lines, '评分', _formatScore(_resultValue(analysis, 'score')));
    _addSuggestions(lines, _resultValue(analysis, 'suggestions'));
    return lines.isEmpty ? '抓拍 AI 分析已完成。' : lines.join('\n');
  }

  dynamic _resultValue(Map<String, dynamic> result, String key) {
    return result[key] ??
        result[_toSnakeCase(key)] ??
        result[_toCamelCase(key)];
  }

  String? _formatScore(dynamic value) {
    if (value is num) {
      return ScoreFormatter.formatHundred(value);
    }
    final parsed = num.tryParse(value?.toString() ?? '');
    return ScoreFormatter.formatHundred(parsed);
  }

  String? _formatPanTilt(Map<String, dynamic> result) {
    final pan =
        _resultValue(result, 'best_pan') ?? _resultValue(result, 'current_pan');
    final tilt =
        _resultValue(result, 'best_tilt') ??
        _resultValue(result, 'current_tilt');
    if (pan == null && tilt == null) {
      return null;
    }
    return 'pan ${pan ?? '-'} / tilt ${tilt ?? '-'}';
  }

  void _addResultLine(List<String> lines, String label, dynamic value) {
    if (value == null) {
      return;
    }
    final text = value.toString().trim();
    if (text.isEmpty) {
      return;
    }
    lines.add('$label：$text');
  }

  void _addSuggestions(List<String> lines, dynamic suggestions) {
    if (suggestions is! Iterable) {
      return;
    }
    final values = suggestions
        .map((item) => item.toString().trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
    if (values.isEmpty) {
      return;
    }
    lines.add('建议：${values.join('；')}');
  }

  String _toSnakeCase(String value) {
    return value.replaceAllMapped(
      RegExp(r'[A-Z]'),
      (match) => '_${match.group(0)!.toLowerCase()}',
    );
  }

  String _toCamelCase(String value) {
    return value.replaceAllMapped(
      RegExp(r'_([a-z])'),
      (match) => match.group(1)!.toUpperCase(),
    );
  }
}
