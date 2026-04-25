// ignore_for_file: unused_element, unused_element_parameter

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/ai_task_summary.dart';
import '../../models/capture_record.dart';
import '../../models/device_health_summary.dart';
import '../../models/device_link_result.dart';
import '../../models/device_status_summary.dart';
import '../../models/device_template_summary.dart';
import '../../models/template_summary.dart';
import '../../services/api_client.dart';
import '../../services/app_config.dart';
import '../../services/device_api_service.dart';
import '../../services/device_webrtc_service.dart';
import '../../services/mobile_api_service.dart';
import '../template/template_photo_dialog.dart';

class DeviceLinkPage extends StatefulWidget {
  const DeviceLinkPage({
    super.key,
    required this.mobileApiService,
    required this.accessToken,
    this.initialDeviceApiBaseUrl,
    this.initialTemplate,
    this.initialSessionCode,
    this.entryLabel,
  });

  final MobileApiService mobileApiService;
  final String accessToken;
  final String? initialDeviceApiBaseUrl;
  final TemplateSummary? initialTemplate;
  final String? initialSessionCode;
  final String? entryLabel;

  @override
  State<DeviceLinkPage> createState() => _DeviceLinkPageState();
}

enum _DeviceHudPanel { control, mode, ai, device }

class _DeviceLinkPageState extends State<DeviceLinkPage> {
  static const Map<DeviceOrientation, int> _cameraOrientations =
      <DeviceOrientation, int>{
        DeviceOrientation.portraitUp: 0,
        DeviceOrientation.landscapeLeft: 90,
        DeviceOrientation.portraitDown: 180,
        DeviceOrientation.landscapeRight: 270,
      };
  static const String _prefsBaseUrlKey = 'device_link.base_url';
  static const String _prefsStreamUrlKey = 'device_link.stream_url';
  static const String _prefsAutoRefreshKey = 'device_link.auto_refresh';
  static const String _prefsLandscapeControlsLeftKey =
      'device_link.landscape_controls_left';
  static const String _prefsJoystickSensitivityKey =
      'device_link.joystick_sensitivity';
  static const String _prefsJoystickVisibleKey = 'device_link.joystick_visible';
  static const String _prefsRecentConnectionsKey =
      'device_link.recent_connections';
  static const String _mobilePushStreamUrl = 'mobile_push';
  static const Duration _mobilePushFrameThrottle = Duration(milliseconds: 50);
  static const Duration _manualMoveRepeatInterval = Duration(milliseconds: 110);
  static const Duration _mobilePushSocketTimeout = Duration(seconds: 8);
  static const List<String> _modes = <String>[
    'MANUAL',
    'AUTO_TRACK',
    'SMART_COMPOSE',
  ];
  static const List<String> _followModes = <String>['shoulders', 'face'];

  final DeviceApiService _deviceApiService = const DeviceApiService();
  final DeviceWebRtcService _deviceWebRtcService = const DeviceWebRtcService();
  late final TextEditingController _baseUrlController;
  late final TextEditingController _streamUrlController;
  late final TextEditingController _sessionCodeController;

  List<TemplateSummary> _templates = const <TemplateSummary>[];
  List<DeviceTemplateSummary> _deviceTemplates =
      const <DeviceTemplateSummary>[];
  TemplateSummary? _selectedTemplate;
  DeviceTemplateSummary? _selectedDeviceTemplate;
  DeviceHealthSummary? _health;
  DeviceStatusSummary? _status;

  bool _isBusy = false;
  bool _isLoadingTemplates = false;
  bool _isLoadingDeviceTemplates = false;
  bool _isUploadingDeviceTemplate = false;
  bool _isDeletingDeviceTemplate = false;
  bool _isCreatingDemoTemplate = false;
  bool _isDeletingTemplate = false;
  bool _autoRefreshEnabled = true;
  bool _isHudHidden = false;
  bool _landscapeControlsOnLeft = false;
  bool _isJoystickVisible = true;
  bool _analyzeCaptureAfterShot = false;
  double _joystickSensitivity = 1.0;
  String? _errorMessage;
  String? _syncMessage;
  String? _diagnosticMessage;
  String? _lastCapturePath;
  AiTaskSummary? _lastBackendAiTask;
  DateTime? _lastStatusUpdatedAt;
  Timer? _pollTimer;
  Timer? _persistTimer;
  Timer? _manualMoveRepeatTimer;
  Timer? _hudMessageTimer;
  String? _hudMessageTimerKey;
  bool _isManualMoveSending = false;
  String? _activeManualMoveAction;
  Offset? _activeManualMoveVector;
  WebSocket? _previewSocket;
  Uint8List? _latestPreviewFrameBytes;
  DateTime? _latestPreviewFrameAt;
  String? _previewStreamErrorMessage;
  _DeviceHudPanel? _activeHudPanel = _DeviceHudPanel.control;
  Offset _joystickAnchor = const Offset(0.5, 0.72);
  Offset _joystickVector = Offset.zero;
  bool _hasCustomJoystickAnchor = false;
  WebSocket? _mobilePushSocket;
  DeviceWebRtcSession? _webRtcSession;
  CameraController? _mobilePushCameraController;
  CameraDescription? _mobilePushCamera;
  List<CameraDescription> _mobilePushCameras = const <CameraDescription>[];
  CameraLensDirection _mobilePushLensDirection = CameraLensDirection.back;
  int _mobilePushRotationDegrees = -1;
  bool _isMobilePushEnabled = false;
  bool _isStartingMobilePush = false;
  bool _isPushingMobileFrame = false;
  bool _isSavingDeviceCapture = false;
  bool _isHandlingMobilePushOrientationChange = false;
  bool _mobilePushConfigSent = false;
  int _mobilePushFrameCount = 0;
  int _lastMobilePushFrameSentAtMs = 0;
  int _lastMobilePushUiUpdateAtMs = 0;
  DateTime? _lastMobilePushFrameAt;
  String? _mobilePushErrorMessage;
  Orientation? _lastScreenOrientation;
  final List<_DeviceActionRecord> _actionRecords = <_DeviceActionRecord>[];
  final List<_DeviceCaptureRecord> _captureRecords = <_DeviceCaptureRecord>[];
  List<_DeviceConnectionPreset> _recentConnections =
      const <_DeviceConnectionPreset>[];

  @override
  void initState() {
    super.initState();
    _baseUrlController = TextEditingController(
      text: widget.initialDeviceApiBaseUrl ?? AppConfig.deviceApiBaseUrl,
    );
    _streamUrlController = TextEditingController(text: _mobilePushStreamUrl);
    _sessionCodeController = TextEditingController(
      text: widget.initialSessionCode ?? _buildSessionCode(),
    );
    _baseUrlController.addListener(_scheduleDraftPersist);
    _streamUrlController.addListener(_scheduleDraftPersist);
    _loadTemplates();
    _loadDeviceTemplates(silent: true);
    _loadPersistedConfig();
    _restartPolling();
  }

  @override
  void dispose() {
    unawaited(_stopMobilePush(silent: true));
    unawaited(_stopPreviewStream());
    _stopManualMoveRepeat(refreshStatus: false);
    _pollTimer?.cancel();
    _persistTimer?.cancel();
    _hudMessageTimer?.cancel();
    _baseUrlController.removeListener(_scheduleDraftPersist);
    _streamUrlController.removeListener(_scheduleDraftPersist);
    _baseUrlController.dispose();
    _streamUrlController.dispose();
    _sessionCodeController.dispose();
    super.dispose();
  }

  String? _currentHudMessageKey() {
    if (_errorMessage != null) {
      return 'error:$_errorMessage';
    }
    if (_previewStreamErrorMessage != null) {
      return 'preview:$_previewStreamErrorMessage';
    }
    if (_syncMessage != null) {
      return 'sync:$_syncMessage';
    }
    return null;
  }

