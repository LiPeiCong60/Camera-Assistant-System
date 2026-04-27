import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../models/device_health_summary.dart';
import '../models/device_status_summary.dart';
import '../models/device_template_summary.dart';
import 'api_client.dart';

class DeviceCaptureTriggerResult {
  const DeviceCaptureTriggerResult({
    required this.path,
    this.analysis,
    this.analysisError,
  });

  final String path;
  final Map<String, dynamic>? analysis;
  final String? analysisError;
}

class DeviceCaptureFileSummary {
  const DeviceCaptureFileSummary({
    required this.path,
    required this.filename,
    this.relativePath,
    this.sizeBytes,
    this.modifiedAt,
  });

  final String path;
  final String filename;
  final String? relativePath;
  final int? sizeBytes;
  final DateTime? modifiedAt;

  factory DeviceCaptureFileSummary.fromJson(Map<String, dynamic> json) {
    final modifiedAtRaw = json['modified_at'] as String?;
    return DeviceCaptureFileSummary(
      path: json['path'] as String? ?? '',
      filename: json['filename'] as String? ?? 'device_capture.jpg',
      relativePath: json['relative_path'] as String?,
      sizeBytes: (json['size_bytes'] as num?)?.toInt(),
      modifiedAt: modifiedAtRaw == null
          ? null
          : DateTime.tryParse(modifiedAtRaw)?.toLocal(),
    );
  }
}

class DeviceApiService {
  const DeviceApiService();

  static const Duration _requestTimeout = Duration(seconds: 10);

  Future<DeviceHealthSummary> getHealth({required String baseUrl}) async {
    final data = await _getJson(baseUrl, '/api/device/health');
    return DeviceHealthSummary.fromJson(data);
  }

  Future<DeviceStatusSummary> getStatus({required String baseUrl}) async {
    final data = await _getJson(baseUrl, '/api/device/status');
    return DeviceStatusSummary.fromJson(data);
  }

  Future<DeviceAiStatusSummary> getAiStatus({required String baseUrl}) async {
    final data = await _getJson(baseUrl, '/api/device/ai/status');
    return DeviceAiStatusSummary.fromJson(data);
  }

  Future<DeviceStatusSummary> updateDeviceConfig({
    required String baseUrl,
    Map<String, bool>? overlay,
    Map<String, bool>? gesture,
    Map<String, bool>? detection,
  }) async {
    final body = <String, dynamic>{};
    if (overlay != null) {
      body['overlay'] = overlay;
    }
    if (gesture != null) {
      body['gesture'] = gesture;
    }
    if (detection != null) {
      body['detection'] = detection;
    }
    final data = await _patchJson(baseUrl, '/api/device/config', body);
    return DeviceStatusSummary.fromJson(data);
  }

  Future<DeviceStatusSummary> openSession({
    required String baseUrl,
    required String sessionCode,
    required String streamUrl,
    bool mirrorView = false,
    String startMode = 'MANUAL',
  }) async {
    final data =
        await _postJson(baseUrl, '/api/device/session/open', <String, dynamic>{
          'session_code': sessionCode,
          'stream_url': streamUrl,
          'mirror_view': mirrorView,
          'start_mode': startMode,
        });
    return DeviceStatusSummary(
      sessionOpened: true,
      sessionCode: data['session_code'] as String?,
      streamUrl: data['stream_url'] as String?,
      mode: data['mode'] as String? ?? startMode,
      followMode: null,
      deviceStatus: 'online',
      currentPan: 0,
      currentTilt: 0,
      loopRunning: true,
    );
  }

  Future<bool> closeSession({
    required String baseUrl,
    String? sessionCode,
  }) async {
    final data = await _postJson(
      baseUrl,
      '/api/device/session/close',
      <String, dynamic>{'session_code': sessionCode},
    );
    return data['closed'] as bool? ?? false;
  }

  Future<DeviceStatusSummary> manualMove({
    required String baseUrl,
    String? action,
    double? panDelta,
    double? tiltDelta,
  }) async {
    await sendManualMoveCommand(
      baseUrl: baseUrl,
      action: action,
      panDelta: panDelta,
      tiltDelta: tiltDelta,
    );
    return getStatus(baseUrl: baseUrl);
  }

