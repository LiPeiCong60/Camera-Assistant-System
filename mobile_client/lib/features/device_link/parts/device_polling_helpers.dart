part of '../device_link_page.dart';

extension _DevicePollingHelpers on _DeviceLinkPageState {
  Duration _resolvePollInterval(DeviceStatusSummary? status) {
    final hasCountdown =
        status?.gestureStatus.captureCountdownActive == true ||
        status?.aiStatus.countdown.active == true;
    return hasCountdown
        ? _DeviceLinkPageState._countdownPollInterval
        : _DeviceLinkPageState._defaultPollInterval;
  }

  String _formatUpdatedAt() {
    final updatedAt = _lastStatusUpdatedAt;
    if (updatedAt == null) {
      return '-';
    }
    return _formatClock(updatedAt);
  }

  String _formatClock(DateTime value) {
    final updatedAt = value;
    final hh = updatedAt.hour.toString().padLeft(2, '0');
    final mm = updatedAt.minute.toString().padLeft(2, '0');
    final ss = updatedAt.second.toString().padLeft(2, '0');
    return '$hh:$mm:$ss';
  }
}