  void _scheduleHudMessageDismiss(String messageKey) {
    if (_hudMessageTimerKey == messageKey &&
        _hudMessageTimer?.isActive == true) {
      return;
    }
    _hudMessageTimer?.cancel();
    _hudMessageTimerKey = messageKey;
    _hudMessageTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted || _currentHudMessageKey() != messageKey) {
        return;
      }
      setState(() {
        _errorMessage = null;
        _previewStreamErrorMessage = null;
        _syncMessage = null;
        _hudMessageTimerKey = null;
      });
    });
  }

  Future<void> _runAction(
    Future<void> Function() action, {
    String? successMessage,
  }) async {
    setState(() {
      _isBusy = true;
      _errorMessage = null;
      _syncMessage = null;
    });

    try {
      await action();
      if (!mounted) {
        return;
      }
      setState(() {
        _syncMessage = successMessage;
        if (successMessage != null) {
          _addActionRecord('system', successMessage);
        }
      });
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = error.message;
        _addActionRecord('error', error.message);
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = '设备请求失败，请检查地址、网络和本地运行时服务。';
        _addActionRecord('error', '设备请求失败，请检查地址、网络和本地运行时服务。');
      });
    } finally {
      if (mounted) {
        setState(() {
          _isBusy = false;
        });
      }
    }
  }

  Future<void> _loadTemplates() async {
    setState(() {
      _isLoadingTemplates = true;
      _errorMessage = null;
    });

    try {
      final templates = await widget.mobileApiService.listTemplates(
        accessToken: widget.accessToken,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _templates = templates;
        _selectedTemplate = _resolveInitialTemplate(templates);
        _isLoadingTemplates = false;
        if (widget.entryLabel != null) {
          _syncMessage = '已从 ${widget.entryLabel} 进入设备联动页。';
        }
      });
    } on ApiException catch (error) {
      final cachedTemplates = await widget.mobileApiService
          .getCachedTemplates();
      if (!mounted) {
        return;
      }
      if (cachedTemplates.isNotEmpty) {
        setState(() {
          _templates = cachedTemplates;
          _selectedTemplate = _resolveInitialTemplate(cachedTemplates);
          _syncMessage = '模板请求失败，已显示本地缓存模板。';
          _isLoadingTemplates = false;
        });
        return;
      }
      setState(() {
        _errorMessage = error.message;
        _isLoadingTemplates = false;
      });
    } catch (_) {
      final cachedTemplates = await widget.mobileApiService
          .getCachedTemplates();
      if (!mounted) {
        return;
      }
      if (cachedTemplates.isNotEmpty) {
        setState(() {
          _templates = cachedTemplates;
          _selectedTemplate = _resolveInitialTemplate(cachedTemplates);
          _syncMessage = '模板接口当前不可用，已显示缓存内容。';
          _isLoadingTemplates = false;
        });
        return;
      }
      setState(() {
        _errorMessage = '模板加载失败。';
        _isLoadingTemplates = false;
      });
    }
  }

  Future<void> _loadDeviceTemplates({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _isLoadingDeviceTemplates = true;
        _errorMessage = null;
      });
    } else if (mounted) {
      setState(() {
        _isLoadingDeviceTemplates = true;
      });
    }

    try {
      final templates = await _deviceApiService.listDeviceTemplates(
        baseUrl: _baseUrlController.text,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _deviceTemplates = templates;
        _selectedDeviceTemplate = _resolveDeviceTemplateSelection(templates);
        _isLoadingDeviceTemplates = false;
      });
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        if (!silent) {
          _errorMessage = error.message;
        }
        _isLoadingDeviceTemplates = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        if (!silent) {
          _errorMessage = '树莓派模板列表加载失败。';
        }
        _isLoadingDeviceTemplates = false;
      });
    }
  }

  DeviceTemplateSummary? _resolveDeviceTemplateSelection(
    List<DeviceTemplateSummary> templates,
  ) {
    if (templates.isEmpty) {
      return null;
    }
    final selectedId = _status?.selectedTemplateId;
    for (final template in templates) {
      if (template.selected || template.id == selectedId) {
        return template;
      }
    }
    if (_selectedDeviceTemplate != null) {
      for (final template in templates) {
        if (template.id == _selectedDeviceTemplate!.id) {
          return template;
        }
      }
    }
    return null;
  }

  Future<void> _createDemoTemplate() async {
    if (_isCreatingDemoTemplate) {
      return;
    }

    setState(() {
      _isCreatingDemoTemplate = true;
      _errorMessage = null;
    });

    try {
      final template = await widget.mobileApiService.createTemplate(
        accessToken: widget.accessToken,
        name: '设备联动示例模板',
        templateData: <String, dynamic>{
          'bbox_norm': <double>[0.32, 0.12, 0.34, 0.70],
          'pose_points': <String, List<double>>{
            'head': <double>[0.49, 0.16],
            'left_shoulder': <double>[0.43, 0.28],
            'right_shoulder': <double>[0.55, 0.28],
            'left_hip': <double>[0.44, 0.58],
            'right_hip': <double>[0.54, 0.58],
          },
        },
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _templates = <TemplateSummary>[template, ..._templates];
        _selectedTemplate = template;
        _syncMessage = '已创建并选中示例模板。';
      });
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = error.message;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = '示例模板创建失败。';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isCreatingDemoTemplate = false;
        });
      }
    }
  }

  Future<void> _createTemplate() async {
    if (_isCreatingDemoTemplate) {
      return;
    }

    final draft = await showTemplatePhotoDialog(context, title: '新增模板');
    if (!mounted || draft == null) {
      return;
    }

    setState(() {
      _isCreatingDemoTemplate = true;
      _errorMessage = null;
    });

    try {
      final template = await widget.mobileApiService.createTemplateFromPhoto(
        accessToken: widget.accessToken,
        name: draft.name,
        filePath: draft.filePath,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _templates = <TemplateSummary>[
          template,
          ..._templates.where((item) => item.id != template.id),
        ];
        _selectedTemplate = template;
        _syncMessage = '已新增模板并选中${template.name}';
      });
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = error.message;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = '模板创建失败。';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isCreatingDemoTemplate = false;
        });
      }
    }
  }

  Future<void> _uploadDeviceTemplate() async {
    if (_isUploadingDeviceTemplate) {
      return;
    }
    final draft = await showTemplatePhotoDialog(context, title: '上传树莓派模板');
    if (!mounted || draft == null) {
      return;
    }

    setState(() {
      _isUploadingDeviceTemplate = true;
      _errorMessage = null;
    });

    try {
      final template = await _deviceApiService.uploadDeviceTemplate(
        baseUrl: _baseUrlController.text,
        file: File(draft.filePath),
        name: draft.name,
      );
      await _refreshStatusSilently();
      final templates = await _deviceApiService.listDeviceTemplates(
        baseUrl: _baseUrlController.text,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _deviceTemplates = templates;
        _selectedDeviceTemplate = templates.firstWhere(
          (item) => item.id == template.id,
          orElse: () => template,
        );
        _syncMessage = '模板已上传到树莓派：${template.name}';
      });
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = error.message;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = '树莓派模板上传失败。';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isUploadingDeviceTemplate = false;
        });
      }
    }
  }

  Future<void> _deleteSelectedDeviceTemplate() async {
    final template = _selectedDeviceTemplate;
    if (template == null || _isDeletingDeviceTemplate) {
      return;
    }
    final confirmed = await _confirmAction(
      title: '删除树莓派模板',
      message: '确认删除树莓派模板“${template.name}”吗？删除后需要重新上传图片生成。',
      confirmLabel: '删除',
    );
    if (confirmed != true || !mounted) {
      return;
    }

    setState(() {
      _isDeletingDeviceTemplate = true;
      _errorMessage = null;
    });
    try {
      await _deviceApiService.deleteDeviceTemplate(
        baseUrl: _baseUrlController.text,
        templateId: template.id,
      );
      await _loadDeviceTemplates(silent: true);
      if (!mounted) {
        return;
      }
      setState(() {
        _selectedDeviceTemplate = null;
        _syncMessage = '树莓派模板已删除。';
      });
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = error.message;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = '树莓派模板删除失败。';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isDeletingDeviceTemplate = false;
        });
      }
    }
  }

  Future<void> _deleteSelectedTemplate() async {
    final template = _selectedTemplate;
    if (template == null || _isDeletingTemplate) {
      return;
    }
    if (template.isRecommendedDefault) {
      setState(() {
        _syncMessage = '后台推荐模板不能在手机端删除，如需调整请到管理后台维护。';
      });
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除模板'),
        content: Text('确认删除模板“${template.name}”吗？删除后将无法继续在设备联动页选择它。'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) {
      return;
    }

    setState(() {
      _isDeletingTemplate = true;
      _errorMessage = null;
    });

    try {
      await widget.mobileApiService.deleteTemplate(
        accessToken: widget.accessToken,
        templateId: template.id,
      );
      if (!mounted) {
        return;
      }

      final nextTemplates = _templates
          .where((item) => item.id != template.id)
          .toList(growable: false);
      setState(() {
        _templates = nextTemplates;
        _selectedTemplate = _resolveInitialTemplate(nextTemplates);
        _syncMessage = '已删除模板：${template.name}';
      });
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = error.message;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = '模板删除失败。';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isDeletingTemplate = false;
        });
      }
    }
  }

  Future<bool?> _confirmAction({
    required String title,
    required String message,
    String confirmLabel = '确认',
  }) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
  }

  Future<void> _checkHealth() async {
    await _runAction(() async {
      final health = await _deviceApiService.getHealth(
        baseUrl: _baseUrlController.text,
      );
      setState(() {
        _health = health;
      });
    }, successMessage: '健康检查完成。');
  }

  Future<void> _runConnectionDiagnostics() async {
    await _runAction(() async {
      final lines = <String>[];
      try {
        final health = await _deviceApiService.getHealth(
          baseUrl: _baseUrlController.text,
        );
        lines.add('Health: ${health.status}');
        _health = health;
      } catch (error) {
        lines.add('Health: 失败');
      }

      try {
        final status = await _deviceApiService.getStatus(
          baseUrl: _baseUrlController.text,
        );
        lines.add('Session: ${status.sessionOpened ? '已打开' : '未打开'}');
        _status = status;
        _lastStatusUpdatedAt = DateTime.now();
      } catch (_) {
        lines.add('Session: 未打开或不可访问');
      }

      try {
        await _deviceApiService.getAiStatus(baseUrl: _baseUrlController.text);
        lines.add('AI: 可访问');
      } catch (_) {
        lines.add('AI: 会话未打开或不可访问');
      }

      lines.add(
        _streamUrlController.text.trim().isEmpty
            ? 'Stream: 未填写'
            : 'Stream: ${_streamUrlController.text.trim()}',
      );

      if (_status?.sessionOpened == true) {
        try {
          final client = HttpClient();
          final request = await client
              .getUrl(Uri.parse(_buildPreviewUrl()))
              .timeout(const Duration(seconds: 4));
          final response = await request.close().timeout(
            const Duration(seconds: 4),
          );
          lines.add('Preview: HTTP ${response.statusCode}');
          client.close(force: true);
        } catch (_) {
          lines.add('Preview: 失败');
        }
      } else {
        lines.add('Preview: 需要先打开会话');
      }

      setState(() {
        _diagnosticMessage = lines.join(' · ');
        _syncMessage = '连接诊断完成。';
      });
    });
  }

  Future<void> _fetchStatus() async {
    await _runAction(() async {
      final status = await _deviceApiService.getStatus(
        baseUrl: _baseUrlController.text,
      );
      setState(() {
        _status = status;
        _lastStatusUpdatedAt = DateTime.now();
      });
    }, successMessage: '设备状态已刷新。');
  }

  Future<void> _setOverlayOption(String key, bool value) async {
    if (_status?.sessionOpened != true) {
      setState(() {
        _errorMessage = '请先打开设备会话，再调整画面辅助显示。';
      });
      return;
    }
    await _runAction(() async {
      final status = await _deviceApiService.updateDeviceConfig(
        baseUrl: _baseUrlController.text,
        overlay: <String, bool>{key: value},
      );
      setState(() {
        _status = status;
        _lastStatusUpdatedAt = DateTime.now();
      });
    }, successMessage: '画面辅助显示已更新。');
  }

  Future<void> _setGestureOption(String key, bool value) async {
    if (_status?.sessionOpened != true) {
      setState(() {
        _errorMessage = '请先打开设备会话，再调整手势抓拍。';
      });
      return;
    }
    await _runAction(() async {
      final status = await _deviceApiService.updateDeviceConfig(
        baseUrl: _baseUrlController.text,
        gesture: <String, bool>{key: value},
      );
      setState(() {
        _status = status;
        _lastStatusUpdatedAt = DateTime.now();
        if (key == 'auto_analyze_enabled') {
          _analyzeCaptureAfterShot = value;
        }
      });
    }, successMessage: '手势抓拍设置已更新。');
  }

  Future<void> _setCaptureAnalyzeAfterShot(bool value) async {
    setState(() {
      _analyzeCaptureAfterShot = value;
    });
    if (_status?.sessionOpened == true) {
      await _setGestureOption('auto_analyze_enabled', value);
    }
  }

  Future<void> _openSession() async {
    await _runAction(() async {
      await _stopPreviewStream();
      final status = await _deviceApiService.openSession(
        baseUrl: _baseUrlController.text,
        sessionCode: _sessionCodeController.text.trim(),
        streamUrl: _streamUrlController.text.trim(),
      );
      setState(() {
        _status = status;
        _lastStatusUpdatedAt = DateTime.now();
        _latestPreviewFrameBytes = null;
        _latestPreviewFrameAt = null;
        _previewStreamErrorMessage = null;
      });
      unawaited(_startPreviewStream());
      await _rememberCurrentConnection();
      await _refreshStatusSilently();
      if (_analyzeCaptureAfterShot) {
        final updatedStatus = await _deviceApiService.updateDeviceConfig(
          baseUrl: _baseUrlController.text,
          gesture: const <String, bool>{'auto_analyze_enabled': true},
        );
        setState(() {
          _status = updatedStatus;
          _lastStatusUpdatedAt = DateTime.now();
        });
      }
      await _refreshHealthSilently();
      await _loadDeviceTemplates(silent: true);
    }, successMessage: '设备会话已打开。');
  }

  Future<void> _closeSession() async {
    final confirmed = await _confirmAction(
      title: '关闭设备会话',
      message: '关闭后会停止预览、推流和设备控制，确认关闭吗？',
      confirmLabel: '关闭',
    );
    if (confirmed != true || !mounted) {
      return;
    }
    await _runAction(() async {
      await _stopMobilePush(silent: true);
      await _stopPreviewStream();
      await _deviceApiService.closeSession(
        baseUrl: _baseUrlController.text,
        sessionCode: _status?.sessionCode ?? _sessionCodeController.text.trim(),
      );
      setState(() {
        _status = null;
        _latestPreviewFrameBytes = null;
        _latestPreviewFrameAt = null;
        _previewStreamErrorMessage = null;
        _lastCapturePath = null;
        _lastBackendAiTask = null;
        _lastStatusUpdatedAt = null;
        _sessionCodeController.text = _buildSessionCode();
      });
      await _refreshHealthSilently();
    }, successMessage: '设备会话已关闭。');
  }

  Future<void> _restartDeviceStream() async {
    if (_status?.sessionOpened != true) {
      setState(() {
        _errorMessage = '请先打开设备会话，再切换视频流。';
      });
      return;
    }
    final confirmed = await _confirmAction(
      title: '切换视频流',
      message: '切换视频流会短暂中断预览，确认切换到当前填写的视频流地址吗？',
      confirmLabel: '切换',
    );
    if (confirmed != true || !mounted) {
      return;
    }
    await _runAction(() async {
      await _stopPreviewStream();
      final status = await _deviceApiService.restartStream(
        baseUrl: _baseUrlController.text,
        streamUrl: _streamUrlController.text.trim(),
      );
      setState(() {
        _status = status;
        _lastStatusUpdatedAt = DateTime.now();
        _latestPreviewFrameBytes = null;
        _previewStreamErrorMessage = null;
      });
      unawaited(_startPreviewStream());
      await _rememberCurrentConnection();
    }, successMessage: '视频流已切换。');
  }

  Future<void> _startMobilePush() async {
    if (_isStartingMobilePush || _isMobilePushEnabled) {
      return;
    }

    await _runAction(() async {
      setState(() {
        _isStartingMobilePush = true;
        _mobilePushErrorMessage = null;
      });

      try {
        try {
          await _startMobilePushWebRtc();
        } catch (error) {
          await _stopWebRtcSession();
          await _startLegacyMobilePush();
          if (mounted) {
            setState(() {
              _mobilePushErrorMessage =
                  'WebRTC 启动失败，已切换到 WebSocket/JPEG fallback：$error';
            });
          }
        }
      } catch (_) {
        await _stopMobilePush(silent: true);
        rethrow;
      } finally {
        if (mounted) {
          setState(() {
            _isStartingMobilePush = false;
          });
        }
      }
    });
  }

  Future<void> _startMobilePushWebRtc() async {
    final camera = await _preferredMobilePushCamera();
    await _stopPreviewStream();
    _streamUrlController.text = _mobilePushStreamUrl;
    final status = await _deviceApiService.openSession(
      baseUrl: _baseUrlController.text,
      sessionCode: _sessionCodeController.text.trim(),
      streamUrl: _mobilePushStreamUrl,
    );
    final session = await _deviceWebRtcService.start(
      baseUrl: _baseUrlController.text,
      lensDirection: camera.lensDirection,
      onConnectionState: (RTCPeerConnectionState state) {
        if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
            state ==
                RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
          _setMobilePushError('WebRTC 连接已断开，请检查设备运行时服务和局域网连接。');
        }
      },
    );
    if (!mounted) {
      await session.dispose();
      return;
    }
    setState(() {
      _status = status;
      _lastStatusUpdatedAt = DateTime.now();
      _webRtcSession = session;
      _mobilePushCamera = camera;
      _mobilePushLensDirection = camera.lensDirection;
      _isMobilePushEnabled = true;
      _mobilePushFrameCount = 0;
      _lastMobilePushFrameSentAtMs = 0;
      _lastMobilePushUiUpdateAtMs = 0;
      _lastMobilePushFrameAt = DateTime.now();
      _latestPreviewFrameBytes = null;
      _latestPreviewFrameAt = DateTime.now();
      _syncMessage = '手机画面 WebRTC 推流已启动。';
      _addActionRecord('system', '手机画面 WebRTC 推流已启动。');
    });
    await _rememberCurrentConnection();
  }

  Future<void> _startLegacyMobilePush() async {
    if (!Platform.isAndroid) {
      throw const ApiException('手机 WebSocket fallback 目前仅支持 Android。');
    }
    final camera = await _preferredMobilePushCamera();
    _mobilePushCamera = camera;
    _mobilePushLensDirection = camera.lensDirection;
    _mobilePushRotationDegrees = -1;
    final controller = CameraController(
      camera,
      ResolutionPreset.low,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.nv21,
    );
    await controller.initialize();
    _mobilePushCameraController = controller;

    _streamUrlController.text = _mobilePushStreamUrl;
    final status = await _deviceApiService.openSession(
      baseUrl: _baseUrlController.text,
      sessionCode: _sessionCodeController.text.trim(),
      streamUrl: _mobilePushStreamUrl,
    );
    setState(() {
      _status = status;
      _lastStatusUpdatedAt = DateTime.now();
      _isMobilePushEnabled = true;
      _mobilePushFrameCount = 0;
      _lastMobilePushFrameSentAtMs = 0;
      _lastMobilePushUiUpdateAtMs = 0;
      _lastMobilePushFrameAt = null;
    });
    await _rememberCurrentConnection();
    unawaited(_startPreviewStream());
    _mobilePushSocket = await WebSocket.connect(
      _buildDeviceWebSocketUri('/api/device/stream/mobile-ws').toString(),
    ).timeout(_mobilePushSocketTimeout);
    _mobilePushSocket!.listen(
      (_) {},
      onError: (_) {
        if (_isMobilePushEnabled) {
          _setMobilePushError('手机 WebSocket 推流连接出错，请检查设备运行时地址。');
        }
      },
      onDone: () {
        if (_isMobilePushEnabled) {
          _setMobilePushError('手机 WebSocket 推流连接已关闭。');
        }
      },
      cancelOnError: false,
    );
    await controller.startImageStream(_handleMobilePushFrame);
  }

  Future<CameraDescription> _preferredMobilePushCamera() async {
    if (_mobilePushCameras.isEmpty) {
      _mobilePushCameras = await availableCameras();
    }
    if (_mobilePushCameras.isEmpty) {
      throw const ApiException('没有找到可用摄像头，请检查系统权限。');
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

  Future<void> _switchMobilePushCamera() async {
    if (_isStartingMobilePush || _isHandlingMobilePushOrientationChange) {
      return;
    }

    if (_webRtcSession != null) {
      final currentDirection =
          _mobilePushCamera?.lensDirection ?? _mobilePushLensDirection;
      _mobilePushLensDirection = currentDirection == CameraLensDirection.front
          ? CameraLensDirection.back
          : CameraLensDirection.front;
      await _runAction(() async {
        setState(() {
          _isStartingMobilePush = true;
          _mobilePushErrorMessage = null;
        });
        try {
          await _stopMobilePush(silent: true);
          await _startMobilePushWebRtc();
        } finally {
          if (mounted) {
            setState(() {
              _isStartingMobilePush = false;
            });
          }
        }
      });
      return;
    }

    await _runAction(() async {
      setState(() {
        _isStartingMobilePush = true;
        _mobilePushErrorMessage = null;
      });

      try {
        if (!Platform.isAndroid) {
          throw const ApiException('旧版手机推流切换摄像头仅支持 Android 真机。');
        }
        if (_mobilePushCameras.isEmpty) {
          _mobilePushCameras = await availableCameras();
        }
        if (_mobilePushCameras.length < 2) {
          throw const ApiException('当前设备没有检测到可切换的第二个摄像头。');
        }

        final currentDirection =
            _mobilePushCamera?.lensDirection ?? _mobilePushLensDirection;
        final targetDirection = currentDirection == CameraLensDirection.front
            ? CameraLensDirection.back
            : CameraLensDirection.front;
        CameraDescription? targetCamera = _findMobilePushCamera(
          targetDirection,
        );
        if (targetCamera == null) {
          for (final camera in _mobilePushCameras) {
            if (camera.lensDirection != currentDirection) {
              targetCamera = camera;
              break;
            }
          }
        }
        if (targetCamera == null ||
            targetCamera.lensDirection == currentDirection) {
          throw const ApiException('没有找到可切换的摄像头。');
        }
        final selectedCamera = targetCamera;

        if (!_isMobilePushEnabled) {
          setState(() {
            _mobilePushCamera = selectedCamera;
            _mobilePushLensDirection = selectedCamera.lensDirection;
          });
          return;
        }

        _isPushingMobileFrame = true;
        final currentController = _mobilePushCameraController;
        _mobilePushCameraController = null;
        if (currentController != null) {
          if (currentController.value.isStreamingImages) {
            await currentController.stopImageStream();
          }
          await currentController.dispose();
        }

        final nextController = CameraController(
          selectedCamera,
          ResolutionPreset.low,
          enableAudio: false,
          imageFormatGroup: ImageFormatGroup.nv21,
        );
        await nextController.initialize();
        if (!_isMobilePushEnabled) {
          await nextController.dispose();
          return;
        }

        _mobilePushCameraController = nextController;
        _mobilePushCamera = selectedCamera;
        _mobilePushLensDirection = selectedCamera.lensDirection;
        _mobilePushRotationDegrees = -1;
        _mobilePushConfigSent = false;
        _lastMobilePushFrameSentAtMs = 0;
        _lastMobilePushUiUpdateAtMs = 0;
        _latestPreviewFrameBytes = null;
        await nextController.startImageStream(_handleMobilePushFrame);
        unawaited(_startPreviewStream());
      } catch (_) {
        if (_isMobilePushEnabled && _mobilePushCameraController == null) {
          await _stopMobilePush(silent: true);
        }
        rethrow;
      } finally {
        _isPushingMobileFrame = false;
        if (mounted) {
          setState(() {
            _isStartingMobilePush = false;
          });
        }
      }
    }, successMessage: '手机画面推送已启动。');
  }

  Future<void> _stopMobilePush({bool silent = false}) async {
    _isMobilePushEnabled = false;
    _isPushingMobileFrame = false;
    _isHandlingMobilePushOrientationChange = false;
    _mobilePushConfigSent = false;
    _mobilePushCamera = null;
    _mobilePushRotationDegrees = -1;
    _lastMobilePushFrameSentAtMs = 0;
    _lastMobilePushUiUpdateAtMs = 0;

    await _stopWebRtcSession();

    final socket = _mobilePushSocket;
    _mobilePushSocket = null;
    if (socket != null) {
      try {
        await socket.close();
      } catch (_) {
        // Ignore socket shutdown errors while leaving the page.
      }
    }

    final controller = _mobilePushCameraController;
    _mobilePushCameraController = null;
    if (controller != null) {
      try {
        if (controller.value.isStreamingImages) {
          await controller.stopImageStream();
        }
        await controller.dispose();
      } catch (_) {
        // Ignore camera shutdown errors while leaving the page.
      }
    }

    if (!silent && mounted) {
      setState(() {
        _syncMessage = '手机画面推送已停止。';
        _addActionRecord('system', '手机画面推送已停止。');
      });
    }
  }

  Future<void> _stopWebRtcSession() async {
    final session = _webRtcSession;
    _webRtcSession = null;
    if (session == null) {
      return;
    }
    try {
      await session.dispose();
    } catch (_) {
      // Ignore WebRTC shutdown errors while leaving the page.
    }
  }

  void _syncScreenOrientation(Orientation orientation) {
    final previousOrientation = _lastScreenOrientation;
    _lastScreenOrientation = orientation;
    if (previousOrientation == null || previousOrientation == orientation) {
      return;
    }
    if (!_isMobilePushEnabled ||
        _webRtcSession != null ||
        _isStartingMobilePush ||
        _isHandlingMobilePushOrientationChange) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _isHandlingMobilePushOrientationChange) {
        return;
      }
      unawaited(_reinitializeMobilePushForOrientationChange());
    });
  }

  Future<void> _reinitializeMobilePushForOrientationChange() async {
    final camera = _mobilePushCamera;
    final currentController = _mobilePushCameraController;
    if (!_isMobilePushEnabled || camera == null || currentController == null) {
      _mobilePushConfigSent = false;
      _mobilePushRotationDegrees = -1;
      return;
    }

    _isHandlingMobilePushOrientationChange = true;
    _isPushingMobileFrame = false;
    if (mounted) {
      setState(() {
        _mobilePushErrorMessage = null;
        _syncMessage = '屏幕方向变化，正在重新校正手机推流画面。';
        _latestPreviewFrameBytes = null;
      });
    }

    try {
      if (currentController.value.isStreamingImages) {
        await currentController.stopImageStream();
      }
      await currentController.dispose();

      final nextController = CameraController(
        camera,
        ResolutionPreset.low,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.nv21,
      );
      await nextController.initialize();
      if (!_isMobilePushEnabled) {
        await nextController.dispose();
        return;
      }

      _mobilePushCameraController = nextController;
      _mobilePushRotationDegrees = -1;
      _mobilePushConfigSent = false;
      await nextController.startImageStream(_handleMobilePushFrame);
      unawaited(_startPreviewStream());

      if (mounted) {
        setState(() {
          _syncMessage = '推流画面方向已校正。';
        });
      }
    } catch (_) {
      if (mounted && _isMobilePushEnabled) {
        _setMobilePushError('屏幕方向变化后重新初始化推流失败，请停止后再启动。');
      }
    } finally {
      _isHandlingMobilePushOrientationChange = false;
    }
  }

  void _handleMobilePushFrame(CameraImage image) {
    final socket = _mobilePushSocket;
    if (!_isMobilePushEnabled ||
        _isPushingMobileFrame ||
        socket == null ||
        socket.readyState != WebSocket.open ||
        image.planes.isEmpty) {
      return;
    }

    final nowMs = DateTime.now().millisecondsSinceEpoch;
    if (nowMs - _lastMobilePushFrameSentAtMs <
        _mobilePushFrameThrottle.inMilliseconds) {
      return;
    }

    try {
      _isPushingMobileFrame = true;
      final rotationDegrees = _mobilePushRotationForCurrentFrame();
      if (!_mobilePushConfigSent ||
          rotationDegrees != _mobilePushRotationDegrees) {
        socket.add(
          jsonEncode(<String, dynamic>{
            'type': 'config',
            'format': 'nv21',
            'width': image.width,
            'height': image.height,
            'rotation_degrees': rotationDegrees,
          }),
        );
        _mobilePushRotationDegrees = rotationDegrees;
        _mobilePushConfigSent = true;
      }
      final frameBytes = _encodeCameraImageAsNv21(image);
      if (frameBytes == null) {
        _setMobilePushError('当前相机格式暂不支持旧版推流，请使用 Android NV21 摄像头格式。');
        return;
      }
      socket.add(frameBytes);
      _lastMobilePushFrameSentAtMs = nowMs;
      _mobilePushFrameCount += 1;

      final shouldUpdateUi =
          nowMs - _lastMobilePushUiUpdateAtMs >=
          const Duration(milliseconds: 300).inMilliseconds;
      if (mounted && shouldUpdateUi) {
        setState(() {
          _lastMobilePushFrameAt = DateTime.now();
          _lastMobilePushUiUpdateAtMs = nowMs;
          _mobilePushErrorMessage = null;
        });
      }
    } on ApiException catch (error) {
      _setMobilePushError(error.message);
    } catch (_) {
      _setMobilePushError('手机画面推送失败，请检查设备运行时地址和网络连接。');
    } finally {
      _isPushingMobileFrame = false;
    }
  }

  int _mobilePushRotationForCurrentFrame() {
    final controller = _mobilePushCameraController;
    final camera = _mobilePushCamera;
    if (controller == null || camera == null) {
      return _mobilePushRotationDegrees >= 0 ? _mobilePushRotationDegrees : 0;
    }
    final deviceOrientation =
        _cameraOrientations[controller.value.deviceOrientation] ?? 0;
    if (camera.lensDirection == CameraLensDirection.front) {
      return (camera.sensorOrientation + deviceOrientation) % 360;
    }
    return (camera.sensorOrientation - deviceOrientation + 360) % 360;
  }

  Uint8List? _encodeCameraImageAsNv21(CameraImage image) {
    final expectedSize = image.width * image.height * 3 ~/ 2;
    if (image.planes.length == 1 &&
        image.planes.first.bytes.length == expectedSize) {
      return image.planes.first.bytes;
    }
    if (image.planes.length < 3) {
      return null;
    }

    final yPlane = image.planes[0];
    final uPlane = image.planes[1];
    final vPlane = image.planes[2];
    final output = Uint8List(expectedSize);
    var offset = 0;

    for (var row = 0; row < image.height; row += 1) {
      final rowStart = row * yPlane.bytesPerRow;
      final yPixelStride = yPlane.bytesPerPixel ?? 1;
      if (yPixelStride == 1) {
        final rowEnd = rowStart + image.width;
        if (rowEnd > yPlane.bytes.length) {
          return null;
        }
        output.setRange(offset, offset + image.width, yPlane.bytes, rowStart);
        offset += image.width;
        continue;
      }
      for (var col = 0; col < image.width; col += 1) {
        final index = rowStart + col * yPixelStride;
        if (index >= yPlane.bytes.length) {
          return null;
        }
        output[offset] = yPlane.bytes[index];
        offset += 1;
      }
    }

    final uvWidth = image.width ~/ 2;
    final uvHeight = image.height ~/ 2;
    final uPixelStride = uPlane.bytesPerPixel ?? 1;
    final vPixelStride = vPlane.bytesPerPixel ?? 1;
    for (var row = 0; row < uvHeight; row += 1) {
      final uRowStart = row * uPlane.bytesPerRow;
      final vRowStart = row * vPlane.bytesPerRow;
      for (var col = 0; col < uvWidth; col += 1) {
        final uIndex = uRowStart + col * uPixelStride;
        final vIndex = vRowStart + col * vPixelStride;
        if (uIndex >= uPlane.bytes.length || vIndex >= vPlane.bytes.length) {
          return null;
        }
        output[offset] = vPlane.bytes[vIndex];
        output[offset + 1] = uPlane.bytes[uIndex];
        offset += 2;
      }
    }

    return output;
  }

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

  void _setMobilePushError(String message) {
    if (!mounted) {
      return;
    }
    setState(() {
      _mobilePushErrorMessage = message;
    });
  }

  Future<void> _startPreviewStream() async {
    if (_previewSocket != null || _status?.sessionOpened != true) {
      return;
    }

    try {
      final socket = await WebSocket.connect(
        _buildDeviceWebSocketUri('/api/device/preview-ws').toString(),
      ).timeout(_mobilePushSocketTimeout);
      _previewSocket = socket;
      socket.listen(
        (dynamic data) {
          if (!mounted || data is! List<int>) {
            return;
          }
          setState(() {
            _latestPreviewFrameBytes = Uint8List.fromList(data);
            _latestPreviewFrameAt = DateTime.now();
            _previewStreamErrorMessage = null;
          });
        },
        onError: (_) {
          _previewSocket = null;
          if (mounted) {
            setState(() {
              _previewStreamErrorMessage = '实时预览连接出错，请检查设备运行时地址。';
            });
          }
        },
        onDone: () {
          _previewSocket = null;
        },
        cancelOnError: false,
      );
    } catch (_) {
      _previewSocket = null;
      if (mounted) {
        setState(() {
          _previewStreamErrorMessage = '实时预览暂时不可用，请确认设备会话已打开。';
        });
      }
    }
  }

  Future<void> _stopPreviewStream() async {
    final socket = _previewSocket;
    _previewSocket = null;
    if (socket == null) {
      return;
    }
    try {
      await socket.close();
    } catch (_) {
      // Ignore preview socket shutdown errors while leaving the page.
    }
  }

  void _startManualMoveRepeat(String action) {
    if (_status?.sessionOpened != true || _isBusy) {
      return;
    }
    _activeManualMoveAction = action;
    _activeManualMoveVector = null;
    _manualMoveRepeatTimer?.cancel();
    unawaited(_sendManualMovePulse(action));
    _manualMoveRepeatTimer = Timer.periodic(_manualMoveRepeatInterval, (_) {
      if (_activeManualMoveAction != action) {
        return;
      }
      unawaited(_sendManualMovePulse(action));
    });
  }

  void _startJoystickMoveRepeat(Offset vector) {
    if (_status?.sessionOpened != true || _isBusy) {
      return;
    }
    _activeManualMoveAction = null;
    _activeManualMoveVector = vector;
    _manualMoveRepeatTimer ??= Timer.periodic(_manualMoveRepeatInterval, (_) {
      final activeVector = _activeManualMoveVector;
      if (activeVector == null || activeVector.distance < 0.08) {
        return;
      }
      unawaited(_sendManualMoveDelta(activeVector));
    });
    unawaited(_sendManualMoveDelta(vector));
  }

  void _stopManualMoveRepeat({bool refreshStatus = true}) {
    _activeManualMoveAction = null;
    _activeManualMoveVector = null;
    _manualMoveRepeatTimer?.cancel();
    _manualMoveRepeatTimer = null;
    if (mounted && _joystickVector != Offset.zero) {
      setState(() {
        _joystickVector = Offset.zero;
      });
    }
    if (refreshStatus) {
      unawaited(_refreshStatusAfterManualMove());
    }
  }

  void _toggleHudPanel(_DeviceHudPanel panel) {
    setState(() {
      _activeHudPanel = _activeHudPanel == panel ? null : panel;
    });
  }

  void _setLandscapeControlsSide(bool left) {
    setState(() {
      _landscapeControlsOnLeft = left;
      _hasCustomJoystickAnchor = false;
    });
    _scheduleDraftPersist();
  }

  void _setJoystickSensitivity(double value) {
    setState(() {
      _joystickSensitivity = value;
    });
    _scheduleDraftPersist();
  }

  void _setJoystickVisible(bool value) {
    if (!value) {
      _stopManualMoveRepeat(refreshStatus: false);
    }
    setState(() {
      _isJoystickVisible = value;
      if (value) {
        _hasCustomJoystickAnchor = false;
      }
    });
    _scheduleDraftPersist();
  }

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

  void _moveJoystickAnchor(DragUpdateDetails details, Size bounds) {
    final current = _effectiveJoystickAnchor(bounds.width > bounds.height);
    final next = Offset(
      current.dx + details.delta.dx / bounds.width,
      current.dy + details.delta.dy / bounds.height,
    );
    setState(() {
      _hasCustomJoystickAnchor = true;
      _joystickAnchor = Offset(
        next.dx.clamp(0.18, 0.82),
        next.dy.clamp(0.26, 0.76),
      );
    });
  }

  void _updateJoystickVector(Offset localPosition, double size) {
    final center = Offset(size / 2, size / 2);
    final maxRadius = size * 0.28;
    final raw = localPosition - center;
    final distance = raw.distance;
    final normalized = distance > maxRadius && distance > 0
        ? raw / distance
        : raw / maxRadius;
    final vector = distance > maxRadius ? normalized : normalized;
    final clampedVector = distance > maxRadius ? raw / distance : vector;
    final visualVector = distance > maxRadius ? clampedVector : vector;
    final clamped = Offset(
      visualVector.dx.clamp(-1.0, 1.0),
      visualVector.dy.clamp(-1.0, 1.0),
    );

    setState(() {
      _joystickVector = clamped;
    });

    if (clamped.distance < 0.16) {
      if (_activeManualMoveAction != null || _activeManualMoveVector != null) {
        _stopManualMoveRepeat(refreshStatus: false);
      }
      return;
    }
    _startJoystickMoveRepeat(clamped);
  }

  String? _manualMoveActionFromVector(Offset vector) {
    if (vector.distance < 0.22) {
      return null;
    }
    if (vector.dx.abs() > vector.dy.abs()) {
      return vector.dx > 0 ? 'right' : 'left';
    }
    return vector.dy > 0 ? 'down' : 'up';
  }

  void _endJoystickGesture() {
    _stopManualMoveRepeat();
  }

  Future<void> _refreshStatusAfterManualMove() async {
    try {
      await _refreshStatusSilently();
    } catch (_) {
      // Manual repeat should stop cleanly even if the status refresh is late.
    }
  }

  Future<void> _sendManualMovePulse(
    String action, {
    bool refreshStatus = false,
  }) async {
    if (_isManualMoveSending || _status?.sessionOpened != true) {
      return;
    }
    _isManualMoveSending = true;
    try {
      await _deviceApiService.sendManualMoveCommand(
        baseUrl: _baseUrlController.text,
        action: action,
      );
      if (refreshStatus) {
        await _refreshStatusSilently();
      }
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = error.message;
        _addActionRecord('error', error.message);
      });
      _stopManualMoveRepeat();
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = '云台控制失败，请检查设备连接。';
        _addActionRecord('error', '云台控制失败，请检查设备连接。');
      });
      _stopManualMoveRepeat();
    } finally {
      _isManualMoveSending = false;
    }
  }

  Future<void> _sendManualMoveDelta(Offset vector) async {
    if (_isManualMoveSending || _status?.sessionOpened != true) {
      return;
    }
    _isManualMoveSending = true;
    final step = _joystickSensitivity * 1.8;
    try {
      await _deviceApiService.sendManualMoveCommand(
        baseUrl: _baseUrlController.text,
        panDelta: vector.dx * step,
        tiltDelta: vector.dy * step,
      );
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = error.message;
        _addActionRecord('error', error.message);
      });
      _stopManualMoveRepeat();
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = '云台控制失败，请检查设备连接。';
        _addActionRecord('error', '云台控制失败，请检查设备连接。');
      });
      _stopManualMoveRepeat();
    } finally {
      _isManualMoveSending = false;
    }
  }

  Future<void> _setMode(String mode) async {
    await _runAction(() async {
      final status = await _deviceApiService.setMode(
        baseUrl: _baseUrlController.text,
        mode: mode,
      );
      setState(() {
        _status = status;
        _lastStatusUpdatedAt = DateTime.now();
      });
    }, successMessage: '模式已更新。');
  }

  Future<void> _home() async {
    await _runAction(() async {
      final status = await _deviceApiService.home(
        baseUrl: _baseUrlController.text,
      );
      setState(() {
        _status = status;
        _lastStatusUpdatedAt = DateTime.now();
      });
    }, successMessage: '云台已回中。');
  }

  Future<void> _setFollowMode(String followMode) async {
    await _runAction(() async {
      final status = await _deviceApiService.setFollowMode(
        baseUrl: _baseUrlController.text,
        followMode: followMode,
      );
      setState(() {
        _status = status;
        _lastStatusUpdatedAt = DateTime.now();
      });
    }, successMessage: '跟随模式已更新。');
  }

  Future<void> _pushTemplate() async {
    final deviceTemplate = _selectedDeviceTemplate;
    if (deviceTemplate != null) {
      await _runAction(() async {
        final status = await _deviceApiService.selectTemplate(
          baseUrl: _baseUrlController.text,
          templateId: deviceTemplate.id,
        );
        await _loadDeviceTemplates(silent: true);
        setState(() {
          _status = status;
          _lastStatusUpdatedAt = DateTime.now();
        });
      }, successMessage: '树莓派模板已选择${deviceTemplate.name}');
      return;
    }

    final template = _selectedTemplate;
    if (template == null) {
      setState(() {
        _errorMessage = _errorMessage = '请先选择模板，再下发到设备。';
      });
      return;
    }

    await _runAction(() async {
      final status = await _deviceApiService.selectTemplate(
        baseUrl: _baseUrlController.text,
        templateId: template.id,
        templateData: template.templateData,
      );
      setState(() {
        _status = status;
        _lastStatusUpdatedAt = DateTime.now();
      });
    }, successMessage: '模板已下发到设备。');
  }

  Future<void> _clearDeviceTemplateSelection() async {
    await _runAction(() async {
      final status = await _deviceApiService.clearTemplate(
        baseUrl: _baseUrlController.text,
      );
      await _loadDeviceTemplates(silent: true);
      setState(() {
        _status = status;
        _selectedDeviceTemplate = null;
        _selectedTemplate = null;
        _lastStatusUpdatedAt = DateTime.now();
      });
    }, successMessage: '模板构图已关闭。');
  }

  Future<void> _applyAngleSuggestion() async {
    await _runAction(() async {
      final status = await _deviceApiService.applyAngle(
        baseUrl: _baseUrlController.text,
        recommendedPanDelta: 4,
        recommendedTiltDelta: -1.5,
      );
      setState(() {
        _status = status;
        _lastStatusUpdatedAt = DateTime.now();
      });
    }, successMessage: 'AI 角度建议已应用。');
  }

  Future<void> _applyLockSuggestion() async {
    final targetBoxNorm = _resolveTargetBoxNorm();
    await _runAction(() async {
      final status = await _deviceApiService.applyLock(
        baseUrl: _baseUrlController.text,
        recommendedPanDelta: 2,
        recommendedTiltDelta: -1,
        targetBoxNorm: targetBoxNorm,
      );
      setState(() {
        _status = status;
        _lastStatusUpdatedAt = DateTime.now();
      });
    }, successMessage: 'AI 锁机位建议已应用。');
  }

  Future<void> _startAngleSearch() async {
    if (_status?.aiStatus.hasRunningTask == true) {
      setState(() {
        _syncMessage = _errorMessage = 'AI 任务正在运行，请等待当前任务完成。';
      });
      return;
    }
    final config = await _showAiScanConfigDialog(
      title: 'AI 自动找角度',
      includeDelay: false,
    );
    if (!mounted || config == null) {
      return;
    }
    await _runAction(() async {
      await _deviceApiService.startAngleSearch(
        baseUrl: _baseUrlController.text,
        panRange: config.panRange,
        tiltRange: config.tiltRange,
        panStep: config.panStep,
        tiltStep: config.tiltStep,
        maxCandidates: config.maxCandidates,
        settleSeconds: config.settleSeconds,
      );
      await _refreshStatusSilently();
    }, successMessage: 'AI 自动找角度已启动。');
  }

  Future<void> _startBackgroundLock() async {
    if (_status?.aiStatus.hasRunningTask == true) {
      setState(() {
        _syncMessage = _errorMessage = 'AI 任务正在运行，请等待当前任务完成。';
      });
      return;
    }
    final config = await _showAiScanConfigDialog(
      title: '背景分析并锁定机位',
      includeDelay: true,
    );
    if (!mounted || config == null) {
      return;
    }
    await _runAction(() async {
      await _deviceApiService.startBackgroundLock(
        baseUrl: _baseUrlController.text,
        panRange: config.panRange,
        tiltRange: config.tiltRange,
        panStep: config.panStep,
        tiltStep: config.tiltStep,
        maxCandidates: config.maxCandidates,
        settleSeconds: config.settleSeconds,
        delaySeconds: config.delaySeconds,
      );
      await _refreshStatusSilently();
    }, successMessage: '背景扫描锁定已启动。');
  }

  Future<void> _unlockBackgroundLock() async {
    await _runAction(() async {
      await _deviceApiService.unlockBackgroundLock(
        baseUrl: _baseUrlController.text,
      );
      await _refreshStatusSilently();
    }, successMessage: 'AI 锁机位已解除。');
  }

  Future<_AiScanConfig?> _showAiScanConfigDialog({
    required String title,
    required bool includeDelay,
  }) {
    return showDialog<_AiScanConfig>(
      context: context,
      builder: (context) =>
          _AiScanConfigDialog(title: title, includeDelay: includeDelay),
    );
  }

  Future<void> _triggerCapture() async {
    await _runAction(() async {
      final captureResult = await _deviceApiService.triggerCapture(
        baseUrl: _baseUrlController.text,
        autoAnalyze: _analyzeCaptureAfterShot,
      );
      await _refreshStatusSilently();
      setState(() {
        _rememberDeviceCapturePath(
          captureResult.path,
          source: 'device_runtime',
        );
        if (captureResult.analysisError != null) {
          _errorMessage = captureResult.analysisError;
        }
      });
    }, successMessage: '设备抓拍已触发。');
  }

  Future<void> _applyLatestBackendAiLock() async {
    await _runAction(() async {
      final captures = await widget.mobileApiService.getHistoryCaptures(
        accessToken: widget.accessToken,
      );
      if (captures.isEmpty) {
        throw const ApiException('后端里还没有抓拍记录，请先在手机拍照页完成一次抓拍。');
      }

      final latestCapture = _pickLatestCapture(captures);
      final task = await widget.mobileApiService.analyzeBackground(
        accessToken: widget.accessToken,
        sessionId: latestCapture.sessionId,
        captureId: latestCapture.id,
      );

      if (task.status != 'succeeded') {
        throw ApiException(task.errorMessage ?? '后端 AI 锁机位任务失败，已阻止下发到设备。');
      }

      final targetBoxNorm = task.targetBoxNorm;
      final panDelta = task.recommendedPanDelta;
      final tiltDelta = task.recommendedTiltDelta;
      if (targetBoxNorm == null || panDelta == null || tiltDelta == null) {
        throw const ApiException('后端 AI 任务没有返回完整的锁机位数据。');
      }

      final status = await _deviceApiService.applyLock(
        baseUrl: _baseUrlController.text,
        recommendedPanDelta: panDelta,
        recommendedTiltDelta: tiltDelta,
        targetBoxNorm: targetBoxNorm,
        summary: task.resultSummary ?? '应用后端 AI 锁机位建议。',
        score: (task.resultScore ?? 90).toDouble(),
      );

      setState(() {
        _status = status;
        _lastBackendAiTask = task;
        _lastStatusUpdatedAt = DateTime.now();
      });
    }, successMessage: '最新后端 AI 锁机位任务已下发到设备。');
  }

  Future<void> _applyLatestBackendAiAngle() async {
    await _runAction(() async {
      final captures = await widget.mobileApiService.getHistoryCaptures(
        accessToken: widget.accessToken,
      );
      if (captures.isEmpty) {
        throw const ApiException('后端里还没有抓拍记录，请先在手机拍照页完成一次抓拍。');
      }

      final latestCapture = _pickLatestCapture(captures);
      final task = await widget.mobileApiService.analyzePhoto(
        accessToken: widget.accessToken,
        sessionId: latestCapture.sessionId,
        captureId: latestCapture.id,
      );

      if (task.status != 'succeeded') {
        throw ApiException(task.errorMessage ?? '后端 AI 角度任务失败，已阻止下发到设备。');
      }

      final panDelta = task.recommendedPanDelta;
      final tiltDelta = task.recommendedTiltDelta;
      if (panDelta == null || tiltDelta == null) {
        throw const ApiException('后端 AI 任务没有返回完整的角度调整数据。');
      }

      final status = await _deviceApiService.applyAngle(
        baseUrl: _baseUrlController.text,
        recommendedPanDelta: panDelta,
        recommendedTiltDelta: tiltDelta,
        summary: task.resultSummary ?? '应用后端 AI 角度建议。',
        score: (task.resultScore ?? 88).toDouble(),
      );

      setState(() {
        _status = status;
        _lastBackendAiTask = task;
        _lastStatusUpdatedAt = DateTime.now();
      });
    }, successMessage: '最新后端 AI 角度任务已下发到设备。');
  }

  List<double> _resolveTargetBoxNorm() {
    final deviceBox = _selectedDeviceTemplate?.bboxNorm;
    if (deviceBox != null && deviceBox.length == 4) {
      return deviceBox;
    }
    final raw = _selectedTemplate?.templateData['bbox_norm'];
    if (raw is List) {
      final values = raw
          .whereType<num>()
          .map((value) => value.toDouble())
          .toList();
      if (values.length == 4) {
        return values;
      }
    }
    return <double>[0.32, 0.12, 0.34, 0.70];
  }

  TemplateSummary? _resolveInitialTemplate(List<TemplateSummary> templates) {
    final preferredTemplateId =
        _selectedTemplate?.id ?? widget.initialTemplate?.id;
    if (templates.isEmpty) {
      return null;
    }
    if (preferredTemplateId == null) {
      return null;
    }
    for (final template in templates) {
      if (template.id == preferredTemplateId) {
        return template;
      }
    }
    return null;
  }

  CaptureRecord _pickLatestCapture(List<CaptureRecord> captures) {
    final sorted = List<CaptureRecord>.from(captures)
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return sorted.first;
  }

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
      _captureRecords.insert(0, existing);
      return;
    }
    _captureRecords.insert(
      0,
      _DeviceCaptureRecord(
        path: normalizedPath,
        createdAt: DateTime.now(),
        source: source,
      ),
    );
    if (_captureRecords.length > 12) {
      _captureRecords.removeRange(12, _captureRecords.length);
    }
  }

  Future<void> _syncDeviceCaptureFiles() async {
    try {
      final files = await _deviceApiService.listCaptureFiles(
        baseUrl: _baseUrlController.text,
        limit: 12,
      );
      if (!mounted || files.isEmpty) {
        return;
      }
      setState(() {
        for (final file in files.reversed) {
          _rememberDeviceCapturePath(file.path, source: 'device_file');
        }
      });
    } catch (_) {
      // Listing captures is a convenience path; status polling should stay quiet.
    }
  }

  Future<void> _saveDeviceCaptureToPhone(_DeviceCaptureRecord record) async {
    if (_isSavingDeviceCapture) {
      return;
    }
    setState(() {
      _isSavingDeviceCapture = true;
      _errorMessage = null;
      _syncMessage = null;
    });
    try {
      final bytes = await _deviceApiService.downloadCaptureFile(
        baseUrl: _baseUrlController.text,
        path: record.path,
      );
      final rootDir = await getApplicationDocumentsDirectory();
      final captureDir = Directory('${rootDir.path}/device_captures');
      await captureDir.create(recursive: true);
      final fileName = _deviceCaptureFileName(record.path);
      final localFile = File('${captureDir.path}/$fileName');
      await localFile.writeAsBytes(bytes, flush: true);

      if (!mounted) {
        return;
      }
      setState(() {
        final index = _captureRecords.indexWhere(
          (item) => item.path == record.path,
        );
        if (index >= 0) {
          _captureRecords[index] = _captureRecords[index].copyWith(
            localPath: localFile.path,
            savedAt: DateTime.now(),
          );
        }
        _syncMessage = '已保存到手机：$fileName';
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = '保存到手机失败：$error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSavingDeviceCapture = false;
        });
      }
    }
  }

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

  String _deviceCaptureFileUrl(String rawPath) {
    final normalizedBaseUrl = _normalizedDeviceBaseUrl(_baseUrlController.text);
    return Uri.parse(
      '$normalizedBaseUrl/api/device/capture/file',
    ).replace(queryParameters: <String, String>{'path': rawPath}).toString();
  }

  Future<void> _refreshStatusSilently() async {
    final status = await _deviceApiService.getStatus(
      baseUrl: _baseUrlController.text,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _status = status;
      _lastStatusUpdatedAt = DateTime.now();
      _rememberDeviceCapturePath(status.latestCapture.path, source: 'status');
      _selectedDeviceTemplate = _resolveDeviceTemplateSelection(
        _deviceTemplates,
      );
    });
    unawaited(_syncDeviceCaptureFiles());
    if (status.sessionOpened) {
      unawaited(_startPreviewStream());
    }
  }

  Future<void> _refreshHealthSilently() async {
    final health = await _deviceApiService.getHealth(
      baseUrl: _baseUrlController.text,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _health = health;
    });
  }

  void _restartPolling() {
    _pollTimer?.cancel();
    if (!_autoRefreshEnabled) {
      return;
    }
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
      if (!mounted || _isBusy) {
        return;
      }
      if (_status?.sessionOpened != true) {
        return;
      }
      try {
        await _refreshStatusSilently();
      } catch (_) {
        if (!mounted) {
          return;
        }
        setState(() {
          _errorMessage = '自动刷新状态失败，请检查设备连接。';
        });
      }
    });
  }

  void _toggleAutoRefresh(bool value) {
    setState(() {
      _autoRefreshEnabled = value;
      if (!value) {
        _syncMessage = '自动刷新已暂停。';
      } else {
        _syncMessage = '自动刷新已开启。';
      }
    });
    _persistDraftConfig();
    _restartPolling();
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

  String _buildPreviewUrl() {
    final baseUrl = _baseUrlController.text.trim();
    final normalizedBaseUrl = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    final nonce =
        _lastStatusUpdatedAt?.millisecondsSinceEpoch ??
        DateTime.now().millisecondsSinceEpoch;
    return '$normalizedBaseUrl/api/device/preview.jpg?ts=$nonce';
  }

  Widget _buildPreviewSection(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final isLandscape = mediaQuery.orientation == Orientation.landscape;
    final hasSession = _status?.sessionOpened == true;
    final previewHeight = (mediaQuery.size.width * (isLandscape ? 0.42 : 0.86))
        .clamp(isLandscape ? 210.0 : 250.0, isLandscape ? 300.0 : 380.0)
        .toDouble();
    final modeLabel = _modeDisplayLabel(_status?.mode ?? 'MANUAL');

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    '设备画面',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                _StatusPill(
                  label: '当前模式',
                  value: modeLabel,
                  active: _status != null,
                ),
              ],
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0xFFF4F1EA),
                  border: Border.all(color: const Color(0xFFD7D0C4)),
                ),
                child: SizedBox(
                  height: previewHeight,
                  width: double.infinity,
                  child: hasSession
                      ? Stack(
                          fit: StackFit.expand,
                          children: <Widget>[
                            if (_webRtcSession != null)
                              _buildWebRtcPreview()
                            else if (_latestPreviewFrameBytes != null)
                              Image.memory(
                                _latestPreviewFrameBytes!,
                                fit: BoxFit.cover,
                                gaplessPlayback: true,
                              )
                            else
                              Image.network(
                                _buildPreviewUrl(),
                                fit: BoxFit.cover,
                                gaplessPlayback: true,
                                loadingBuilder:
                                    (
                                      BuildContext context,
                                      Widget child,
                                      ImageChunkEvent? progress,
                                    ) {
                                      if (progress == null) {
                                        return child;
                                      }
                                      return const _PreviewEmptyState(
                                        icon: Icons.camera_outdoor_outlined,
                                        title: '正在加载设备画面',
                                        description: '已打开设备会话，正在连接实时预览。',
                                      );
                                    },
                                errorBuilder:
                                    (
                                      BuildContext context,
                                      Object error,
                                      StackTrace? stackTrace,
                                    ) {
                                      return const _PreviewEmptyState(
                                        icon:
                                            Icons.wifi_tethering_error_rounded,
                                        title: '暂时无法显示设备画面',
                                        description:
                                            '实时预览或静态预览暂不可用。请确认设备会话已打开，并检查手机画面推送是否正在运行。',
                                      );
                                    },
                              ),
                            Positioned(
                              left: 14,
                              top: 14,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.62),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  _webRtcSession != null
                                      ? 'WebRTC 预览'
                                      : _latestPreviewFrameAt == null
                                      ? '等待预览'
                                      : '预览 ',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        )
                      : const _PreviewEmptyState(
                          icon: Icons.videocam_off_outlined,
                          title: '等待打开设备会话',
                          description: '会话打开后，这里会显示设备返回的画面。',
                        ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '视频流地址${_status?.streamUrl ?? _streamUrlController.text.trim()}',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: const Color(0xFF6A6258)),
            ),
            if (_previewStreamErrorMessage != null) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                _previewStreamErrorMessage!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: const Color(0xFFB9442F),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _formatDateTime(DateTime value) {
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    final hh = value.hour.toString().padLeft(2, '0');
    final mm = value.minute.toString().padLeft(2, '0');
    final ss = value.second.toString().padLeft(2, '0');
    return '$month-$day $hh:$mm:$ss';
  }

  String _captureDisplayName(String path) {
    final normalized = path.replaceAll('\\', '/');
    final segments = normalized.split('/');
    return segments.isEmpty ? path : segments.last;
  }

  String _captureSourceLabel(String source) {
    switch (source) {
      case 'device_runtime':
        return '设备抓拍';
      default:
        return source;
    }
  }

  String _actionCategoryLabel(String category) {
    switch (category) {
      case 'error':
        return '错误';
      case 'system':
        return '系统';
      case 'capture':
        return '抓拍';
      default:
        return category;
    }
  }

  void _addActionRecord(String category, String message) {
    _actionRecords.insert(
      0,
      _DeviceActionRecord(
        category: category,
        message: message,
        createdAt: DateTime.now(),
      ),
    );
    if (_actionRecords.length > 16) {
      _actionRecords.removeRange(16, _actionRecords.length);
    }
  }

  String _buildSessionCode() {
    final now = DateTime.now();
    final datePart =
        '${now.year.toString().padLeft(4, '0')}'
        '${now.month.toString().padLeft(2, '0')}'
        '${now.day.toString().padLeft(2, '0')}';
    final timePart =
        '${now.hour.toString().padLeft(2, '0')}'
        '${now.minute.toString().padLeft(2, '0')}'
        '${now.second.toString().padLeft(2, '0')}';
    return 'MOBILE_${datePart}_$timePart';
  }

  Future<void> _loadPersistedConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final recentRaw =
        prefs.getStringList(_prefsRecentConnectionsKey) ?? <String>[];
    final recentConnections = recentRaw
        .map(_DeviceConnectionPreset.tryParse)
        .whereType<_DeviceConnectionPreset>()
        .toList(growable: false);
    if (!mounted) {
      return;
    }
    setState(() {
      _baseUrlController.text =
          prefs.getString(_prefsBaseUrlKey) ?? _baseUrlController.text;
      _streamUrlController.text =
          prefs.getString(_prefsStreamUrlKey) ?? _streamUrlController.text;
      _autoRefreshEnabled =
          prefs.getBool(_prefsAutoRefreshKey) ?? _autoRefreshEnabled;
      _landscapeControlsOnLeft =
          prefs.getBool(_prefsLandscapeControlsLeftKey) ??
          _landscapeControlsOnLeft;
      _isJoystickVisible =
          prefs.getBool(_prefsJoystickVisibleKey) ?? _isJoystickVisible;
      _joystickSensitivity =
          prefs.getDouble(_prefsJoystickSensitivityKey) ?? _joystickSensitivity;
      _recentConnections = recentConnections;
    });
    _restartPolling();
  }

  void _scheduleDraftPersist() {
    _persistTimer?.cancel();
    _persistTimer = Timer(
      const Duration(milliseconds: 300),
      _persistDraftConfig,
    );
  }

  Future<void> _persistDraftConfig() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsBaseUrlKey, _baseUrlController.text.trim());
    await prefs.setString(_prefsStreamUrlKey, _streamUrlController.text.trim());
    await prefs.setBool(_prefsAutoRefreshKey, _autoRefreshEnabled);
    await prefs.setBool(
      _prefsLandscapeControlsLeftKey,
      _landscapeControlsOnLeft,
    );
    await prefs.setBool(_prefsJoystickVisibleKey, _isJoystickVisible);
    await prefs.setDouble(_prefsJoystickSensitivityKey, _joystickSensitivity);
  }

  Future<void> _rememberCurrentConnection() async {
    final preset = _DeviceConnectionPreset(
      baseUrl: _baseUrlController.text.trim(),
      streamUrl: _streamUrlController.text.trim(),
      sessionCode: _sessionCodeController.text.trim(),
      updatedAt: DateTime.now(),
    );
    final merged = <_DeviceConnectionPreset>[
      preset,
      ..._recentConnections.where(
        (item) =>
            item.baseUrl != preset.baseUrl ||
            item.streamUrl != preset.streamUrl,
      ),
    ];
    final limited = merged.take(5).toList(growable: false);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _prefsRecentConnectionsKey,
      limited.map((item) => item.toStorageString()).toList(growable: false),
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _recentConnections = limited;
    });
  }

  void _applyConnectionPreset(_DeviceConnectionPreset preset) {
    setState(() {
      _baseUrlController.text = preset.baseUrl;
      _streamUrlController.text = preset.streamUrl;
      _sessionCodeController.text = _buildSessionCode();
      _syncMessage = '已载入最近连接配置。';
    });
    _persistDraftConfig();
  }

  Future<void> _clearRecentConnections() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsRecentConnectionsKey);
    if (!mounted) {
      return;
    }
    setState(() {
      _recentConnections = const <_DeviceConnectionPreset>[];
      _syncMessage = '最近连接记录已清空。';
    });
  }

  DeviceLinkResult _buildReturnResult() {
    return DeviceLinkResult(
      selectedTemplateId: _selectedTemplate?.id,
      selectedTemplateName: _selectedTemplate?.name,
      deviceSessionCode:
          _status?.sessionCode ?? _sessionCodeController.text.trim(),
      lastCapturePath: _lastCapturePath,
      backendTaskCode: _lastBackendAiTask?.taskCode,
      aiLockEnabled: _status?.aiLockEnabled ?? false,
    );
  }

  void _returnToCameraPage() {
    Navigator.of(context).pop<DeviceLinkResult>(_buildReturnResult());
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

  Widget _buildStatusOverviewSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          _statusHeadline(),
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            color: const Color(0xFF0D5C63),
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          _statusDescription(),
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            height: 1.45,
            color: const Color(0xFF5A6B70),
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            _StatusPill(
              label: '设备',
              value: _status?.deviceStatus ?? _health?.status ?? '未知',
              active:
                  _status?.deviceStatus == 'online' ||
                  _health?.status == 'online',
            ),
            _StatusPill(
              label: '会话',
              value: _status?.sessionOpened == true ? '已打开' : '未打开',
              active: _status?.sessionOpened == true,
            ),
            _StatusPill(
              label: '模式',
              value: _status?.mode ?? 'MANUAL',
              active: _status != null,
            ),
            if (_status?.selectedTemplateId != null)
              _StatusPill(
                label: '模板',
                value: _status!.selectedTemplateId!.toString(),
                active: true,
              ),
            _StatusPill(
              label: 'AI ?',
              value: _status?.aiLockEnabled == true ? '??' : '??',
              active: _status?.aiLockEnabled == true,
            ),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: <Widget>[
            _SummaryLine(
              label: '会话编号',
              value:
                  _status?.sessionCode ??
                  _health?.sessionCode ??
                  _sessionCodeController.text.trim(),
            ),
            _SummaryLine(label: '最近刷新', value: _formatUpdatedAt()),
            _SummaryLine(label: '跟随模式', value: _status?.followMode ?? '未设置'),
          ],
        ),
      ],
    );
  }

  Widget _buildPreviewPlaceholderSection(BuildContext context) {
    final hasSession = _status?.sessionOpened == true;
    final description = hasSession
        ? '当前会话已经打开，预览画面会在这里显示。'
        : '会话未打开时，这里显示设备画面预览的空状态。请先打开会话。';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              '设备画面',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            AspectRatio(
              aspectRatio: 16 / 9,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0xFFF4F1EA),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: const Color(0xFFD7D0C4)),
                ),
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        Icon(
                          hasSession
                              ? Icons.live_tv_outlined
                              : Icons.videocam_off_outlined,
                          size: 34,
                          color: const Color(0xFF0D5C63),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          hasSession ? '设备画面准备中' : '等待打开设备会话',
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: const Color(0xFF17313A),
                              ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          description,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: const Color(0xFF5A6B70),
                                height: 1.5,
                              ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '视频流地址${_status?.streamUrl ?? _streamUrlController.text.trim()}',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: const Color(0xFF6A6258)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCoreControlsSection(BuildContext context) {
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;

    return _InfoSection(
      title: '手动控制',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (isLandscape)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(child: _buildDirectionControlsSection(context)),
                const SizedBox(width: 18),
                Expanded(child: _buildModeControlsSection(context)),
              ],
            )
          else ...<Widget>[
            _buildDirectionControlsSection(context),
            const SizedBox(height: 18),
            _buildModeControlsSection(context),
          ],
          const SizedBox(height: 18),
          _buildSessionActionsSection(context),
          const SizedBox(height: 14),
          _buildMobilePushSection(context),
          const SizedBox(height: 14),
          _buildStatusOverviewSection(context),
        ],
      ),
    );
  }

  Widget _buildSessionActionsSection(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final buttonWidth = constraints.maxWidth > 600
            ? (constraints.maxWidth - 36) / 4
            : (constraints.maxWidth - 12) / 2;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: <Widget>[
            SizedBox(
              width: buttonWidth,
              child: FilledButton.tonalIcon(
                onPressed: _isBusy ? null : _checkHealth,
                icon: const Icon(Icons.health_and_safety_outlined),
                label: const Text('健康检查'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ),
            SizedBox(
              width: buttonWidth,
              child: FilledButton.tonalIcon(
                onPressed: _isBusy ? null : _fetchStatus,
                icon: const Icon(Icons.radar_outlined),
                label: const Text('刷新状态'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ),
            SizedBox(
              width: buttonWidth,
              child: FilledButton.icon(
                onPressed: _isBusy ? null : _openSession,
                icon: const Icon(Icons.link_outlined),
                label: const Text('打开会话'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ),
            SizedBox(
              width: buttonWidth,
              child: OutlinedButton.icon(
                onPressed: _isBusy ? null : _closeSession,
                icon: const Icon(Icons.link_off_outlined),
                label: const Text('关闭会话'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildMobilePushSection(BuildContext context) {
    final theme = Theme.of(context);
    final lastFrame = _lastMobilePushFrameAt == null
        ? '-'
        : _formatClock(_lastMobilePushFrameAt!);
    final description = _isMobilePushEnabled
        ? (_webRtcSession != null
              ? 'WebRTC 推流中，最近预览 $lastFrame。'
              : 'WebSocket fallback 推流中，已发送 $_mobilePushFrameCount 帧，最近 $lastFrame。')
        : '优先使用 WebRTC 推送手机摄像头，失败时自动回退到 WebSocket/JPEG fallback。';

    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFF8F5EE),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE1D8CA)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(
                  _isMobilePushEnabled
                      ? Icons.videocam_outlined
                      : Icons.mobile_screen_share_outlined,
                  color: _isMobilePushEnabled
                      ? const Color(0xFF0F8F6D)
                      : const Color(0xFF6E6558),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '手机画面推送',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Switch(
                  value: _isMobilePushEnabled,
                  onChanged: _isBusy || _isStartingMobilePush
                      ? null
                      : (bool value) {
                          if (value) {
                            unawaited(_startMobilePush());
                          } else {
                            unawaited(_stopMobilePush());
                          }
                        },
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              description,
              style: theme.textTheme.bodySmall?.copyWith(
                color: const Color(0xFF6E6558),
                height: 1.35,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: <Widget>[
                _StatusPill(
                  label: '摄像头',
                  value: _mobilePushLensLabel(),
                  active: _isMobilePushEnabled,
                ),
                OutlinedButton.icon(
                  onPressed:
                      _isBusy ||
                          _isStartingMobilePush ||
                          _isHandlingMobilePushOrientationChange
                      ? null
                      : () => unawaited(_switchMobilePushCamera()),
                  icon: const Icon(Icons.cameraswitch_outlined),
                  label: Text(_mobilePushSwitchTargetLabel()),
                ),
              ],
            ),
            if (_mobilePushErrorMessage != null) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                _mobilePushErrorMessage!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: const Color(0xFFB9442F),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDirectionControlsSection(BuildContext context) {
    final canManualMove = _status?.sessionOpened == true && !_isBusy;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          '方向控制',
          style: Theme.of(
            context,
          ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 12),
        Center(
          child: Column(
            children: <Widget>[
              _ManualMoveHoldButton(
                enabled: canManualMove,
                onStart: () => _startManualMoveRepeat('up'),
                onStop: _stopManualMoveRepeat,
                icon: const Icon(Icons.keyboard_arrow_up),
                label: '上移',
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  _ManualMoveHoldButton(
                    enabled: canManualMove,
                    onStart: () => _startManualMoveRepeat('left'),
                    onStop: _stopManualMoveRepeat,
                    icon: const Icon(Icons.keyboard_arrow_left),
                    label: '左移',
                  ),
                  const SizedBox(width: 10),
                  OutlinedButton.icon(
                    onPressed: _isBusy ? null : _home,
                    icon: const Icon(Icons.center_focus_strong_outlined),
                    label: const Text('回中'),
                  ),
                  const SizedBox(width: 10),
                  _ManualMoveHoldButton(
                    enabled: canManualMove,
                    onStart: () => _startManualMoveRepeat('right'),
                    onStop: _stopManualMoveRepeat,
                    icon: const Icon(Icons.keyboard_arrow_right),
                    label: '右移',
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _ManualMoveHoldButton(
                enabled: canManualMove,
                onStart: () => _startManualMoveRepeat('down'),
                onStop: _stopManualMoveRepeat,
                icon: const Icon(Icons.keyboard_arrow_down),
                label: '下移',
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _modeDisplayLabel(String mode) {
    switch (mode) {
      case 'MANUAL':
        return '手动控制';
      case 'AUTO_TRACK':
        return '自动跟随';
      case 'SMART_COMPOSE':
        return '模板构图';
      default:
        return mode;
    }
  }

  String _followModeDisplayLabel(String mode) {
    switch (mode) {
      case 'shoulders':
        return '肩部跟随';
      case 'face':
        return '人脸跟随';
      default:
        return mode;
    }
  }

  Widget _buildModeGroup({
    required BuildContext context,
    required String title,
    required String summary,
    required String description,
    required List<Widget> children,
    Widget? footer,
    bool initiallyExpanded = false,
  }) {
    return SizedBox(
      width: double.infinity,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xFFF7F3EC),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFE2D8C9)),
        ),
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            initiallyExpanded: initiallyExpanded,
            tilePadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 2,
            ),
            childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
            title: Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                summary,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: const Color(0xFF6A6258),
                  height: 1.35,
                ),
              ),
            ),
            children: <Widget>[
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  description,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF6A6258),
                    height: 1.4,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: Wrap(spacing: 8, runSpacing: 8, children: children),
              ),
              if (footer != null) ...<Widget>[
                const SizedBox(height: 12),
                footer,
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAiActionSummary(BuildContext context) {
    if (_lastCapturePath == null && _lastBackendAiTask == null) {
      return Text(
        '当前还没有 AI 执行记录，可直接触发抓拍或应用后端结果。',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: const Color(0xFF6A6258),
          height: 1.4,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (_lastCapturePath != null)
          Text(
            '最近抓拍：${_captureDisplayName(_lastCapturePath!)}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: const Color(0xFF6A6258),
              height: 1.4,
            ),
          ),
        if (_lastCapturePath != null && _lastBackendAiTask != null)
          const SizedBox(height: 6),
        if (_lastBackendAiTask != null) ...<Widget>[
          Text(
            '最近后端任务：${_lastBackendAiTask!.taskCode} · ${_lastBackendAiTask!.status}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: const Color(0xFF6A6258),
              height: 1.4,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '任务结果：',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: const Color(0xFF6A6258),
              height: 1.4,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildModeControlsSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _buildModeGroup(
          context: context,
          title: '运行模式',
          summary: '当前：',
          description: '选择设备当前的控制方式。',
          initiallyExpanded: true,
          children: _modes
              .map(
                (mode) => _ModeChip(
                  label: _modeDisplayLabel(mode),
                  selected: _status?.mode == mode,
                  onTap: _isBusy ? null : () => _setMode(mode),
                ),
              )
              .toList(growable: false),
        ),
        const SizedBox(height: 12),
        _buildModeGroup(
          context: context,
          title: '跟随模式',
          summary: '当前：',
          description: '选择跟随肩部或人脸作为自动构图参考。',
          children: _followModes
              .map(
                (mode) => _ModeChip(
                  label: _followModeDisplayLabel(mode),
                  selected: _status?.followMode == mode,
                  onTap: _isBusy ? null : () => _setFollowMode(mode),
                ),
              )
              .toList(growable: false),
        ),
        const SizedBox(height: 12),
        _buildModeGroup(
          context: context,
          title: 'AI 功能',
          summary: _lastBackendAiTask == null
              ? '暂无任务'
              : '最近任务：${_lastBackendAiTask!.status}',
          description: '抓拍、找角度和背景锁定集中在这里。',
          children: <Widget>[
            FilledButton.tonalIcon(
              onPressed: _isBusy ? null : _applyAngleSuggestion,
              icon: const Icon(Icons.auto_fix_high_outlined),
              label: const Text('应用示例角度'),
            ),
            FilledButton.tonalIcon(
              onPressed: _isBusy ? null : _applyLockSuggestion,
              icon: const Icon(Icons.lock_outline),
              label: const Text('应用示例锁机位'),
            ),
            FilledButton.icon(
              onPressed: _isBusy ? null : _triggerCapture,
              icon: const Icon(Icons.camera_outlined),
              label: const Text('触发抓拍'),
            ),
            FilledButton.tonalIcon(
              onPressed: _isBusy ? null : _applyLatestBackendAiLock,
              icon: const Icon(Icons.cloud_sync_outlined),
              label: const Text('应用后端 AI 锁机位'),
            ),
            FilledButton.tonalIcon(
              onPressed: _isBusy ? null : _applyLatestBackendAiAngle,
              icon: const Icon(Icons.tune_outlined),
              label: const Text('应用后端 AI 角度'),
            ),
          ],
          footer: _buildAiActionSummary(context),
        ),
      ],
    );
  }

  Widget _buildConnectionSettingsContent(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          '连接参数会自动保存在本机。修改后可直接回到上方手动控制区域执行健康检查或打开会话。',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            height: 1.5,
            color: const Color(0xFF5A6B70),
          ),
        ),
        const SizedBox(height: 14),
        _InputBlock(
          label: '设备地址',
          hintText: 'http://192.168.1.100:8001',
          controller: _baseUrlController,
        ),
        const SizedBox(height: 12),
        _InputBlock(
          label: '视频流地址',
          hintText: 'rtsp://example.invalid/live',
          controller: _streamUrlController,
        ),
        const SizedBox(height: 12),
        _InputBlock(
          label: '会话编号',
          hintText: 'MOBILE_20260418_131500',
          controller: _sessionCodeController,
        ),
        if (_recentConnections.isNotEmpty) ...<Widget>[
          const SizedBox(height: 16),
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  '最近连接',
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              TextButton(
                onPressed: _clearRecentConnections,
                child: const Text('清空记录'),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ..._recentConnections.map(
            (preset) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: OutlinedButton(
                onPressed: _isBusy
                    ? null
                    : () => _applyConnectionPreset(preset),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.all(14),
                  alignment: Alignment.centerLeft,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      preset.baseUrl,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(' · ', style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildTemplateDispatchContent(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                _selectedTemplate == null ? '模板（可选）' : '模板（已选择）',
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            TextButton(
              onPressed: _isCreatingDemoTemplate ? null : _createTemplate,
              child: _isCreatingDemoTemplate
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('新增模板'),
            ),
          ],
        ),
        if (_selectedTemplate != null) ...<Widget>[
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerRight,
            child: Wrap(
              spacing: 6,
              children: <Widget>[
                TextButton(
                  onPressed: _isBusy
                      ? null
                      : () {
                          setState(() {
                            _selectedTemplate = null;
                            _syncMessage = '已取消模板选择。';
                          });
                        },
                  child: const Text('不使用模板'),
                ),
                TextButton(
                  onPressed: _isDeletingTemplate
                      ? null
                      : _deleteSelectedTemplate,
                  child: _isDeletingTemplate
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('删除当前模板'),
                ),
              ],
            ),
          ),
        ],
        if (_isLoadingTemplates) ...<Widget>[
          const SizedBox(height: 10),
          const LinearProgressIndicator(minHeight: 3),
        ] else if (_templates.isEmpty) ...<Widget>[
          const SizedBox(height: 10),
          const Text('还没有模板，可以先新增一个模板。'),
        ] else ...<Widget>[
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: <Widget>[
              _ModeChip(
                label: '不使用模板',
                selected: _selectedTemplate == null,
                onTap: _isBusy
                    ? null
                    : () {
                        setState(() {
                          _selectedTemplate = null;
                          _syncMessage = '已取消模板选择。';
                        });
                      },
              ),
              ..._templates.map(
                (template) => _ModeChip(
                  label: template.name,
                  selected: _selectedTemplate?.id == template.id,
                  onTap: _isBusy
                      ? null
                      : () {
                          setState(() {
                            _selectedTemplate = template;
                            _syncMessage = '已选择模板${template.name}';
                          });
                        },
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          FilledButton.tonalIcon(
            onPressed: _isBusy ? null : _pushTemplate,
            icon: const Icon(Icons.upload_outlined),
            label: Text(
              _selectedTemplate == null
                  ? '下发模板'
                  : '下发 ${_selectedTemplate!.name}',
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildLinkStatusContent(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                '最后刷新时间：${_formatUpdatedAt()}',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
            Switch(value: _autoRefreshEnabled, onChanged: _toggleAutoRefresh),
          ],
        ),
        Text(
          _autoRefreshEnabled
              ? '当设备会话处于打开状态时，页面会每 3 秒自动刷新一次。'
              : '自动刷新已暂停，请手动点击刷新状态或执行任意控制动作更新页面。',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(height: 1.5),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: <Widget>[
            _StatusPill(
              label: '设备',
              value: _status?.deviceStatus ?? '空闲',
              active: _status?.deviceStatus == 'online',
            ),
            _StatusPill(
              label: '会话',
              value: _status?.sessionOpened == true ? '已打开' : '已关闭',
              active: _status?.sessionOpened == true,
            ),
            if (_status?.selectedTemplateId != null)
              _StatusPill(
                label: '模板',
                value: _status!.selectedTemplateId!.toString(),
                active: true,
              ),
            _StatusPill(
              label: 'AI 锁机位',
              value: _status?.aiLockEnabled == true ? '开启' : '关闭',
              active: _status?.aiLockEnabled == true,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildCaptureRecordsContent(BuildContext context) {
    if (_captureRecords.isEmpty) {
      return const Text('还没有设备抓拍记录。');
    }
    return Column(
      children: _captureRecords
          .map(
            (record) => _TimelineTile(
              title: _captureDisplayName(record.path),
              subtitle: ' · ',
              accentColor: const Color(0xFF3A7D44),
            ),
          )
          .toList(growable: false),
    );
  }

  Widget _buildActionTimelineContent(BuildContext context) {
    if (_actionRecords.isEmpty) {
      return const Text('还没有设备操作记录。');
    }
    return Column(
      children: _actionRecords
          .map(
            (record) => _TimelineTile(
              title: record.message,
              subtitle: ' · ',
              accentColor: record.category == 'error'
                  ? const Color(0xFF9E2A2B)
                  : const Color(0xFF0D5C63),
            ),
          )
          .toList(growable: false),
    );
  }

  Widget _buildHealthResultContent() {
    if (_health == null) {
      return const Text('还没有健康检查结果。');
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('设备编号${_health!.deviceCode}'),
        const SizedBox(height: 6),
        Text('状态：${_health!.status}'),
        const SizedBox(height: 6),
        Text('服务版本${_health!.serviceVersion}'),
        const SizedBox(height: 6),
        Text('会话编号${_health!.sessionCode ?? ' - '}'),
      ],
    );
  }

  Widget _buildRuntimeStatusContent() {
    if (_status == null) {
      return const Text('还没有加载运行状态。');
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('会话是否打开${_status!.sessionOpened}'),
        const SizedBox(height: 6),
        Text('会话编号${_status!.sessionCode ?? ' - '}'),
        const SizedBox(height: 6),
        Text('视频流地址${_status!.streamUrl ?? ' - '}'),
        const SizedBox(height: 6),
        Text('运行模式${_status!.mode}'),
        const SizedBox(height: 6),
        Text('跟随模式${_status!.followMode ?? ' - '}'),
        const SizedBox(height: 6),
        Text('设备状态：${_status!.deviceStatus}'),
        const SizedBox(height: 6),
        Text('当前水平角：${_status!.currentPan.toStringAsFixed(2)}'),
        const SizedBox(height: 6),
        Text('当前俯仰角：${_status!.currentTilt.toStringAsFixed(2)}'),
        const SizedBox(height: 6),
        Text('处理循环运行中：${_status!.loopRunning}'),
        const SizedBox(height: 6),
        Text('选中模板编号${_status!.selectedTemplateId?.toString() ?? ' - '}'),
        const SizedBox(height: 6),
        Text('AI 锁机位开启：${_status!.aiLockEnabled}'),
        const SizedBox(height: 6),
        Text('AI 锁机位拟合分：'),
        const SizedBox(height: 6),
        Text('AI 锁机位目标框：'),
      ],
    );
  }

  Widget _buildDevicePreviewBackdrop(BuildContext context) {
    final hasSession = _status?.sessionOpened == true;
    final Widget preview;

    if (!hasSession) {
      preview = const _HudEmptyPreview();
    } else if (_webRtcSession != null) {
      preview = _buildWebRtcPreview();
    } else if (_latestPreviewFrameBytes != null) {
      preview = Image.memory(
        _latestPreviewFrameBytes!,
        fit: BoxFit.cover,
        gaplessPlayback: true,
      );
    } else {
      preview = Image.network(
        _buildPreviewUrl(),
        fit: BoxFit.cover,
        gaplessPlayback: true,
        loadingBuilder: (context, child, progress) {
          if (progress == null) {
            return child;
          }
          return const _HudEmptyPreview(
            icon: Icons.camera_outdoor_outlined,
            title: '正在加载设备画面',
            description: '已打开设备会话，正在连接实时预览。',
          );
        },
        errorBuilder: (context, error, stackTrace) {
          return const _HudEmptyPreview(
            icon: Icons.wifi_tethering_error_rounded,
            title: '暂时无法显示设备画面',
            description: '请检查会话、视频流地址或手机画面推送。',
          );
        },
      );
    }

    return ColoredBox(
      color: Colors.black,
      child: SizedBox.expand(child: preview),
    );
  }

  Widget _buildHudTopBar(BuildContext context, {required bool isLandscape}) {
    if (_isHudHidden) {
      return const SizedBox.shrink();
    }
    final topPadding = MediaQuery.paddingOf(context).top;
    return Positioned(
      left: isLandscape ? 18 : 14,
      right: isLandscape ? 18 : 14,
      top: math.max(10, topPadding + 8),
      child: _HudGlass(
        compact: true,
        child: Row(
          children: <Widget>[
            _HudCircleButton(
              icon: Icons.arrow_back,
              tooltip: '返回',
              onTap: _returnToCameraPage,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    '设备联动',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    _statusDescription(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.white.withValues(alpha: 0.74),
                      height: 1.25,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            _HudStatusBadge(
              label: _status?.sessionOpened == true ? '已连接' : '未连接',
              active: _status?.sessionOpened == true,
            ),
            const SizedBox(width: 8),
            _HudCircleButton(
              icon: Icons.visibility_off_outlined,
              tooltip: '隐藏 HUD',
              onTap: () {
                setState(() {
                  _isHudHidden = true;
                });
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreviewBadge(BuildContext context, {required bool isLandscape}) {
    if (_isHudHidden) {
      return const SizedBox.shrink();
    }
    return Positioned(
      left: isLandscape ? 22 : 16,
      top: isLandscape ? 94 : 108,
      child: _HudGlass(
        compact: true,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              _latestPreviewFrameAt == null
                  ? Icons.image_outlined
                  : Icons.sensors_outlined,
              size: 16,
              color: Colors.white.withValues(alpha: 0.86),
            ),
            const SizedBox(width: 8),
            Text(
              _latestPreviewFrameAt == null
                  ? '静态预览'
                  : '实时 ${_formatClock(_latestPreviewFrameAt!)}',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 12.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHudMessages(BuildContext context, {required bool isLandscape}) {
    final messageKey = _currentHudMessageKey();
    if (messageKey == null) {
      _hudMessageTimer?.cancel();
      _hudMessageTimerKey = null;
    } else {
      _scheduleHudMessageDismiss(messageKey);
    }
    if (_isHudHidden) {
      return const SizedBox.shrink();
    }
    final message = _errorMessage ?? _previewStreamErrorMessage ?? _syncMessage;
    if (message == null) {
      return const SizedBox.shrink();
    }
    final isError = _errorMessage != null || _previewStreamErrorMessage != null;
    return Positioned(
      left: isLandscape ? 22 : 16,
      right: isLandscape ? 22 : 16,
      top: isLandscape ? null : 154,
      bottom: isLandscape ? 82 : null,
      child: _HudGlass(
        tint: isError ? const Color(0xBB6F1D1B) : const Color(0xAA0D5C63),
        compact: true,
        child: Text(
          message,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            height: 1.35,
          ),
        ),
      ),
    );
  }

  Widget _buildHudBottomNav(BuildContext context, {required bool isLandscape}) {
    final bottomPadding = MediaQuery.paddingOf(context).bottom;
    final items = <({IconData icon, String label, _DeviceHudPanel panel})>[
      (
        icon: Icons.gamepad_outlined,
        label: '控制',
        panel: _DeviceHudPanel.control,
      ),
      (icon: Icons.tune_outlined, label: '模式', panel: _DeviceHudPanel.mode),
      (
        icon: Icons.auto_awesome_outlined,
        label: 'AI',
        panel: _DeviceHudPanel.ai,
      ),
      (
        icon: Icons.settings_input_component_outlined,
        label: '设备',
        panel: _DeviceHudPanel.device,
      ),
    ];

    if (_isHudHidden) {
      return Positioned(
        left: isLandscape && _landscapeControlsOnLeft ? 18 : null,
        right: isLandscape && !_landscapeControlsOnLeft ? 18 : 16,
        bottom: math.max(12, bottomPadding + 10),
        child: _HudGlass(
          compact: true,
          child: _HudCircleButton(
            icon: Icons.visibility_outlined,
            tooltip: '显示 HUD',
            onTap: () {
              setState(() {
                _isHudHidden = false;
              });
            },
          ),
        ),
      );
    }

    if (isLandscape) {
      final sidePadding = MediaQuery.paddingOf(context).right;
      final leftPadding = MediaQuery.paddingOf(context).left;
      final sideInset = math.max(
        14.0,
        (_landscapeControlsOnLeft ? leftPadding : sidePadding) + 12,
      );
      return Positioned(
        top: math.max(92, MediaQuery.paddingOf(context).top + 70),
        bottom: math.max(14, bottomPadding + 14),
        left: _landscapeControlsOnLeft ? sideInset : null,
        right: _landscapeControlsOnLeft ? null : sideInset,
        width: 78,
        child: _HudGlass(
          compact: true,
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: <Widget>[
                      for (var index = 0; index < items.length; index += 1)
                        Padding(
                          padding: EdgeInsets.only(
                            bottom: index == items.length - 1 ? 0 : 6,
                          ),
                          child: _HudNavButton(
                            icon: items[index].icon,
                            label: items[index].label,
                            selected: _activeHudPanel == items[index].panel,
                            onTap: () => _toggleHudPanel(items[index].panel),
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      );
    }

    return Positioned(
      left: 16,
      right: 16,
      bottom: math.max(10, bottomPadding + 8),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: _HudGlass(
            compact: true,
            child: Row(
              children: items
                  .map(
                    (item) => Expanded(
                      child: _HudNavButton(
                        icon: item.icon,
                        label: item.label,
                        selected: _activeHudPanel == item.panel,
                        onTap: () => _toggleHudPanel(item.panel),
                      ),
                    ),
                  )
                  .toList(growable: false),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHudPanel(BuildContext context, {required bool isLandscape}) {
    final panel = _activeHudPanel;
    if (_isHudHidden || panel == null) {
      return const SizedBox.shrink();
    }
    final mediaPadding = MediaQuery.paddingOf(context);
    final bottomPadding = MediaQuery.paddingOf(context).bottom;
    final sideInset = math.max(
      108.0,
      (_landscapeControlsOnLeft ? mediaPadding.left : mediaPadding.right) + 104,
    );

    if (isLandscape) {
      final panelWidth = panel == _DeviceHudPanel.device ? 420.0 : 360.0;
      return Positioned(
        top: math.max(92, mediaPadding.top + 70),
        bottom: math.max(14, bottomPadding + 14),
        left: _landscapeControlsOnLeft ? sideInset : null,
        right: _landscapeControlsOnLeft ? null : sideInset,
        width: panelWidth,
        child: _HudGlass(
          child: SingleChildScrollView(
            child: switch (panel) {
              _DeviceHudPanel.control => _buildHudControlPanel(context),
              _DeviceHudPanel.mode => _buildHudModePanel(context),
              _DeviceHudPanel.ai => _buildHudAiPanel(context),
              _DeviceHudPanel.device => _buildHudDevicePanel(context),
            },
          ),
        ),
      );
    }

    return Positioned(
      left: 16,
      right: 16,
      bottom: bottomPadding + 76,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460, maxHeight: 320),
          child: _HudGlass(
            child: SingleChildScrollView(
              child: switch (panel) {
                _DeviceHudPanel.control => _buildHudControlPanel(context),
                _DeviceHudPanel.mode => _buildHudModePanel(context),
                _DeviceHudPanel.ai => _buildHudAiPanel(context),
                _DeviceHudPanel.device => _buildHudDevicePanel(context),
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHudControlPanel(BuildContext context) {
    final sensitivityItems = <({String label, double value})>[
      (label: '低', value: 0.65),
      (label: '中', value: 1.0),
      (label: '高', value: 1.45),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _HudPanelHeader(
          title: '手动控制',
          subtitle: _status?.sessionOpened == true
              ? '摇杆独立显示，关闭这个面板后仍会保留。'
              : '打开会话后即可拖动摇杆。',
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: <Widget>[
            _HudActionChip(
              icon: Icons.gamepad_outlined,
              label: _isJoystickVisible ? '隐藏摇杆' : '显示摇杆',
              selected: _isJoystickVisible,
              onTap: () => _setJoystickVisible(!_isJoystickVisible),
            ),
            _HudActionChip(
              icon: Icons.open_with_outlined,
              label: '重置位置',
              onTap: _isJoystickVisible
                  ? () {
                      setState(() {
                        _hasCustomJoystickAnchor = false;
                      });
                      _scheduleDraftPersist();
                    }
                  : null,
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[
            Text(
              '灵敏度',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.72),
                fontWeight: FontWeight.w700,
              ),
            ),
            ...sensitivityItems.map(
              (item) => _HudActionChip(
                label: item.label,
                selected: (_joystickSensitivity - item.value).abs() < 0.05,
                onTap: () => _setJoystickSensitivity(item.value),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: <Widget>[
            _HudActionChip(
              icon: Icons.center_focus_strong_outlined,
              label: '回中',
              onTap: _isBusy ? null : _home,
            ),
            _HudActionChip(
              icon: Icons.radar_outlined,
              label: '刷新',
              onTap: _isBusy ? null : _fetchStatus,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildHudModePanel(BuildContext context) {
    final templateStatus = _status?.templateStatus;
    final templateSummary = templateStatus == null
        ? '未选择模板'
        : '${templateStatus.templateName ?? _status?.selectedTemplateId ?? '未命名模板'} · ${templateStatus.ready ? 'ready' : 'waiting'}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _HudPanelHeader(
          title: '运行模式',
          subtitle: '当前：${_modeDisplayLabel(_status?.mode ?? 'MANUAL')}',
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: _modes
              .map(
                (mode) => _HudActionChip(
                  label: _modeDisplayLabel(mode),
                  selected: _status?.mode == mode,
                  onTap: _isBusy ? null : () => _setMode(mode),
                ),
              )
              .toList(growable: false),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: _followModes
              .map(
                (mode) => _HudActionChip(
                  label: _followModeDisplayLabel(mode),
                  selected: _status?.followMode == mode,
                  onTap: _isBusy ? null : () => _setFollowMode(mode),
                ),
              )
              .toList(growable: false),
        ),
        const SizedBox(height: 14),
        Text(
          '树莓派模板',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          templateSummary,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.68),
            height: 1.35,
          ),
        ),
        if (templateStatus?.composeScore != null) ...<Widget>[
          const SizedBox(height: 4),
          Text(
            '构图分数${templateStatus!.composeScore!.toStringAsFixed(1)}',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.68)),
          ),
        ],
        if (templateStatus?.messages.isNotEmpty == true) ...<Widget>[
          const SizedBox(height: 4),
          Text(
            templateStatus!.messages.join(' · '),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: Colors.white.withValues(alpha: 0.62)),
          ),
        ],
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: <Widget>[
            _HudActionChip(
              icon: Icons.add_photo_alternate_outlined,
              label: _isUploadingDeviceTemplate ? '上传中' : '上传图片',
              onTap: _isBusy || _isUploadingDeviceTemplate
                  ? null
                  : _uploadDeviceTemplate,
            ),
            _HudActionChip(
              icon: Icons.refresh_outlined,
              label: _isLoadingDeviceTemplates ? '刷新中' : '刷新模板',
              onTap: _isBusy || _isLoadingDeviceTemplates
                  ? null
                  : () => _loadDeviceTemplates(),
            ),
            _HudActionChip(
              icon: Icons.check_circle_outline,
              label: _selectedDeviceTemplate == null
                  ? '选择模板'
                  : '使用 ${_selectedDeviceTemplate!.name}',
              onTap: _isBusy || _selectedDeviceTemplate == null
                  ? null
                  : _pushTemplate,
            ),
            _HudActionChip(
              icon: Icons.layers_clear_outlined,
              label: '关闭模板',
              onTap: _isBusy || _status?.selectedTemplateId == null
                  ? null
                  : _clearDeviceTemplateSelection,
            ),
            _HudActionChip(
              icon: Icons.delete_outline,
              label: _isDeletingDeviceTemplate ? '删除中' : '删除模板',
              onTap:
                  _isBusy ||
                      _isDeletingDeviceTemplate ||
                      _selectedDeviceTemplate == null
                  ? null
                  : _deleteSelectedDeviceTemplate,
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (_isLoadingDeviceTemplates)
          LinearProgressIndicator(
            minHeight: 3,
            color: const Color(0xFF9BE7DD),
            backgroundColor: Colors.white.withValues(alpha: 0.12),
          )
        else if (_deviceTemplates.isEmpty)
          Text(
            '还没有树莓派模板，先上传人物姿势图生成模板。',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.66)),
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _deviceTemplates
                .map(
                  (template) => _HudActionChip(
                    label:
                        '${template.name}${template.posePointCount > 0 ? ' · ${template.posePointCount}点' : ''}',
                    selected: _selectedDeviceTemplate?.id == template.id,
                    onTap: _isBusy
                        ? null
                        : () {
                            setState(() {
                              _selectedDeviceTemplate = template;
                              _selectedTemplate = null;
                              _syncMessage = '已选择树莓派模板：';
                            });
                          },
                  ),
                )
                .toList(growable: false),
          ),
      ],
    );
  }

  Widget _buildHudAiPanel(BuildContext context) {
    final aiStatus = _status?.aiStatus ?? const DeviceAiStatusSummary();
    final isRunning = aiStatus.hasRunningTask;
    final lastError =
        aiStatus.lastAngleSearchError ?? aiStatus.lastBackgroundLockError;
    final lastResult =
        aiStatus.lastAngleSearchResult ?? aiStatus.lastBackgroundLockResult;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _HudPanelHeader(
          title: 'AI 功能',
          subtitle: isRunning ? 'AI 正在扫描，请等待结果。' : '抓拍、找角度和背景锁定集中在这里。',
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: <Widget>[
            _HudActionChip(
              icon: Icons.camera_outlined,
              label: '抓拍',
              onTap: _isBusy ? null : _triggerCapture,
            ),
            _HudActionChip(
              icon: Icons.travel_explore_outlined,
              label: isRunning ? '运行中' : '自动找角度',
              onTap: _isBusy || isRunning ? null : _startAngleSearch,
            ),
            _HudActionChip(
              icon: Icons.center_focus_weak_outlined,
              label: isRunning ? '运行中' : '背景锁定',
              onTap: _isBusy || isRunning ? null : _startBackgroundLock,
            ),
            _HudActionChip(
              icon: Icons.lock_open_outlined,
              label: '解除锁定',
              onTap: _isBusy || !aiStatus.lockEnabled
                  ? null
                  : _unlockBackgroundLock,
            ),
            _HudActionChip(
              icon: Icons.cloud_sync_outlined,
              label: '外部锁定',
              onTap: _isBusy ? null : _applyLatestBackendAiLock,
            ),
            _HudActionChip(
              icon: Icons.tune_outlined,
              label: '外部角度',
              onTap: _isBusy ? null : _applyLatestBackendAiAngle,
            ),
          ],
        ),
        const SizedBox(height: 12),
        _buildHudGestureOptions(context),
        if (isRunning) ...<Widget>[
          const SizedBox(height: 12),
          LinearProgressIndicator(
            minHeight: 3,
            color: const Color(0xFF9BE7DD),
            backgroundColor: Colors.white.withValues(alpha: 0.12),
          ),
        ],
        if (lastResult != null) ...<Widget>[
          const SizedBox(height: 10),
          Text(
            "最近结果：${lastResult['summary'] ?? lastResult['best_summary'] ?? lastResult}",
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.72),
              height: 1.35,
            ),
          ),
        ],
        if (lastError != null) ...<Widget>[
          const SizedBox(height: 10),
          Text(
            '最近错误：$lastError',
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFFFFB7A8),
              fontWeight: FontWeight.w700,
              height: 1.35,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildHudGestureOptions(BuildContext context) {
    final gesture =
        _status?.gestureStatus ?? const DeviceGestureStatusSummary();
    final latestCapture =
        _status?.latestCapture ?? const DeviceLatestCaptureSummary();
    final canUpdate = _status?.sessionOpened == true && !_isBusy;
    final analysisSummary = latestCapture.analysis?.summary;
    final analysisScore = latestCapture.analysis?.score;
    final recentCaptures = _captureRecords.take(4).toList(growable: false);

    Widget option({
      required IconData icon,
      required String label,
      required bool selected,
      required VoidCallback? onTap,
    }) {
      return _HudActionChip(
        icon: icon,
        label: label,
        selected: selected,
        onTap: onTap,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: <Widget>[
            option(
              icon: Icons.auto_awesome_outlined,
              label: '抓拍后AI分析',
              selected: _analyzeCaptureAfterShot || gesture.autoAnalyzeEnabled,
              onTap: () => _setCaptureAnalyzeAfterShot(
                !(_analyzeCaptureAfterShot || gesture.autoAnalyzeEnabled),
              ),
            ),
            option(
              icon: Icons.pan_tool_alt_outlined,
              label: '张手握拳抓拍',
              selected: gesture.captureEnabled,
              onTap: canUpdate
                  ? () => _setGestureOption(
                      'capture_enabled',
                      !gesture.captureEnabled,
                    )
                  : null,
            ),
            option(
              icon: Icons.check_circle_outline,
              label: 'OK手势抓拍',
              selected: gesture.forceOkEnabled,
              onTap: canUpdate
                  ? () => _setGestureOption(
                      'force_ok_enabled',
                      !gesture.forceOkEnabled,
                    )
                  : null,
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          '手势：检测到 ${gesture.handCount} 只手；张手握拳需要模板构图 ready，OK 可强制抓拍。',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.62),
            height: 1.35,
          ),
        ),
        if (latestCapture.path != null &&
            latestCapture.path!.isNotEmpty) ...<Widget>[
          const SizedBox(height: 8),
          Text(
            '最近抓拍保存：${latestCapture.path}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.72),
              fontWeight: FontWeight.w700,
              height: 1.35,
            ),
          ),
        ],
        if (analysisSummary != null ||
            latestCapture.analysisError != null) ...<Widget>[
          const SizedBox(height: 8),
          Text(
            latestCapture.analysisError ??
                '抓拍 AI：${analysisScore == null ? '' : '${analysisScore.toStringAsFixed(1)} 分 · '}$analysisSummary',
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: latestCapture.analysisError == null
                  ? Colors.white.withValues(alpha: 0.72)
                  : const Color(0xFFFFB7A8),
              fontWeight: FontWeight.w700,
              height: 1.35,
            ),
          ),
        ],
        if (recentCaptures.isNotEmpty) ...<Widget>[
          const SizedBox(height: 10),
          Text(
            '设备照片',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.78),
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              for (var index = 0; index < recentCaptures.length; index++)
                SizedBox(
                  width: 118,
                  child: _HudGlass(
                    compact: true,
                    tint: const Color(0x6610181C),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: AspectRatio(
                            aspectRatio: 1,
                            child: Image.network(
                              _deviceCaptureFileUrl(recentCaptures[index].path),
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) {
                                return Container(
                                  color: Colors.white.withValues(alpha: 0.08),
                                  alignment: Alignment.center,
                                  child: Icon(
                                    Icons.image_not_supported_outlined,
                                    color: Colors.white.withValues(alpha: 0.52),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _shortDeviceCaptureName(recentCaptures[index].path),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.72),
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 6),
                        _HudActionChip(
                          icon: recentCaptures[index].localPath == null
                              ? Icons.download_outlined
                              : Icons.check_circle_outline,
                          label: recentCaptures[index].localPath == null
                              ? '保存'
                              : '已保存',
                          selected: recentCaptures[index].localPath != null,
                          onTap:
                              _isSavingDeviceCapture ||
                                  recentCaptures[index].localPath != null
                              ? null
                              : () => _saveDeviceCaptureToPhone(
                                  recentCaptures[index],
                                ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '树莓派照片会先列在这里，点保存后才写入手机本地。',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.58),
              height: 1.35,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildHudTextField({
    required String label,
    required String hintText,
    required TextEditingController controller,
  }) {
    return TextField(
      controller: controller,
      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
      cursorColor: const Color(0xFFBDF6EF),
      decoration: InputDecoration(
        labelText: label,
        hintText: hintText,
        labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.68)),
        hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.35)),
        isDense: true,
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.08),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.16)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFFBDF6EF)),
        ),
      ),
    );
  }

  Widget _buildHudDevicePanel(BuildContext context) {
    final lastFrame = _lastMobilePushFrameAt == null
        ? '-'
        : _formatClock(_lastMobilePushFrameAt!);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _HudPanelHeader(
          title: '设备',
          subtitle:
              '设备 ${_status?.deviceStatus ?? _health?.status ?? '未知'} · 最近刷新 ${_formatUpdatedAt()}',
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            _HudStatusBadge(
              label: '会话 ${_status?.sessionOpened == true ? '已开' : '未开'}',
              active: _status?.sessionOpened == true,
            ),
            _HudStatusBadge(
              label: 'AI 锁 ${_status?.aiLockEnabled == true ? '开' : '关'}',
              active: _status?.aiLockEnabled == true,
            ),
            _HudStatusBadge(
              label: _webRtcSession != null
                  ? 'WebRTC 推流'
                  : 'WebSocket $_mobilePushFrameCount 帧',
              active: _isMobilePushEnabled,
            ),
          ],
        ),
        const SizedBox(height: 12),
        _buildHudTextField(
          label: '树莓派 API 地址',
          hintText: 'http://192.168.1.100:8001',
          controller: _baseUrlController,
        ),
        const SizedBox(height: 10),
        _buildHudTextField(
          label: '视频流地址',
          hintText: 'mobile_push / rtsp://...',
          controller: _streamUrlController,
        ),
        const SizedBox(height: 10),
        _buildHudTextField(
          label: '会话码',
          hintText: 'MOBILE_20260425_011000',
          controller: _sessionCodeController,
        ),
        const SizedBox(height: 12),
        _buildHudOverlayOptions(context),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: <Widget>[
            _HudActionChip(
              icon: Icons.health_and_safety_outlined,
              label: '健康',
              onTap: _isBusy ? null : _checkHealth,
            ),
            _HudActionChip(
              icon: Icons.fact_check_outlined,
              label: '诊断',
              onTap: _isBusy ? null : _runConnectionDiagnostics,
            ),
            _HudActionChip(
              icon: Icons.radar_outlined,
              label: '刷新',
              onTap: _isBusy ? null : _fetchStatus,
            ),
            _HudActionChip(
              icon: Icons.video_settings_outlined,
              label: '切换视频源',
              onTap: _isBusy ? null : _restartDeviceStream,
            ),
            _HudActionChip(
              icon: Icons.camera_alt_outlined,
              label: '返回拍摄',
              onTap: _returnToCameraPage,
            ),
            _HudActionChip(
              icon: _isMobilePushEnabled
                  ? Icons.videocam_outlined
                  : Icons.mobile_screen_share_outlined,
              label: _isMobilePushEnabled ? '停止推流' : '手机推流',
              onTap: _isBusy || _isStartingMobilePush
                  ? null
                  : () {
                      if (_isMobilePushEnabled) {
                        unawaited(_stopMobilePush());
                      } else {
                        unawaited(_startMobilePush());
                      }
                    },
            ),
            _HudActionChip(
              icon: Icons.cameraswitch_outlined,
              label: _mobilePushSwitchTargetLabel(),
              onTap:
                  _isBusy ||
                      _isStartingMobilePush ||
                      _isHandlingMobilePushOrientationChange
                  ? null
                  : () => unawaited(_switchMobilePushCamera()),
            ),
            _HudActionChip(
              icon: Icons.swap_horiz_outlined,
              label: _landscapeControlsOnLeft ? '横屏左手' : '横屏右手',
              onTap: () => _setLandscapeControlsSide(!_landscapeControlsOnLeft),
            ),
          ],
        ),
        if (_diagnosticMessage != null) ...<Widget>[
          const SizedBox(height: 10),
          Text(
            _diagnosticMessage!,
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.72),
              height: 1.35,
            ),
          ),
        ],
        if (_recentConnections.isNotEmpty) ...<Widget>[
          const SizedBox(height: 12),
          Text(
            '最近连接',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _recentConnections
                .map(
                  (preset) => _HudActionChip(
                    icon: Icons.history_outlined,
                    label: preset.baseUrl,
                    onTap: _isBusy
                        ? null
                        : () => _applyConnectionPreset(preset),
                  ),
                )
                .toList(growable: false),
          ),
        ],
        if (_mobilePushErrorMessage != null) ...<Widget>[
          const SizedBox(height: 10),
          Text(
            _mobilePushErrorMessage!,
            style: const TextStyle(
              color: Color(0xFFFFB7A8),
              fontWeight: FontWeight.w700,
              height: 1.35,
            ),
          ),
        ] else if (_isMobilePushEnabled) ...<Widget>[
          const SizedBox(height: 10),
          Text(
            '最近推流帧：$lastFrame',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.72)),
          ),
        ],
      ],
    );
  }

  Widget _buildHudOverlayOptions(BuildContext context) {
    final overlay =
        _status?.overlayStatus ?? const DeviceOverlayStatusSummary();
    final canUpdate = _status?.sessionOpened == true && !_isBusy;

    Widget option({
      required IconData icon,
      required String label,
      required String key,
      required bool selected,
    }) {
      return _HudActionChip(
        icon: icon,
        label: label,
        selected: selected,
        onTap: canUpdate ? () => _setOverlayOption(key, !selected) : null,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          '画面辅助',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            option(
              icon: Icons.layers_outlined,
              label: '总开关',
              key: 'enabled',
              selected: overlay.enabled,
            ),
            option(
              icon: Icons.accessibility_new_outlined,
              label: '人体框',
              key: 'show_live_person_bbox',
              selected: overlay.showLivePersonBbox,
            ),
            option(
              icon: Icons.account_tree_outlined,
              label: '人体骨骼',
              key: 'show_live_body_skeleton',
              selected: overlay.showLiveBodySkeleton,
            ),
            option(
              icon: Icons.back_hand_outlined,
              label: '手部骨骼',
              key: 'show_live_hands',
              selected: overlay.showLiveHands,
            ),
            option(
              icon: Icons.crop_free_outlined,
              label: '模板框',
              key: 'show_template_bbox',
              selected: overlay.showTemplateBbox,
            ),
            option(
              icon: Icons.schema_outlined,
              label: '模板骨骼',
              key: 'show_template_skeleton',
              selected: overlay.showTemplateSkeleton,
            ),
            option(
              icon: Icons.center_focus_weak_outlined,
              label: '锁定位框',
              key: 'show_ai_lock_box',
              selected: overlay.showAiLockBox,
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          canUpdate ? '这些开关会直接影响树莓派返回的预览叠加。' : '打开设备会话后可以调整画面辅助显示。',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.62),
            fontWeight: FontWeight.w600,
            height: 1.35,
          ),
        ),
      ],
    );
  }

  Widget _buildFloatingJoystick(
    BuildContext context, {
    required bool isLandscape,
    required Size bounds,
  }) {
    if (_isHudHidden || !_isJoystickVisible) {
      return const SizedBox.shrink();
    }
    final size = isLandscape ? 118.0 : 132.0;
    final anchor = _effectiveJoystickAnchor(isLandscape);
    final left = (anchor.dx * bounds.width - size / 2)
        .clamp(12.0, math.max(12.0, bounds.width - size - 12))
        .toDouble();
    final top = (anchor.dy * bounds.height - size / 2)
        .clamp(92.0, math.max(92.0, bounds.height - size - 96))
        .toDouble();

    return Positioned(
      left: left,
      top: top,
      child: _HudJoystick(
        size: size,
        vector: _joystickVector,
        enabled: _status?.sessionOpened == true && !_isBusy,
        onDragHandleUpdate: (details) => _moveJoystickAnchor(details, bounds),
        onJoystickUpdate: (localPosition) =>
            _updateJoystickVector(localPosition, size),
        onJoystickEnd: _endJoystickGesture,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: OrientationBuilder(
        builder: (BuildContext context, Orientation orientation) {
          final isLandscape = orientation == Orientation.landscape;
          _syncScreenOrientation(orientation);
          return LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              final bounds = Size(constraints.maxWidth, constraints.maxHeight);
              return Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  _buildDevicePreviewBackdrop(context),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: <Color>[
                          Colors.black.withValues(alpha: 0.58),
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.72),
                        ],
                        stops: const <double>[0, 0.46, 1],
                      ),
                    ),
                  ),
                  _buildHudTopBar(context, isLandscape: isLandscape),
                  _buildPreviewBadge(context, isLandscape: isLandscape),
                  _buildHudPanel(context, isLandscape: isLandscape),
                  _buildFloatingJoystick(
                    context,
                    isLandscape: isLandscape,
                    bounds: bounds,
                  ),
                  _buildHudMessages(context, isLandscape: isLandscape),
                  _buildHudBottomNav(context, isLandscape: isLandscape),
                  if (_isBusy)
                    Positioned(
                      left: 0,
                      right: 0,
                      top: 0,
                      child: LinearProgressIndicator(
                        minHeight: 3,
                        color: const Color(0xFF9BE7DD),
                        backgroundColor: Colors.white.withValues(alpha: 0.12),
                      ),
                    ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildWebRtcPreview() {
    final session = _webRtcSession;
    if (session == null) {
      return const SizedBox.shrink();
    }
    return RTCVideoView(
      session.remoteRenderer,
      objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
    );
  }
}

class _InputBlock extends StatelessWidget {
  const _InputBlock({
    required this.label,
    required this.hintText,
    required this.controller,
  });

  final String label;
  final String hintText;
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          decoration: InputDecoration(
            hintText: hintText,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
          ),
        ),
      ],
    );
  }
}

class _ManualMoveHoldButton extends StatelessWidget {
  const _ManualMoveHoldButton({
    required this.enabled,
    required this.onStart,
    required this.onStop,
    required this.icon,
    required this.label,
  });

  final bool enabled;
  final VoidCallback onStart;
  final VoidCallback onStop;
  final Widget icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: enabled ? (_) => onStart() : null,
      onPointerUp: enabled ? (_) => onStop() : null,
      onPointerCancel: enabled ? (_) => onStop() : null,
      child: FilledButton.tonalIcon(
        onPressed: enabled ? () {} : null,
        icon: icon,
        label: Text(label),
      ),
    );
  }
}

class _InfoSection extends StatelessWidget {
  const _InfoSection({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class _ExpandableInfoSection extends StatelessWidget {
  const _ExpandableInfoSection({
    required this.title,
    required this.child,
    this.initiallyExpanded = false,
  });

  final String title;
  final Widget child;
  final bool initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: initiallyExpanded,
          tilePadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 2),
          childrenPadding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
          title: Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          children: <Widget>[child],
        ),
      ),
    );
  }
}

class _NoticeCard extends StatelessWidget {
  const _NoticeCard({
    required this.message,
    required this.backgroundColor,
    required this.textColor,
  });

  final String message;
  final Color backgroundColor;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Text(
          message,
          style: TextStyle(color: textColor, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

class _ModeChip extends StatelessWidget {
  const _ModeChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF0D5C63) : Colors.white10,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? const Color(0xFF0D5C63) : Colors.black12,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : const Color(0xFF17313A),
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.label,
    required this.value,
    required this.active,
  });

  final String label;
  final String value;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: active ? const Color(0x140D5C63) : const Color(0xFFF4F1EA),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: active ? const Color(0xFF0D5C63) : const Color(0xFFD3C7B8),
        ),
      ),
      child: Text(
        '$label: $value',
        style: TextStyle(
          color: active ? const Color(0xFF0D5C63) : const Color(0xFF6A6258),
          fontWeight: FontWeight.w700,
          fontSize: 12.5,
        ),
      ),
    );
  }
}

class _PreviewEmptyState extends StatelessWidget {
  const _PreviewEmptyState({
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(icon, size: 34, color: const Color(0xFF0D5C63)),
            const SizedBox(height: 12),
            Text(
              title,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: const Color(0xFF17313A),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              description,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: const Color(0xFF5A6B70),
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _HudEmptyPreview extends StatelessWidget {
  const _HudEmptyPreview({
    this.icon = Icons.videocam_off_outlined,
    this.title = '等待打开设备会话',
    this.description = '会话打开后，这里会显示设备返回的画面。',
  });

  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF080D0F),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icon, size: 42, color: Colors.white.withValues(alpha: 0.72)),
              const SizedBox(height: 14),
              Text(
                title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                description,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.white.withValues(alpha: 0.68),
                  height: 1.45,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HudGlass extends StatelessWidget {
  const _HudGlass({
    required this.child,
    this.compact = false,
    this.tint = const Color(0xA8141D20),
  });

  final Widget child;
  final bool compact;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: tint,
        borderRadius: BorderRadius.circular(compact ? 18 : 24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.24),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 10 : 16,
          vertical: compact ? 8 : 14,
        ),
        child: child,
      ),
    );
  }
}

class _HudCircleButton extends StatelessWidget {
  const _HudCircleButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.13),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
          ),
          child: Icon(icon, color: Colors.white, size: 22),
        ),
      ),
    );
  }
}

class _HudStatusBadge extends StatelessWidget {
  const _HudStatusBadge({required this.label, required this.active});

  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: active
            ? const Color(0x883BC8A4)
            : Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: active
              ? const Color(0xFF9BE7DD)
              : Colors.white.withValues(alpha: 0.2),
        ),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
          fontSize: 12,
        ),
      ),
    );
  }
}

class _HudNavButton extends StatelessWidget {
  const _HudNavButton({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            color: selected
                ? const Color(0x773BC8A4)
                : Colors.white.withValues(alpha: 0.03),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                icon,
                size: 21,
                color: selected ? const Color(0xFFBDF6EF) : Colors.white,
              ),
              const SizedBox(height: 3),
              Text(
                label,
                style: TextStyle(
                  color: selected
                      ? const Color(0xFFBDF6EF)
                      : Colors.white.withValues(alpha: 0.78),
                  fontWeight: FontWeight.w800,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HudPanelHeader extends StatelessWidget {
  const _HudPanelHeader({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          title,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Colors.white.withValues(alpha: 0.68),
            height: 1.35,
          ),
        ),
      ],
    );
  }
}

class _HudActionChip extends StatelessWidget {
  const _HudActionChip({
    required this.label,
    required this.onTap,
    this.icon,
    this.selected = false,
  });

  final IconData? icon;
  final String label;
  final VoidCallback? onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? const Color(0x8847D7B4)
              : Colors.white.withValues(alpha: enabled ? 0.13 : 0.06),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected
                ? const Color(0xFFBDF6EF)
                : Colors.white.withValues(alpha: 0.18),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (icon != null) ...<Widget>[
              Icon(
                icon,
                size: 17,
                color: Colors.white.withValues(alpha: enabled ? 0.94 : 0.42),
              ),
              const SizedBox(width: 7),
            ],
            Text(
              label,
              style: TextStyle(
                color: Colors.white.withValues(alpha: enabled ? 0.94 : 0.42),
                fontWeight: FontWeight.w800,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HudJoystick extends StatelessWidget {
  const _HudJoystick({
    required this.size,
    required this.vector,
    required this.enabled,
    required this.onDragHandleUpdate,
    required this.onJoystickUpdate,
    required this.onJoystickEnd,
  });

  final double size;
  final Offset vector;
  final bool enabled;
  final ValueChanged<DragUpdateDetails> onDragHandleUpdate;
  final ValueChanged<Offset> onJoystickUpdate;
  final VoidCallback onJoystickEnd;

  @override
  Widget build(BuildContext context) {
    final knobTravel = size * 0.28;
    final knobSize = size * 0.36;
    final knobOffset = Offset(vector.dx * knobTravel, vector.dy * knobTravel);

    return _HudGlass(
      tint: const Color(0x9810181C),
      child: SizedBox(
        width: size,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanUpdate: onDragHandleUpdate,
              child: Container(
                width: 54,
                height: 18,
                alignment: Alignment.center,
                child: Container(
                  width: 34,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.46),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
            ),
            SizedBox(
              width: size,
              height: size,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanDown: enabled
                    ? (details) => onJoystickUpdate(details.localPosition)
                    : null,
                onPanUpdate: enabled
                    ? (details) => onJoystickUpdate(details.localPosition)
                    : null,
                onPanEnd: enabled ? (_) => onJoystickEnd() : null,
                onPanCancel: enabled ? onJoystickEnd : null,
                child: Stack(
                  alignment: Alignment.center,
                  children: <Widget>[
                    Container(
                      width: size * 0.86,
                      height: size * 0.86,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withValues(alpha: 0.08),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.2),
                          width: 1.5,
                        ),
                      ),
                    ),
                    Icon(
                      Icons.add,
                      color: Colors.white.withValues(alpha: 0.20),
                      size: size * 0.42,
                    ),
                    Transform.translate(
                      offset: knobOffset,
                      child: Container(
                        width: knobSize,
                        height: knobSize,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: enabled
                              ? const Color(0xDDBDF6EF)
                              : Colors.white.withValues(alpha: 0.16),
                          boxShadow: <BoxShadow>[
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.24),
                              blurRadius: 16,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: Icon(
                          Icons.control_camera_outlined,
                          color: enabled
                              ? const Color(0xFF0D3F43)
                              : Colors.white.withValues(alpha: 0.36),
                          size: knobSize * 0.48,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryLine extends StatelessWidget {
  const _SummaryLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return RichText(
      text: TextSpan(
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: const Color(0xFF6A6258),
          height: 1.35,
        ),
        children: <InlineSpan>[
          TextSpan(
            text: '$label：',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          TextSpan(text: value),
        ],
      ),
    );
  }
}

class _TimelineTile extends StatelessWidget {
  const _TimelineTile({
    required this.title,
    required this.subtitle,
    required this.accentColor,
  });

  final String title;
  final String subtitle;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 10,
            height: 10,
            margin: const EdgeInsets.only(top: 6),
            decoration: BoxDecoration(
              color: accentColor,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF6A6258),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AiScanConfig {
  const _AiScanConfig({
    required this.panRange,
    required this.tiltRange,
    required this.panStep,
    required this.tiltStep,
    required this.maxCandidates,
    required this.settleSeconds,
    required this.delaySeconds,
  });

  final double panRange;
  final double tiltRange;
  final double panStep;
  final double tiltStep;
  final int maxCandidates;
  final double settleSeconds;
  final double delaySeconds;
}

class _AiScanConfigDialog extends StatefulWidget {
  const _AiScanConfigDialog({required this.title, required this.includeDelay});

  final String title;
  final bool includeDelay;

  @override
  State<_AiScanConfigDialog> createState() => _AiScanConfigDialogState();
}

class _AiScanConfigDialogState extends State<_AiScanConfigDialog> {
  late final TextEditingController _panRangeController;
  late final TextEditingController _tiltRangeController;
  late final TextEditingController _panStepController;
  late final TextEditingController _tiltStepController;
  late final TextEditingController _maxCandidatesController;
  late final TextEditingController _settleController;
  late final TextEditingController _delayController;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _panRangeController = TextEditingController(text: '6');
    _tiltRangeController = TextEditingController(text: '3');
    _panStepController = TextEditingController(text: '4');
    _tiltStepController = TextEditingController(text: '3');
    _maxCandidatesController = TextEditingController(text: '5');
    _settleController = TextEditingController(text: '0.5');
    _delayController = TextEditingController(text: '0');
  }

  @override
  void dispose() {
    _panRangeController.dispose();
    _tiltRangeController.dispose();
    _panStepController.dispose();
    _tiltStepController.dispose();
    _maxCandidatesController.dispose();
    _settleController.dispose();
    _delayController.dispose();
    super.dispose();
  }

  void _submit() {
    final panRange = double.tryParse(_panRangeController.text.trim());
    final tiltRange = double.tryParse(_tiltRangeController.text.trim());
    final panStep = double.tryParse(_panStepController.text.trim());
    final tiltStep = double.tryParse(_tiltStepController.text.trim());
    final maxCandidates = int.tryParse(_maxCandidatesController.text.trim());
    final settleSeconds = double.tryParse(_settleController.text.trim());
    final delaySeconds = double.tryParse(_delayController.text.trim()) ?? 0;

    if (panRange == null ||
        tiltRange == null ||
        panStep == null ||
        tiltStep == null ||
        maxCandidates == null ||
        settleSeconds == null) {
      setState(() {
        _errorMessage = '请填写有效数字。';
      });
      return;
    }
    if (panRange < 1 ||
        tiltRange < 1 ||
        panStep < 0.8 ||
        tiltStep < 0.8 ||
        maxCandidates < 2 ||
        maxCandidates > 9 ||
        settleSeconds < 0.1 ||
        delaySeconds < 0) {
      setState(() {
        _errorMessage = '参数超出树莓派允许范围，请调小或恢复默认值。';
      });
      return;
    }

    Navigator.of(context).pop(
      _AiScanConfig(
        panRange: panRange,
        tiltRange: tiltRange,
        panStep: panStep,
        tiltStep: tiltStep,
        maxCandidates: maxCandidates,
        settleSeconds: settleSeconds,
        delaySeconds: delaySeconds,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(child: _numberField('横向范围', _panRangeController)),
                const SizedBox(width: 10),
                Expanded(child: _numberField('纵向范围', _tiltRangeController)),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: <Widget>[
                Expanded(child: _numberField('横向步长', _panStepController)),
                const SizedBox(width: 10),
                Expanded(child: _numberField('纵向步长', _tiltStepController)),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: <Widget>[
                Expanded(child: _numberField('拍摄数量', _maxCandidatesController)),
                const SizedBox(width: 10),
                Expanded(child: _numberField('稳定等待', _settleController)),
              ],
            ),
            if (widget.includeDelay) ...<Widget>[
              const SizedBox(height: 10),
              _numberField('延迟秒数', _delayController),
            ],
            if (_errorMessage != null) ...<Widget>[
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _errorMessage!,
                  style: const TextStyle(
                    color: Color(0xFFB9442F),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _submit, child: const Text('启动')),
      ],
    );
  }

  Widget _numberField(String label, TextEditingController controller) {
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }
}

class _DeviceActionRecord {
  const _DeviceActionRecord({
    required this.category,
    required this.message,
    required this.createdAt,
  });

  final String category;
  final String message;
  final DateTime createdAt;
}

class _DeviceCaptureRecord {
  const _DeviceCaptureRecord({
    required this.path,
    required this.createdAt,
    required this.source,
    this.localPath,
    this.savedAt,
  });

  final String path;
  final DateTime createdAt;
  final String source;
  final String? localPath;
  final DateTime? savedAt;

  _DeviceCaptureRecord copyWith({
    String? path,
    DateTime? createdAt,
    String? source,
    String? localPath,
    DateTime? savedAt,
  }) {
    return _DeviceCaptureRecord(
      path: path ?? this.path,
      createdAt: createdAt ?? this.createdAt,
      source: source ?? this.source,
      localPath: localPath ?? this.localPath,
      savedAt: savedAt ?? this.savedAt,
    );
  }
}

class _DeviceConnectionPreset {
  const _DeviceConnectionPreset({
    required this.baseUrl,
    required this.streamUrl,
    required this.sessionCode,
    required this.updatedAt,
  });

  final String baseUrl;
  final String streamUrl;
  final String sessionCode;
  final DateTime updatedAt;

  String toStorageString() {
    return jsonEncode(<String, dynamic>{
      'base_url': baseUrl,
      'stream_url': streamUrl,
      'session_code': sessionCode,
      'updated_at': updatedAt.toIso8601String(),
    });
  }

  static _DeviceConnectionPreset? tryParse(String raw) {
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      return _DeviceConnectionPreset(
        baseUrl: json['base_url'] as String? ?? '',
        streamUrl: json['stream_url'] as String? ?? '',
        sessionCode: json['session_code'] as String? ?? '',
        updatedAt: DateTime.parse(
          json['updated_at'] as String? ?? DateTime.now().toIso8601String(),
        ),
      );
    } catch (_) {
      return null;
    }
  }
}