  Future<void> sendManualMoveCommand({
    required String baseUrl,
    String? action,
    double? panDelta,
    double? tiltDelta,
  }) async {
    await _postJson(
      baseUrl,
      '/api/device/control/manual-move',
      <String, dynamic>{
        'action': action,
        'pan_delta': panDelta,
        'tilt_delta': tiltDelta,
      },
    );
  }

  Future<DeviceStatusSummary> setMode({
    required String baseUrl,
    required String mode,
  }) async {
    await _postJson(baseUrl, '/api/device/control/mode', <String, dynamic>{
      'mode': mode,
    });
    return getStatus(baseUrl: baseUrl);
  }

  Future<DeviceStatusSummary> home({required String baseUrl}) async {
    await _postJson(baseUrl, '/api/device/control/home', <String, dynamic>{});
    return getStatus(baseUrl: baseUrl);
  }

  Future<DeviceStatusSummary> setFollowMode({
    required String baseUrl,
    required String followMode,
  }) async {
    await _postJson(
      baseUrl,
      '/api/device/control/follow-mode',
      <String, dynamic>{'follow_mode': followMode},
    );
    return getStatus(baseUrl: baseUrl);
  }

  Future<DeviceStatusSummary> restartStream({
    required String baseUrl,
    required String streamUrl,
  }) async {
    await _postJson(baseUrl, '/api/device/stream/start', <String, dynamic>{
      'stream_url': streamUrl,
    });
    return getStatus(baseUrl: baseUrl);
  }

  Future<List<DeviceTemplateSummary>> listDeviceTemplates({
    required String baseUrl,
  }) async {
    final data = await _getJson(baseUrl, '/api/device/templates');
    final items = data['items'] as List<dynamic>? ?? const <dynamic>[];
    return items
        .whereType<Map<String, dynamic>>()
        .map(DeviceTemplateSummary.fromJson)
        .toList(growable: false);
  }

