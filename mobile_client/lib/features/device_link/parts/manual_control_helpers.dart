part of '../device_link_page.dart';

extension _DeviceLinkManualControlHelpers on _DeviceLinkPageState {
  Offset _defaultJoystickAnchor(bool isLandscape) {
    if (!isLandscape) {
      return const Offset(0.72, 0.70);
    }
    return _landscapeControlsOnLeft
        ? const Offset(0.74, 0.56)
        : const Offset(0.26, 0.56);
  }

  Offset _effectiveJoystickAnchor(bool isLandscape) {
    return _hasCustomJoystickAnchor
        ? _joystickAnchor
        : _defaultJoystickAnchor(isLandscape);
  }
}
