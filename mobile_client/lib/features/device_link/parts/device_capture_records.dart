part of '../device_link_page.dart';

extension _DeviceCaptureRecords on _DeviceLinkPageState {
  void _rememberDeviceCapturePath(String? path, {required String source}) {
    final normalizedPath = path?.trim();
    if (normalizedPath == null || normalizedPath.isEmpty) {
      return;
    }
    _lastCapturePath = normalizedPath;
    final existingIndex = _captureRecords.indexWhere(
      (record) => record.path == normalizedPath,
    );
    if (existingIndex >= 0) {
      final existing = _captureRecords.removeAt(existingIndex);
      _captureRecords.insert(
        0,
        existing.copyWith(
          backendCaptureId:
              existing.backendCaptureId ??
              _deviceHistoryCaptureIds[normalizedPath],
        ),
      );
      return;
    }
    _captureRecords.insert(
      0,
      _DeviceCaptureRecord(
        path: normalizedPath,
        createdAt: DateTime.now(),
        source: source,
        backendCaptureId: _deviceHistoryCaptureIds[normalizedPath],
      ),
    );
    if (_captureRecords.length > 12) {
      _captureRecords.removeRange(12, _captureRecords.length);
    }
  }
}
