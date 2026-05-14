part of '../device_link_page.dart';

extension _DeviceCaptureHelpers on _DeviceLinkPageState {
  String _deviceCaptureFileName(String rawPath) {
    final segments = rawPath.split(RegExp(r'[\\/]'));
    final original = segments.isEmpty ? '' : segments.last.trim();
    final fallback =
        'device_capture_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final candidate = original.isEmpty ? fallback : original;
    final safe = candidate.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    return safe.toLowerCase().endsWith('.jpg') ||
            safe.toLowerCase().endsWith('.jpeg')
        ? safe
        : '$safe.jpg';
  }

  String _shortDeviceCaptureName(String rawPath) {
    final filename = _deviceCaptureFileName(rawPath);
    if (filename.length <= 14) {
      return filename;
    }
    return '${filename.substring(0, 6)}...${filename.substring(filename.length - 7)}';
  }
}
