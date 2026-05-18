part of '../device_link_page.dart';

extension _DeviceLinkMobilePushStateActions on _DeviceLinkPageState {
  void _markMobilePushStarting() {
    _isStartingMobilePush = true;
    _mobilePushErrorMessage = null;
  }

  void _markMobilePushStartFinished() {
    _isStartingMobilePush = false;
  }

  void _resetMobilePushFrameStats({DateTime? lastFrameAt}) {
    _mobilePushFrameCount = 0;
    _lastMobilePushFrameSentAtMs = 0;
    _lastMobilePushUiUpdateAtMs = 0;
    _lastMobileTrackTargetSentAtMs = 0;
    _consecutiveMobilePoseMisses = 0;
    _lastMobilePushFrameAt = lastFrameAt;
  }

  void _resetMobilePushTransportState() {
    _isMobilePushEnabled = false;
    _isPushingMobileFrame = false;
    _isProcessingMobileTrackTarget = false;
    _useMobilePushHttpFallback = false;
    _isHandlingMobilePushOrientationChange = false;
    _isDeviceLinkRecordingVideo = false;
    _isDeviceLinkRecordingPreviewPaused = false;
    _isFinalizingDeviceLinkVideo = false;
    _deviceLinkRecordingPreviewBytes = null;
    _deviceLinkRecordingStartedAt = null;
    _mobilePushConfigSent = false;
    _mobilePushCamera = null;
    _mobilePushRotationDegrees = -1;
    _latestMobileVisionOverlay = null;
    _lastRecordingPreviewFrameAtMs = 0;
    _resetMobilePushFrameStats();
  }

  void _markMobilePushStarted({
    required CameraDescription camera,
    required DateTime? lastFrameAt,
  }) {
    _mobilePushCamera = camera;
    _mobilePushLensDirection = camera.lensDirection;
    _isMobilePushEnabled = true;
    _useMobilePushHttpFallback = false;
    _latestMobileVisionOverlay = null;
    _resetMobilePushFrameStats(lastFrameAt: lastFrameAt);
  }

  void _resetMobilePushFrameConfig() {
    _mobilePushRotationDegrees = -1;
    _mobilePushConfigSent = false;
  }

  void _beginMobilePushOrientationChange() {
    _isHandlingMobilePushOrientationChange = true;
    _isPushingMobileFrame = false;
    _mobilePushErrorMessage = null;
  }

  void _finishMobilePushOrientationChange() {
    _isHandlingMobilePushOrientationChange = false;
  }

  bool _shouldSendMobilePushFrame({
    required _MobilePushSocketSender sender,
    required CameraImage image,
  }) {
    return _isMobilePushEnabled &&
        !_isPushingMobileFrame &&
        (sender.isOpen || _status?.sessionOpened == true) &&
        image.planes.isNotEmpty;
  }

  bool _isMobilePushFrameThrottled(int nowMs) {
    final interval = _useMobilePushHttpFallback
        ? _DeviceLinkPageState._mobilePushHttpFallbackFrameThrottle
        : _DeviceLinkPageState._mobilePushFrameThrottle;
    return nowMs - _lastMobilePushFrameSentAtMs < interval.inMilliseconds;
  }

  void _markMobilePushFrameSending() {
    _isPushingMobileFrame = true;
  }

  void _markMobilePushFrameSendFinished() {
    _isPushingMobileFrame = false;
  }

  bool _shouldRefreshMobilePushFrameUi(int nowMs) {
    return nowMs - _lastMobilePushUiUpdateAtMs >=
        const Duration(milliseconds: 300).inMilliseconds;
  }

  void _markMobilePushFrameSent(int nowMs) {
    _lastMobilePushFrameSentAtMs = nowMs;
    _mobilePushFrameCount += 1;
  }

  void _markMobilePushFrameUiUpdated(int nowMs) {
    _lastMobilePushFrameAt = DateTime.now();
    _lastMobilePushUiUpdateAtMs = nowMs;
    _mobilePushErrorMessage = null;
  }
}
