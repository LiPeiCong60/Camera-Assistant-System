import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/ai_task_summary.dart';
import '../../models/capture_record.dart';
import '../../models/device_health_summary.dart';
import '../../models/device_link_result.dart';
import '../../models/device_status_summary.dart';
import '../../models/template_summary.dart';
import '../../services/api_client.dart';
import '../../services/app_config.dart';
import '../../services/device_api_service.dart';
import '../../services/mobile_api_service.dart';
import '../template/template_photo_dialog.dart';

class DeviceLinkPage extends StatefulWidget {
  const DeviceLinkPage({
    super.key,
    required this.mobileApiService,
    required this.accessToken,
    this.initialTemplate,
    this.initialSessionCode,
    this.entryLabel,
  });

  final MobileApiService mobileApiService;
  final String accessToken;
  final TemplateSummary? initialTemplate;
  final String? initialSessionCode;
  final String? entryLabel;

  @override
  State<DeviceLinkPage> createState() => _DeviceLinkPageState();
}

class _DeviceLinkPageState extends State<DeviceLinkPage> {
  static const String _prefsBaseUrlKey = 'device_link.base_url';
  static const String _prefsStreamUrlKey = 'device_link.stream_url';
  static const String _prefsAutoRefreshKey = 'device_link.auto_refresh';
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
  late final TextEditingController _baseUrlController;
  late final TextEditingController _streamUrlController;
  late final TextEditingController _sessionCodeController;

  List<TemplateSummary> _templates = const <TemplateSummary>[];
  TemplateSummary? _selectedTemplate;
  DeviceHealthSummary? _health;
  DeviceStatusSummary? _status;

  bool _isBusy = false;
  bool _isLoadingTemplates = false;
  bool _isCreatingDemoTemplate = false;
  bool _isDeletingTemplate = false;
  bool _autoRefreshEnabled = true;
  String? _errorMessage;
  String? _syncMessage;
  String? _lastCapturePath;
  AiTaskSummary? _lastBackendAiTask;
  DateTime? _lastStatusUpdatedAt;
  Timer? _pollTimer;
  Timer? _persistTimer;
  Timer? _manualMoveRepeatTimer;
  bool _isManualMoveSending = false;
  String? _activeManualMoveAction;
  WebSocket? _previewSocket;
  Uint8List? _latestPreviewFrameBytes;
  DateTime? _latestPreviewFrameAt;
  String? _previewStreamErrorMessage;
  WebSocket? _mobilePushSocket;
  CameraController? _mobilePushCameraController;
  List<CameraDescription> _mobilePushCameras = const <CameraDescription>[];
  int _mobilePushRotationDegrees = 0;
  bool _isMobilePushEnabled = false;
  bool _isStartingMobilePush = false;
  bool _isPushingMobileFrame = false;
  bool _mobilePushConfigSent = false;
  int _mobilePushFrameCount = 0;
  int _lastMobilePushFrameSentAtMs = 0;
  int _lastMobilePushUiUpdateAtMs = 0;
  DateTime? _lastMobilePushFrameAt;
  String? _mobilePushErrorMessage;
  final List<_DeviceActionRecord> _actionRecords = <_DeviceActionRecord>[];
  final List<_DeviceCaptureRecord> _captureRecords = <_DeviceCaptureRecord>[];
  List<_DeviceConnectionPreset> _recentConnections =
      const <_DeviceConnectionPreset>[];

