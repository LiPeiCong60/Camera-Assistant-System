part of '../device_link_page.dart';

extension _DeviceLinkUrlHelpers on _DeviceLinkPageState {
  Uri _buildDeviceWebSocketUri(String path) {
    final withoutApi = _normalizedDeviceBaseUrl(_baseUrlController.text);
    final uri = Uri.parse(withoutApi);
    final scheme = uri.scheme == 'https' ? 'wss' : 'ws';
    final basePath = uri.path.endsWith('/')
        ? uri.path.substring(0, uri.path.length - 1)
        : uri.path;
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    return uri.replace(scheme: scheme, path: '$basePath$normalizedPath');
  }

  String _normalizedDeviceBaseUrl(String rawBaseUrl) {
    var normalized = rawBaseUrl.trim();
    if (normalized.endsWith('/')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    if (normalized.endsWith('/api')) {
      normalized = normalized.substring(0, normalized.length - 4);
    }
    return normalized;
  }

  String _deviceCaptureFileUrl(String rawPath) {
    final normalizedBaseUrl = _normalizedDeviceBaseUrl(_baseUrlController.text);
    return Uri.parse(
      '$normalizedBaseUrl/api/device/capture/file',
    ).replace(queryParameters: <String, String>{'path': rawPath}).toString();
  }

  String? _templatePreviewImageUrl(TemplateSummary template) {
    final rawUrl = template.previewImageUrl?.trim();
    if (rawUrl == null || rawUrl.isEmpty) {
      return null;
    }
    final uri = Uri.tryParse(rawUrl);
    if (uri != null && uri.hasScheme) {
      return rawUrl;
    }

    final apiBaseUrl = AppConfig.apiBaseUrl;
    final origin = apiBaseUrl.endsWith('/api')
        ? apiBaseUrl.substring(0, apiBaseUrl.length - 4)
        : apiBaseUrl;
    final path = rawUrl.startsWith('/') ? rawUrl : '/$rawUrl';
    return '$origin$path';
  }
}