  Future<DeviceTemplateSummary> uploadDeviceTemplate({
    required String baseUrl,
    required File file,
    required String name,
    bool selectAfterImport = true,
  }) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('${_normalizeBaseUrl(baseUrl)}/api/device/templates/upload'),
    );
    request.headers['Accept'] = 'application/json';
    request.fields['name'] = name;
    request.fields['select_after_import'] = selectAfterImport.toString();
    request.files.add(
      await http.MultipartFile.fromPath(
        'file',
        file.path,
        filename: file.uri.pathSegments.isEmpty
            ? 'template.jpg'
            : file.uri.pathSegments.last,
      ),
    );

    final response = await _send(() async {
      final streamed = await request.send();
      return http.Response.fromStream(streamed);
    });
    return DeviceTemplateSummary.fromJson(_decodeEnvelope(response));
  }

  Future<void> deleteDeviceTemplate({
    required String baseUrl,
    required String templateId,
  }) async {
    await _deleteJson(
      baseUrl,
      '/api/device/templates/${Uri.encodeComponent(templateId)}',
    );
  }

  Future<DeviceStatusSummary> selectTemplate({
    required String baseUrl,
    required Object templateId,
    Map<String, dynamic>? templateData,
  }) async {
    await _postJson(baseUrl, '/api/device/templates/select', <String, dynamic>{
      'template_id': templateId,
      'template_data': templateData,
    });
    return getStatus(baseUrl: baseUrl);
  }

  Future<DeviceStatusSummary> clearTemplate({required String baseUrl}) async {
    await _postJson(
      baseUrl,
      '/api/device/templates/clear',
      <String, dynamic>{},
    );
    return getStatus(baseUrl: baseUrl);
  }

  Future<DeviceAiStatusSummary> startAngleSearch({
    required String baseUrl,
    double panRange = 6,
    double tiltRange = 3,
    double panStep = 4,
    double tiltStep = 3,
    int maxCandidates = 5,
    double settleSeconds = 0.5,
  }) async {
    final data = await _postJson(
      baseUrl,
      '/api/device/ai/angle-search/start',
      <String, dynamic>{
        'pan_range': panRange,
        'tilt_range': tiltRange,
        'pan_step': panStep,
        'tilt_step': tiltStep,
        'max_candidates': maxCandidates,
        'settle_s': settleSeconds,
      },
    );
    return DeviceAiStatusSummary.fromJson(data);
  }

  Future<DeviceAiStatusSummary> startBackgroundLock({
    required String baseUrl,
    double panRange = 6,
    double tiltRange = 3,
    double panStep = 4,
    double tiltStep = 3,
    int maxCandidates = 5,
    double settleSeconds = 0.5,
    double delaySeconds = 0,
  }) async {
    final data = await _postJson(
      baseUrl,
      '/api/device/ai/background-lock/start',
      <String, dynamic>{
        'pan_range': panRange,
        'tilt_range': tiltRange,
        'pan_step': panStep,
        'tilt_step': tiltStep,
        'max_candidates': maxCandidates,
        'settle_s': settleSeconds,
        'delay_s': delaySeconds,
      },
    );
    return DeviceAiStatusSummary.fromJson(data);
  }

  Future<DeviceAiStatusSummary> unlockBackgroundLock({
    required String baseUrl,
  }) async {
    final data = await _postJson(
      baseUrl,
      '/api/device/ai/background-lock/unlock',
      <String, dynamic>{},
    );
    return DeviceAiStatusSummary.fromJson(data);
  }

  Future<DeviceStatusSummary> applyAngle({
    required String baseUrl,
    required double recommendedPanDelta,
    required double recommendedTiltDelta,
    String summary = 'Apply mobile AI angle suggestion.',
    double score = 88,
  }) async {
    await _postJson(baseUrl, '/api/device/ai/apply-angle', <String, dynamic>{
      'task_type': 'auto_angle',
      'recommended_pan_delta': recommendedPanDelta,
      'recommended_tilt_delta': recommendedTiltDelta,
      'summary': summary,
      'score': score,
    });
    return getStatus(baseUrl: baseUrl);
  }

  Future<DeviceStatusSummary> applyLock({
    required String baseUrl,
    required double recommendedPanDelta,
    required double recommendedTiltDelta,
    required List<double> targetBoxNorm,
    String summary = 'Apply mobile AI lock suggestion.',
    double score = 92,
  }) async {
    await _postJson(baseUrl, '/api/device/ai/apply-lock', <String, dynamic>{
      'task_type': 'background_lock',
      'recommended_pan_delta': recommendedPanDelta,
      'recommended_tilt_delta': recommendedTiltDelta,
      'target_box_norm': targetBoxNorm,
      'summary': summary,
      'score': score,
    });
    return getStatus(baseUrl: baseUrl);
  }

  Future<DeviceCaptureTriggerResult> triggerCapture({
    required String baseUrl,
    String reason = 'mobile_manual',
    bool autoAnalyze = false,
  }) async {
    final data = await _postJson(
      baseUrl,
      '/api/device/capture/trigger',
      <String, dynamic>{'reason': reason, 'auto_analyze': autoAnalyze},
    );
    return DeviceCaptureTriggerResult(
      path: data['capture_path'] as String? ?? '',
      analysis: data['analysis'] as Map<String, dynamic>?,
      analysisError: data['analysis_error'] as String?,
    );
  }

  Future<List<DeviceCaptureFileSummary>> listCaptureFiles({
    required String baseUrl,
    int limit = 20,
  }) async {
    final data = await _getJson(
      baseUrl,
      '/api/device/capture/list?limit=$limit',
    );
    final items = data['items'] as List<dynamic>? ?? const <dynamic>[];
    return items
        .whereType<Map<String, dynamic>>()
        .map(DeviceCaptureFileSummary.fromJson)
        .toList(growable: false);
  }

  Future<List<int>> downloadCaptureFile({
    required String baseUrl,
    required String path,
  }) async {
    final response = await _send(
      () => http.get(
        Uri.parse(
          '${_normalizeBaseUrl(baseUrl)}/api/device/capture/file',
        ).replace(queryParameters: <String, String>{'path': path}),
        headers: const <String, String>{'Accept': 'image/jpeg'},
      ),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      _decodeEnvelope(response);
    }
    return response.bodyBytes;
  }

  Future<void> pushMobileFrame({
    required String baseUrl,
    required File file,
  }) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('${_normalizeBaseUrl(baseUrl)}/api/device/stream/frame'),
    );
    request.headers['Accept'] = 'application/json';
    request.files.add(
      await http.MultipartFile.fromPath(
        'file',
        file.path,
        filename: 'mobile_frame.jpg',
      ),
    );

    final response = await _send(() async {
      final streamed = await request.send();
      return http.Response.fromStream(streamed);
    });
    _decodeEnvelope(response);
  }

  Future<Map<String, dynamic>> _getJson(String baseUrl, String path) async {
    final response = await _send(
      () => http.get(
        Uri.parse('${_normalizeBaseUrl(baseUrl)}$path'),
        headers: const <String, String>{'Accept': 'application/json'},
      ),
    );
    return _decodeEnvelope(response);
  }

  Future<Map<String, dynamic>> _postJson(
    String baseUrl,
    String path,
    Map<String, dynamic> body,
  ) async {
    final response = await _send(
      () => http.post(
        Uri.parse('${_normalizeBaseUrl(baseUrl)}$path'),
        headers: const <String, String>{
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode(body),
      ),
    );
    return _decodeEnvelope(response);
  }

  Future<Map<String, dynamic>> _patchJson(
    String baseUrl,
    String path,
    Map<String, dynamic> body,
  ) async {
    final response = await _send(
      () => http.patch(
        Uri.parse('${_normalizeBaseUrl(baseUrl)}$path'),
        headers: const <String, String>{
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode(body),
      ),
    );
    return _decodeEnvelope(response);
  }

  Future<Map<String, dynamic>> _deleteJson(String baseUrl, String path) async {
    final response = await _send(
      () => http.delete(
        Uri.parse('${_normalizeBaseUrl(baseUrl)}$path'),
        headers: const <String, String>{'Accept': 'application/json'},
      ),
    );
    return _decodeEnvelope(response);
  }

  Future<http.Response> _send(Future<http.Response> Function() request) async {
    try {
      return await request().timeout(_requestTimeout);
    } on TimeoutException {
      throw const ApiException('设备响应超时，请检查设备地址或稍后重试。');
    } on SocketException {
      throw const ApiException('无法连接设备，请确认本地运行时服务已启动且地址正确。');
    } on http.ClientException {
      throw const ApiException('设备请求失败，请检查设备地址和网络状态。');
    }
  }

  String _normalizeBaseUrl(String rawBaseUrl) {
    var normalized = rawBaseUrl.trim();
    if (normalized.endsWith('/')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    if (normalized.endsWith('/api')) {
      normalized = normalized.substring(0, normalized.length - 4);
    }
    return normalized;
  }

  Map<String, dynamic> _decodeEnvelope(http.Response response) {
    final body = _safeDecodeBody(response);
    final success = body['success'] as bool? ?? false;
    if (!success) {
      final detail = body['detail'];
      final backendMessage =
          body['message'] as String? ?? (detail is String ? detail : null);
      throw ApiException(
        _humanizeErrorMessage(
          response.statusCode,
          backendMessage,
          fallback: '设备请求失败，请稍后重试。',
        ),
        statusCode: response.statusCode,
      );
    }
    return body['data'] as Map<String, dynamic>? ?? <String, dynamic>{};
  }

  Map<String, dynamic> _safeDecodeBody(http.Response response) {
    if (response.body.isEmpty) {
      return <String, dynamic>{};
    }

    try {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } on FormatException {
      throw ApiException(
        response.statusCode >= 500 ? '设备服务暂时不可用，请稍后重试。' : '设备返回了无法识别的数据，请稍后重试。',
        statusCode: response.statusCode,
      );
    }
  }

  String _humanizeErrorMessage(
    int statusCode,
    String? backendMessage, {
    required String fallback,
  }) {
    final normalizedMessage = backendMessage?.trim();
    if (normalizedMessage == null ||
        normalizedMessage.isEmpty ||
        normalizedMessage == 'Not Found' ||
        normalizedMessage == 'request failed') {
      return _fallbackStatusMessage(statusCode, fallback);
    }
    return normalizedMessage;
  }

  String _fallbackStatusMessage(int statusCode, String fallback) {
    switch (statusCode) {
      case 400:
        return '设备请求参数无效，请检查输入后重试。';
      case 404:
        return '设备接口不存在，请确认本地运行时服务已更新。';
      case 409:
        return '当前设备状态不允许执行该操作，请刷新后再试。';
      case 422:
        return '设备请求格式不正确，请检查输入后重试。';
      default:
        if (statusCode >= 500) {
          return '设备服务暂时不可用，请稍后重试。';
        }
        return fallback;
    }
  }
}
