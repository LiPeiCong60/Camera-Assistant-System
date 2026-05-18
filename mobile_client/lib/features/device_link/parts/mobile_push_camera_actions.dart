part of '../device_link_page.dart';

extension _DeviceLinkMobilePushCameraActions on _DeviceLinkPageState {
  Future<CameraDescription> _preferredMobilePushCamera() async {
    if (_mobilePushCameras.isEmpty) {
      _mobilePushCameras = await availableCameras();
    }
    if (_mobilePushCameras.isEmpty) {
      throw const ApiException('没有找到可用摄像头，请检查系统权限。');
    }
    if (!_isMobilePushEnabled) {
      final prefs = await SharedPreferences.getInstance();
      final preferredLens = prefs.getString(
        _DeviceLinkPageState._detailedSettingKey('push.camera_lens'),
      );
      if (preferredLens == 'front') {
        _mobilePushLensDirection = CameraLensDirection.front;
      } else if (preferredLens == 'back') {
        _mobilePushLensDirection = CameraLensDirection.back;
      }
    }
    return _findMobilePushCamera(_mobilePushLensDirection) ??
        _findMobilePushCamera(CameraLensDirection.back) ??
        _mobilePushCameras.first;
  }

  CameraDescription? _findMobilePushCamera(CameraLensDirection direction) {
    for (final camera in _mobilePushCameras) {
      if (camera.lensDirection == direction) {
        return camera;
      }
    }
    return null;
  }

  String _mobilePushLensLabel([CameraLensDirection? direction]) {
    final lensDirection =
        direction ??
        _mobilePushCamera?.lensDirection ??
        _mobilePushLensDirection;
    return switch (lensDirection) {
      CameraLensDirection.front => '前摄',
      CameraLensDirection.back => '后摄',
      CameraLensDirection.external => '外接摄像头',
    };
  }

  String _mobilePushSwitchTargetLabel() {
    final currentDirection =
        _mobilePushCamera?.lensDirection ?? _mobilePushLensDirection;
    return currentDirection == CameraLensDirection.front ? '切换到后摄' : '切换到前摄';
  }
}