  @override
  void initState() {
    super.initState();
    _baseUrlController = TextEditingController(
      text: AppConfig.deviceApiBaseUrl,
    );
    _streamUrlController = TextEditingController(
      text: _mobilePushStreamUrl,
    );
    _sessionCodeController = TextEditingController(
      text: widget.initialSessionCode ?? _buildSessionCode(),
    );
    _baseUrlController.addListener(_scheduleDraftPersist);
    _streamUrlController.addListener(_scheduleDraftPersist);
    _loadTemplates();
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
    _baseUrlController.removeListener(_scheduleDraftPersist);
    _streamUrlController.removeListener(_scheduleDraftPersist);
    _baseUrlController.dispose();
    _streamUrlController.dispose();
    _sessionCodeController.dispose();
    super.dispose();
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

  // ignore: unused_element
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
        _syncMessage = '已新增模板并选中：${template.name}';
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

  Future<void> _openSession() async {
    await _runAction(() async {
      final status = await _deviceApiService.openSession(
        baseUrl: _baseUrlController.text,
        sessionCode: _sessionCodeController.text.trim(),
        streamUrl: _streamUrlController.text.trim(),
      );
      setState(() {
        _status = status;
        _lastStatusUpdatedAt = DateTime.now();
      });
      unawaited(_startPreviewStream());
      await _rememberCurrentConnection();
      await _refreshStatusSilently();
      await _refreshHealthSilently();
    }, successMessage: '设备会话已打开。');
  }

  Future<void> _closeSession() async {
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
        if (!Platform.isAndroid) {
          throw const ApiException('手机画面推送当前优先支持 Android / 安卓模拟器。');
        }
        if (_mobilePushCameras.isEmpty) {
          _mobilePushCameras = await availableCameras();
        }
        if (_mobilePushCameras.isEmpty) {
          throw const ApiException('当前设备没有可用摄像头，无法推送画面。');
        }

        final camera = _mobilePushCameras.firstWhere(
          (item) => item.lensDirection == CameraLensDirection.back,
          orElse: () => _mobilePushCameras.first,
        );
        _mobilePushRotationDegrees = camera.sensorOrientation;
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
              _setMobilePushError('手机画面推送连接异常，请检查树莓派地址与网络。');
            }
          },
          onDone: () {
            if (_isMobilePushEnabled) {
              _setMobilePushError('手机画面推送连接已断开。');
            }
          },
          cancelOnError: false,
        );
        await controller.startImageStream(_handleMobilePushFrame);
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
    }, successMessage: '手机画面推送已启动。');
  }

  Future<void> _stopMobilePush({bool silent = false}) async {
    _isMobilePushEnabled = false;
    _isPushingMobileFrame = false;
    _mobilePushConfigSent = false;
    _lastMobilePushFrameSentAtMs = 0;
    _lastMobilePushUiUpdateAtMs = 0;

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
      if (!_mobilePushConfigSent) {
        socket.add(
          jsonEncode(<String, dynamic>{
            'type': 'config',
            'format': 'nv21',
            'width': image.width,
            'height': image.height,
            'rotation_degrees': _mobilePushRotationDegrees,
          }),
        );
        _mobilePushConfigSent = true;
      }
      final frameBytes = _encodeCameraImageAsNv21(image);
      if (frameBytes == null) {
        _setMobilePushError('当前相机帧格式暂不支持，请确认使用 Android 摄像头。');
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
      _setMobilePushError('手机画面推送失败，请检查摄像头权限与设备网络。');
    } finally {
      _isPushingMobileFrame = false;
    }
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
    final rawBaseUrl = _baseUrlController.text.trim();
    final normalizedBaseUrl = rawBaseUrl.endsWith('/')
        ? rawBaseUrl.substring(0, rawBaseUrl.length - 1)
        : rawBaseUrl;
    final withoutApi = normalizedBaseUrl.endsWith('/api')
        ? normalizedBaseUrl.substring(0, normalizedBaseUrl.length - 4)
        : normalizedBaseUrl;
    final uri = Uri.parse(withoutApi);
    final scheme = uri.scheme == 'https' ? 'wss' : 'ws';
    final basePath = uri.path.endsWith('/')
        ? uri.path.substring(0, uri.path.length - 1)
        : uri.path;
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    return uri.replace(
      scheme: scheme,
      path: '$basePath$normalizedPath',
    );
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
              _previewStreamErrorMessage = '实时预览连接异常，已回退到静态预览。';
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
          _previewStreamErrorMessage = '实时预览连接失败，已回退到静态预览。';
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
    _manualMoveRepeatTimer?.cancel();
    unawaited(_sendManualMovePulse(action));
    _manualMoveRepeatTimer = Timer.periodic(_manualMoveRepeatInterval, (_) {
      if (_activeManualMoveAction != action) {
        return;
      }
      unawaited(_sendManualMovePulse(action));
    });
  }

  void _stopManualMoveRepeat({bool refreshStatus = true}) {
    _activeManualMoveAction = null;
    _manualMoveRepeatTimer?.cancel();
    _manualMoveRepeatTimer = null;
    if (refreshStatus) {
      unawaited(_refreshStatusAfterManualMove());
    }
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
        _errorMessage = '手动控制发送失败，请检查设备连接。';
        _addActionRecord('error', '手动控制发送失败，请检查设备连接。');
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
    final template = _selectedTemplate;
    if (template == null) {
      setState(() {
        _errorMessage = '请先选择一个模板。';
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

  Future<void> _triggerCapture() async {
    await _runAction(() async {
      final capturePath = await _deviceApiService.triggerCapture(
        baseUrl: _baseUrlController.text,
      );
      await _refreshStatusSilently();
      setState(() {
        _lastCapturePath = capturePath;
        _captureRecords.insert(
          0,
          _DeviceCaptureRecord(
            path: capturePath,
            createdAt: DateTime.now(),
            source: 'device_runtime',
          ),
        );
        if (_captureRecords.length > 8) {
          _captureRecords.removeRange(8, _captureRecords.length);
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
    final preferredTemplateId = _selectedTemplate?.id ?? widget.initialTemplate?.id;
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
    });
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
          _errorMessage = '自动刷新失败，请手动点击状态刷新后重试。';
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
                    style: Theme.of(
                      context,
                    ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                _StatusPill(label: '当前模式', value: modeLabel, active: _status != null),
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
                            if (_latestPreviewFrameBytes != null)
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
                                        description: '已打开设备会话，正在尝试连接实时预览。',
                                      );
                                    },
                                errorBuilder:
                                    (
                                      BuildContext context,
                                      Object error,
                                      StackTrace? stackTrace,
                                    ) {
                                      return const _PreviewEmptyState(
                                        icon: Icons.wifi_tethering_error_rounded,
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
                                  _latestPreviewFrameAt == null
                                      ? '静态预览'
                                      : '实时预览 ${_formatClock(_latestPreviewFrameAt!)}',
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
                          description: '会话打开后，这里会显示设备返回的最新预览帧，方便你先看画面，再做控制。',
                        ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '视频流地址：${_status?.streamUrl ?? _streamUrlController.text.trim()}',
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
    final limited = merged.take(6).toList(growable: false);
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
      return '设备会话运行中';
    }
    if (_health != null) {
      return '设备服务可访问';
    }
    return '等待连接设备';
  }

  String _statusDescription() {
    if (_status?.sessionOpened == true) {
      return '当前会话 ${_status?.sessionCode ?? '-'} 已打开，可继续执行控制、模板下发和 AI 动作。';
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
              label: 'AI 锁机位',
              value: _status?.aiLockEnabled == true ? '开启' : '关闭',
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

  // ignore: unused_element
  Widget _buildPreviewPlaceholderSection(BuildContext context) {
    final hasSession = _status?.sessionOpened == true;
    final description = hasSession
        ? '当前会话已经打开。下一阶段会在这里接入设备画面预览；现在先用状态回显和控制链路确认联动正常。'
        : '会话未打开时，这里显示设备画面预览的空状态。先打开会话，后续再接入真实预览能力。';

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
                          hasSession ? '预览区占位已准备' : '等待打开设备会话',
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
              '视频流地址：${_status?.streamUrl ?? _streamUrlController.text.trim()}',
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
        ? '已推送 $_mobilePushFrameCount 帧，最近一帧 $lastFrame。'
        : '使用当前 Android 摄像头向树莓派推送 WebSocket 视频帧，树莓派会以 mobile_push 作为视频源。';

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
            tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
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
            '任务摘要：${_lastBackendAiTask!.resultSummary ?? '-'}',
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
          summary: '当前：${_modeDisplayLabel(_status?.mode ?? 'MANUAL')}',
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
          summary: '当前：${_status?.followMode == null ? '未设置' : _followModeDisplayLabel(_status!.followMode!)}',
          description: '选择自动跟随时优先识别的目标区域。',
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
              ? '包含抓拍、示例 AI、后端 AI 下发'
              : '最近任务：${_lastBackendAiTask!.status}',
          description: '集中执行抓拍、示例 AI 动作，以及应用后端返回的 AI 结果。',
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
          '连接参数会自动保存在本机。修改后可直接回到上方“手动控制”区执行健康检查或打开会话。',
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
                    Text(
                      '${preset.streamUrl} · ${_formatDateTime(preset.updatedAt)}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
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
                  onPressed: _isDeletingTemplate ? null : _deleteSelectedTemplate,
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
                            _syncMessage = '已选择模板：${template.name}';
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
              : '自动刷新已暂停，请手动点击“刷新状态”或执行任意控制动作更新页面。',
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
              subtitle:
                  '${_captureSourceLabel(record.source)} · ${_formatDateTime(record.createdAt)}',
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
              subtitle:
                  '${_actionCategoryLabel(record.category)} · ${_formatDateTime(record.createdAt)}',
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
        Text('设备编号：${_health!.deviceCode}'),
        const SizedBox(height: 6),
        Text('状态：${_health!.status}'),
        const SizedBox(height: 6),
        Text('服务版本：${_health!.serviceVersion}'),
        const SizedBox(height: 6),
        Text('会话编号：${_health!.sessionCode ?? '-'}'),
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
        Text('会话是否打开：${_status!.sessionOpened}'),
        const SizedBox(height: 6),
        Text('会话编号：${_status!.sessionCode ?? '-'}'),
        const SizedBox(height: 6),
        Text('视频流地址：${_status!.streamUrl ?? '-'}'),
        const SizedBox(height: 6),
        Text('运行模式：${_status!.mode}'),
        const SizedBox(height: 6),
        Text('跟随模式：${_status!.followMode ?? '-'}'),
        const SizedBox(height: 6),
        Text('设备状态：${_status!.deviceStatus}'),
        const SizedBox(height: 6),
        Text('当前水平角：${_status!.currentPan.toStringAsFixed(2)}'),
        const SizedBox(height: 6),
        Text('当前俯仰角：${_status!.currentTilt.toStringAsFixed(2)}'),
        const SizedBox(height: 6),
        Text('处理循环运行中：${_status!.loopRunning}'),
        const SizedBox(height: 6),
        Text('选中模板编号：${_status!.selectedTemplateId?.toString() ?? '-'}'),
        const SizedBox(height: 6),
        Text('AI 锁机位开启：${_status!.aiLockEnabled}'),
        const SizedBox(height: 6),
        Text('AI 锁机位拟合分：${_status!.aiLockFitScore.toStringAsFixed(2)}'),
        const SizedBox(height: 6),
        Text('AI 锁机位目标框：${_status!.aiLockTargetBoxNorm?.join(', ') ?? '-'}'),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;

    return Scaffold(
      appBar: AppBar(
        title: const Text('设备联动'),
        leading: IconButton(
          onPressed: _returnToCameraPage,
          icon: const Icon(Icons.arrow_back),
        ),
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          isLandscape ? 16 : 20,
          isLandscape ? 12 : 18,
          isLandscape ? 16 : 20,
          isLandscape ? 20 : 28,
        ),
        children: <Widget>[
          _buildPreviewSection(context),
          const SizedBox(height: 18),
          _buildCoreControlsSection(context),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: _returnToCameraPage,
            icon: const Icon(Icons.camera_alt_outlined),
            label: const Text('返回拍照页并同步'),
          ),
          const SizedBox(height: 18),
          _ExpandableInfoSection(
            title: '更多设置与记录',
            child: Column(
              children: <Widget>[
                _ExpandableInfoSection(
                  title: '连接设置',
                  initiallyExpanded:
                      _status?.sessionOpened != true &&
                      _health == null &&
                      _recentConnections.isEmpty,
                  child: _buildConnectionSettingsContent(context),
                ),
                _ExpandableInfoSection(
                  title: '模板下发',
                  child: _buildTemplateDispatchContent(context),
                ),
                _ExpandableInfoSection(
                  title: '联动状态',
                  initiallyExpanded: _status?.sessionOpened == true,
                  child: _buildLinkStatusContent(context),
                ),
                _ExpandableInfoSection(
                  title: '最近抓拍',
                  child: _buildCaptureRecordsContent(context),
                ),
                _ExpandableInfoSection(
                  title: '操作时间线',
                  child: _buildActionTimelineContent(context),
                ),
                _ExpandableInfoSection(
                  title: '健康检查结果',
                  child: _buildHealthResultContent(),
                ),
                _ExpandableInfoSection(
                  title: '运行状态',
                  child: _buildRuntimeStatusContent(),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          if (_isBusy) ...<Widget>[
            const SizedBox(height: 6),
            const LinearProgressIndicator(minHeight: 3),
          ],
          if (_syncMessage != null) ...<Widget>[
            const SizedBox(height: 12),
            _NoticeCard(
              message: _syncMessage!,
              backgroundColor: const Color(0x142C6E49),
              textColor: const Color(0xFF2C6E49),
            ),
          ],
          if (_errorMessage != null) ...<Widget>[
            const SizedBox(height: 12),
            _NoticeCard(
              message: _errorMessage!,
              backgroundColor: const Color(0x149E2A2B),
              textColor: const Color(0xFF9E2A2B),
            ),
          ],
        ],
      ),
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
  });

  final String path;
  final DateTime createdAt;
  final String source;
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
