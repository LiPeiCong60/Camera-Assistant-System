part of '../device_link_page.dart';

const Map<String, String> _deviceModeDisplayLabels = <String, String>{
  'MANUAL': '手动控制',
  'AUTO_TRACK': '自动跟随',
  'SMART_COMPOSE': '模板构图',
};

const Map<String, String> _deviceFollowModeDisplayLabels = <String, String>{
  'shoulders': '肩部跟随',
  'face': '人脸跟随',
};

extension _DeviceDisplayHelpers on _DeviceLinkPageState {
  String _captureDisplayName(String path) {
    final lastSlash = math.max(path.lastIndexOf('/'), path.lastIndexOf('\\'));
    return lastSlash < 0 ? path : path.substring(lastSlash + 1);
  }

  String _statusHeadline() {
    if (_status?.sessionOpened == true) {
      return '设备会话运行中。';
    }
    if (_health != null) {
      return '设备服务可访问。';
    }
    return '等待连接设备';
  }

  String _statusDescription() {
    if (_status?.sessionOpened == true) {
      return '当前会话  已打开，可继续执行控制、模板下发和 AI 动作。';
    }
    if (_health != null) {
      return '本地设备运行时已启动，但当前还没有打开设备会话。';
    }
    return '先填写设备地址和视频流地址，再执行健康检查或打开会话。';
  }

  String _modeDisplayLabel(String mode) {
    return _deviceModeDisplayLabels[mode] ?? mode;
  }

  String _followModeDisplayLabel(String mode) {
    return _deviceFollowModeDisplayLabels[mode] ?? mode;
  }
}
