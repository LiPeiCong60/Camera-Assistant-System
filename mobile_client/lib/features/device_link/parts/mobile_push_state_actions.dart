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
    _lastMobilePushFrameAt = lastFrameAt;
  }

  void _resetMobilePushTransportState() {
    _isMobilePushEnabled = false;
    _isPushingMobileFrame = false;
    _isHandlingMobilePushOrientationChange = false;
    _mobilePushConfigSent = false;
    _mobilePushCamera = null;
    _mobilePushRotationDegrees = -1;
    _resetMobilePushFrameStats();
  }

  void _markMobilePushStarted({
    required CameraDescription camera,
    required DateTime? lastFrameAt,
  }) {
    _mobilePushCamera = camera;
    _mobilePushLensDirection = camera.lensDirection;
    _isMobilePushEnabled = true;
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
        sender.isOpen &&
        image.planes.isNotEmpty;
  }

  bool _isMobilePushFrameThrottled(int nowMs) {
    return nowMs - _lastMobilePushFrameSentAtMs <
        _DeviceLinkPageState._mobilePushFrameThrottle.inMilliseconds;
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
