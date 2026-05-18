// ignore_for_file: unused_element, unused_element_parameter, unused_field

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/ai_task_summary.dart';
import '../../models/capture_record.dart';
import '../../models/capture_session_summary.dart';
import '../../models/device_health_summary.dart';
import '../../models/device_link_result.dart';
import '../../models/device_status_summary.dart';
import '../../models/device_template_summary.dart';
import '../../models/normalized_geometry.dart';
import '../../models/template_summary.dart';
import '../../services/api_client.dart';
import '../../services/app_config.dart';
import '../../services/device_api_service.dart';
import '../../services/device_webrtc_service.dart';
import '../../services/gallery_save_service.dart';
import '../../services/mobile_api_service.dart';
import '../../utils/score_formatter.dart';
import '../overlay/overlay_scene.dart';
import '../template/template_photo_dialog.dart';

part 'parts/ai_scan_config_dialog.dart';
part 'parts/ai_result_formatters.dart';
part 'parts/device_capture_helpers.dart';
part 'parts/device_capture_records.dart';
part 'parts/device_link_records.dart';
part 'parts/device_polling_helpers.dart';
part 'parts/device_display_helpers.dart';
part 'parts/device_hud_panels.dart';
part 'parts/device_link_url_helpers.dart';
part 'parts/device_link_widgets.dart';
part 'parts/mobile_push_camera_actions.dart';
part 'parts/mobile_push_socket_sender.dart';
part 'parts/mobile_push_state_actions.dart';
part 'parts/mobile_push_tools.dart';
part 'parts/manual_control_helpers.dart';
part 'parts/preview_stream_controller.dart';

class DeviceLinkPage extends StatefulWidget {
  const DeviceLinkPage({
    super.key,
    required this.mobileApiService,
    required this.accessToken,
    this.initialDeviceApiBaseUrl,
    this.initialTemplate,
    this.initialSessionCode,
    this.entryLabel,
    this.detailedSettingsBuilder,
  });

  final MobileApiService mobileApiService;
  final String accessToken;
  final String? initialDeviceApiBaseUrl;
  final TemplateSummary? initialTemplate;
  final String? initialSessionCode;
  final String? entryLabel;
  final WidgetBuilder? detailedSettingsBuilder;

  @override
  State<DeviceLinkPage> createState() => _DeviceLinkPageState();
}

enum _DeviceHudPanel { control, mode, ai, device }

class _DeviceLinkPageState extends State<DeviceLinkPage> {
  static const String _mobilePushStreamUrl = 'mobile_push';
  static const Duration _mobilePushFrameThrottle = Duration(milliseconds: 66);
  static const Duration _mobilePushHttpFallbackFrameThrottle = Duration(
    milliseconds: 220,
  );
  static const Duration _mobileTrackTargetThrottle = Duration(milliseconds: 80);
  static const Duration _recordingPreviewFrameThrottle = Duration(
    milliseconds: 66,
  );
  static const Duration _mobileAiFrameCacheThrottle = Duration(
    milliseconds: 280,
  );
  static const Duration _mobileAiFrameFreshTimeout = Duration(seconds: 2);
  static const Duration _mobileAiFrameMaxAge = Duration(seconds: 5);
  static const int _maxMobilePoseMissesBeforeClear = 6;
  static bool get _sendPhoneTrackTargetCommands => true;
  static const Duration _manualMoveRepeatInterval = Duration(milliseconds: 80);
  static const Duration _mobilePushSocketTimeout = Duration(seconds: 8);
  static const Duration _defaultPollInterval = Duration(seconds: 3);
  static const Duration _countdownPollInterval = Duration(seconds: 1);
  static const List<String> _modes = <String>[
    'MANUAL',
    'AUTO_TRACK',
    'SMART_COMPOSE',
  ];
  static const List<String> _followModes = <String>['shoulders', 'face'];
  static const List<({PoseLandmarkType start, PoseLandmarkType end})>
  _mobilePoseSkeletonPairs = <({PoseLandmarkType start, PoseLandmarkType end})>[
    (start: PoseLandmarkType.leftShoulder, end: PoseLandmarkType.rightShoulder),
    (start: PoseLandmarkType.leftShoulder, end: PoseLandmarkType.leftElbow),
    (start: PoseLandmarkType.leftElbow, end: PoseLandmarkType.leftWrist),
    (start: PoseLandmarkType.rightShoulder, end: PoseLandmarkType.rightElbow),
    (start: PoseLandmarkType.rightElbow, end: PoseLandmarkType.rightWrist),
    (start: PoseLandmarkType.leftShoulder, end: PoseLandmarkType.leftHip),
    (start: PoseLandmarkType.rightShoulder, end: PoseLandmarkType.rightHip),
    (start: PoseLandmarkType.leftHip, end: PoseLandmarkType.rightHip),
    (start: PoseLandmarkType.leftHip, end: PoseLandmarkType.leftKnee),
    (start: PoseLandmarkType.leftKnee, end: PoseLandmarkType.leftAnkle),
    (start: PoseLandmarkType.rightHip, end: PoseLandmarkType.rightKnee),
    (start: PoseLandmarkType.rightKnee, end: PoseLandmarkType.rightAnkle),
    (start: PoseLandmarkType.nose, end: PoseLandmarkType.leftEye),
    (start: PoseLandmarkType.nose, end: PoseLandmarkType.rightEye),
  ];

  final DeviceApiService _deviceApiService = const DeviceApiService();
  final DeviceWebRtcService _deviceWebRtcService = const DeviceWebRtcService();
  final GallerySaveService _gallerySaveService = const GallerySaveService();
  final _DeviceLinkPreferenceStore _preferenceStore =
      const _DeviceLinkPreferenceStore();
  final _DevicePreviewStreamController _previewStreamController =
      _DevicePreviewStreamController();
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
  double _sensitivity = 1.0;
  double _aiPanScanRange = 6;
  double _aiTiltScanRange = 3;
  double _aiScanStepDegrees = 4;
  int _aiMaxCandidates = 5;
  double _aiSettleSeconds = 0.5;
  double _aiStartDelaySeconds = 0;
  String? _errorMessage;
  String? _syncMessage;
  String? _diagnosticMessage;
  String? _lastCapturePath;
  String? _lastAiResultTitle;
  String? _lastAiResultBody;
  String? _preferredAiResultKind;
  DateTime? _lastAiResultAt;
  AiTaskSummary? _lastBackendAiTask;
  CaptureSessionSummary? _deviceHistorySession;
  DateTime? _lastStatusUpdatedAt;
  Timer? _pollTimer;
  Duration _pollInterval = _defaultPollInterval;
  Timer? _persistTimer;
  Timer? _manualMoveRepeatTimer;
  Timer? _hudMessageTimer;
  String? _hudMessageTimerKey;
  bool _isManualMoveSending = false;
  bool _manualMoveQueued = false;
  bool _manualStopQueued = false;
  String? _activeManualMoveAction;
  Offset? _activeManualMoveVector;
  _DeviceHudPanel? _activeHudPanel = _DeviceHudPanel.control;
  Offset _joystickAnchor = const Offset(0.5, 0.72);
  Offset _joystickVector = Offset.zero;
  bool _hasCustomJoystickAnchor = false;
  final _MobilePushSocketSender _mobilePushSocketSender =
      _MobilePushSocketSender();
  late final PoseDetector _mobileTrackPoseDetector = PoseDetector(
    options: PoseDetectorOptions(mode: PoseDetectionMode.stream),
  );
  DeviceWebRtcSession? _webRtcSession;
  CameraController? _mobilePushCameraController;
  CameraDescription? _mobilePushCamera;
  List<CameraDescription> _mobilePushCameras = const <CameraDescription>[];
  CameraLensDirection _mobilePushLensDirection = CameraLensDirection.back;
  int _mobilePushRotationDegrees = -1;
  bool _isMobilePushEnabled = false;
  bool _isStartingMobilePush = false;
  bool _isPushingMobileFrame = false;
  bool _isMobileAiScanning = false;
  bool _isProcessingMobileTrackTarget = false;
  bool _useMobilePushHttpFallback = false;
  _MobileVisionOverlay? _latestMobileVisionOverlay;
  bool _isSavingDeviceCapture = false;
  bool _isDeviceLinkCapturingPhoto = false;
  bool _isAnalyzingDeviceLinkCapture = false;
  bool _isDeviceLinkRecordingVideo = false;
  bool _isDeviceLinkRecordingPreviewPaused = false;
  bool _isFinalizingDeviceLinkVideo = false;
  Uint8List? _deviceLinkRecordingPreviewBytes;
  Uint8List? _latestMobileAiFrameBytes;
  bool _isHudAiResultExpanded = false;
  bool _isHudCapturesExpanded = false;
  bool _isHandlingMobilePushOrientationChange = false;
  bool _mobilePushConfigSent = false;
  int _mobilePushFrameCount = 0;
  int _lastMobilePushFrameSentAtMs = 0;
  int _lastMobilePushUiUpdateAtMs = 0;
  int _lastMobileTrackTargetSentAtMs = 0;
  int _lastRecordingPreviewFrameAtMs = 0;
  int _lastMobileAiFrameCachedAtMs = 0;
  int _latestMobileAiFrameAtMs = 0;
  int _consecutiveMobilePoseMisses = 0;
  DateTime? _lastMobilePushFrameAt;
  DateTime? _deviceLinkRecordingStartedAt;
  String? _mobilePushErrorMessage;
  Orientation? _lastScreenOrientation;
  final List<_DeviceActionRecord> _actionRecords = <_DeviceActionRecord>[];
  final List<_DeviceCaptureRecord> _captureRecords = <_DeviceCaptureRecord>[];
  final Map<String, int> _deviceHistoryCaptureIds = <String, int>{};
  final Set<String> _autoSavingDeviceCapturePaths = <String>{};
  final Set<String> _handledMobileCaptureRequestIds = <String>{};
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
    _previewStreamController.addListener(_handlePreviewStreamChanged);
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
    _hudMessageTimer?.cancel();
    _baseUrlController.removeListener(_scheduleDraftPersist);
    _streamUrlController.removeListener(_scheduleDraftPersist);
    _previewStreamController.removeListener(_handlePreviewStreamChanged);
    _previewStreamController.dispose();
    _mobileTrackPoseDetector.close();
    _baseUrlController.dispose();
    _streamUrlController.dispose();
    _sessionCodeController.dispose();
    super.dispose();
  }

  Uint8List? get _latestPreviewFrameBytes =>
      _previewStreamController.latestFrameBytes;

  DateTime? get _latestPreviewFrameAt => _previewStreamController.latestFrameAt;

  String? get _previewStreamErrorMessage =>
      _previewStreamController.errorMessage;

  void _handlePreviewStreamChanged() {
    if (!mounted) {
      return;
    }
    setState(() {});
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
        _syncMessage = null;
        _hudMessageTimerKey = null;
      });
      _previewStreamController.clearError();
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

    final draft = await showTemplatePhotoDialog(
      context,
      title: '新增模板',
      enabledRecognitionModes: const <TemplateRecognitionMode>{
        TemplateRecognitionMode.local,
      },
    );
    if (!mounted || draft == null) {
      return;
    }

    setState(() {
      _isCreatingDemoTemplate = true;
      _errorMessage = null;
    });

    try {
      final templateData = await _buildLocalTemplateDataFromPhoto(
        name: draft.name,
        filePath: draft.filePath,
      );
      final uploadedFile = await widget.mobileApiService.uploadCaptureFile(
        accessToken: widget.accessToken,
        filePath: draft.filePath,
      );
      templateData['source_image_url'] = uploadedFile.fileUrl;
      templateData['image_path'] = uploadedFile.fileUrl;
      final template = await widget.mobileApiService.createTemplate(
        accessToken: widget.accessToken,
        name: draft.name,
        sourceImageUrl: uploadedFile.fileUrl,
        previewImageUrl: uploadedFile.fileUrl,
        templateData: templateData,
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
    if (template == null) {
      return;
    }
    await _deleteTemplate(template);
  }

  Future<bool> _deleteTemplate(TemplateSummary template) async {
    if (_isDeletingTemplate) {
      return false;
    }
    if (template.isRecommendedDefault) {
      setState(() {
        _syncMessage = '后台推荐模板不能在手机端删除，如需调整请到管理后台维护。';
      });
      return false;
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
      return false;
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
        return false;
      }

      final nextTemplates = _templates
          .where((item) => item.id != template.id)
          .toList(growable: false);
      setState(() {
        _templates = nextTemplates;
        _selectedTemplate = _resolveInitialTemplate(nextTemplates);
        _selectedDeviceTemplate = null;
        _syncMessage = '已删除模板：${template.name}';
      });
      return true;
    } on ApiException catch (error) {
      if (!mounted) {
        return false;
      }
      setState(() {
        _errorMessage = error.message;
      });
    } catch (_) {
      if (!mounted) {
        return false;
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
    return false;
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
      final detection = <String, bool>{};
      if (key == 'show_live_body_skeleton') {
        detection['enable_pose_landmarks'] = value;
      } else if (key == 'show_live_face_mesh') {
        detection['enable_face_landmarks'] = value;
      } else if (key == 'show_live_hands') {
        final gesture =
            _status?.gestureStatus ?? const DeviceGestureStatusSummary();
        detection['enable_hand_landmarks'] =
            value || gesture.captureEnabled || gesture.forceOkEnabled;
      }
      final status = await _deviceApiService.updateDeviceConfig(
        baseUrl: _baseUrlController.text,
        overlay: <String, bool>{key: value},
        detection: detection.isEmpty ? null : detection,
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
      final enablesGestureRecognition =
          value && (key == 'capture_enabled' || key == 'force_ok_enabled');
      final status = await _deviceApiService.updateDeviceConfig(
        baseUrl: _baseUrlController.text,
        gesture: <String, bool>{key: value},
        detection: enablesGestureRecognition
            ? const <String, bool>{'enable_hand_landmarks': true}
            : null,
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
      final detailedPrefs = await SharedPreferences.getInstance();
      final shouldAutoStartMobilePush =
          detailedPrefs.getBool(
            _detailedSettingKey('device.auto_start_mobile_push'),
          ) ??
          true;
      final deviceStartMode =
          detailedPrefs.getString(_detailedSettingKey('device.start_mode')) ??
          'MANUAL';
      if (shouldAutoStartMobilePush &&
          !_isMobilePushEnabled &&
          Platform.isAndroid) {
        setState(() {
          _markMobilePushStarting();
        });
        try {
          await _startConfiguredMobilePush();
        } finally {
          if (mounted) {
            setState(() {
              _markMobilePushStartFinished();
            });
          }
        }
      } else {
        final status = await _deviceApiService.openSession(
          baseUrl: _baseUrlController.text,
          sessionCode: _sessionCodeController.text.trim(),
          streamUrl: _streamUrlController.text.trim(),
          startMode: deviceStartMode,
        );
        setState(() {
          _status = status;
          _lastStatusUpdatedAt = DateTime.now();
        });
        _previewStreamController.clear();
        await _rememberCurrentConnection();
        await _refreshStatusSilently();
      }
      final gestureConfig = <String, bool>{};
      final overlayConfig = <String, bool>{};
      final detectionConfig = <String, bool>{};
      final detailedCaptureEnabled = detailedPrefs.getBool(
        _detailedSettingKey('gesture.capture_enabled'),
      );
      final detailedOkCaptureEnabled = detailedPrefs.getBool(
        _detailedSettingKey('gesture.ok_capture_enabled'),
      );
      final detailedAnalyzeAfterCapture = detailedPrefs.getBool(
        _detailedSettingKey('gesture.analyze_after_capture'),
      );
      if (detailedCaptureEnabled != null) {
        gestureConfig['capture_enabled'] = detailedCaptureEnabled;
      }
      if (detailedOkCaptureEnabled != null) {
        gestureConfig['force_ok_enabled'] = detailedOkCaptureEnabled;
      }
      if (detailedAnalyzeAfterCapture != null || _analyzeCaptureAfterShot) {
        gestureConfig['auto_analyze_enabled'] =
            detailedAnalyzeAfterCapture ?? _analyzeCaptureAfterShot;
      }
      if (gestureConfig['capture_enabled'] == true ||
          gestureConfig['force_ok_enabled'] == true) {
        detectionConfig['enable_hand_landmarks'] = true;
      }
      final overlayEnabled = detailedPrefs.getBool(
        _detailedSettingKey('device_overlay.enabled'),
      );
      bool overlayValue(String prefKey, {bool fallback = true}) {
        final configured = detailedPrefs.getBool(_detailedSettingKey(prefKey));
        final enabled = overlayEnabled ?? true;
        return enabled && (configured ?? fallback);
      }

      if (overlayEnabled != null ||
          detailedPrefs.getBool(
                _detailedSettingKey('device_overlay.live_person_box'),
              ) !=
              null) {
        overlayConfig['show_live_person_bbox'] = overlayValue(
          'device_overlay.live_person_box',
        );
      }
      if (overlayEnabled != null ||
          detailedPrefs.getBool(
                _detailedSettingKey('device_overlay.live_skeleton'),
              ) !=
              null) {
        final showSkeleton = overlayValue('device_overlay.live_skeleton');
        overlayConfig['show_live_body_skeleton'] = showSkeleton;
        detectionConfig['enable_pose_landmarks'] = showSkeleton;
      }
      if (overlayEnabled != null ||
          detailedPrefs.getBool(
                _detailedSettingKey('device_overlay.live_hands'),
              ) !=
              null) {
        final showHands = overlayValue('device_overlay.live_hands');
        overlayConfig['show_live_hands'] = showHands;
        detectionConfig['enable_hand_landmarks'] = showHands;
      }
      if (overlayEnabled != null ||
          detailedPrefs.getBool(
                _detailedSettingKey('device_overlay.template_box'),
              ) !=
              null) {
        overlayConfig['show_template_bbox'] = overlayValue(
          'device_overlay.template_box',
        );
      }
      if (overlayEnabled != null ||
          detailedPrefs.getBool(
                _detailedSettingKey('device_overlay.template_skeleton'),
              ) !=
              null) {
        overlayConfig['show_template_skeleton'] = overlayValue(
          'device_overlay.template_skeleton',
        );
      }
      if (overlayEnabled != null ||
          detailedPrefs.getBool(
                _detailedSettingKey('device_overlay.ai_lock_box'),
              ) !=
              null) {
        overlayConfig['show_ai_lock_box'] = overlayValue(
          'device_overlay.ai_lock_box',
        );
      }
      if (gestureConfig['capture_enabled'] == true ||
          gestureConfig['force_ok_enabled'] == true) {
        detectionConfig['enable_hand_landmarks'] = true;
      }
      if (gestureConfig.isNotEmpty ||
          overlayConfig.isNotEmpty ||
          detectionConfig.isNotEmpty) {
        final updatedStatus = await _deviceApiService.updateDeviceConfig(
          baseUrl: _baseUrlController.text,
          gesture: gestureConfig.isEmpty ? null : gestureConfig,
          overlay: overlayConfig.isEmpty ? null : overlayConfig,
          detection: detectionConfig.isEmpty ? null : detectionConfig,
        );
        setState(() {
          _status = updatedStatus;
          _lastStatusUpdatedAt = DateTime.now();
        });
      }
      final detailedFollowMode = detailedPrefs.getString(
        _detailedSettingKey('device.follow_target_mode'),
      );
      if (detailedFollowMode != null && detailedFollowMode.isNotEmpty) {
        final updatedStatus = await _deviceApiService.setFollowMode(
          baseUrl: _baseUrlController.text,
          followMode: detailedFollowMode,
        );
        setState(() {
          _status = updatedStatus;
          _lastStatusUpdatedAt = DateTime.now();
        });
      }
      await _refreshHealthSilently();
    }, successMessage: '设备会话已打开，手机画面已启动。');
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
        _lastCapturePath = null;
        _lastAiResultTitle = null;
        _lastAiResultBody = null;
        _preferredAiResultKind = null;
        _lastAiResultAt = null;
        _isHudAiResultExpanded = false;
        _isHudCapturesExpanded = false;
        _lastBackendAiTask = null;
        _lastStatusUpdatedAt = null;
        _sessionCodeController.text = _buildSessionCode();
      });
      _previewStreamController.clear();
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
      });
      _previewStreamController.clear();
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
        _markMobilePushStarting();
      });

      try {
        await _startConfiguredMobilePush();
      } catch (_) {
        await _stopMobilePush(silent: true);
        rethrow;
      } finally {
        if (mounted) {
          setState(() {
            _markMobilePushStartFinished();
          });
        }
      }
    });
  }

  Future<void> _startConfiguredMobilePush() async {
    final detailedPrefs = await SharedPreferences.getInstance();
    final transport =
        detailedPrefs.getString(_detailedSettingKey('push.transport')) ??
        'websocket';
    final preferWebRtc =
        detailedPrefs.getBool(_detailedSettingKey('push.prefer_webrtc')) ??
        false;
    final shouldTryWebRtc =
        transport == 'webrtc' || transport == 'auto' || preferWebRtc;
    if (shouldTryWebRtc) {
      try {
        await _startMobilePushWebRtc();
        return;
      } catch (_) {
        if (transport == 'webrtc') {
          rethrow;
        }
        await _stopMobilePush(silent: true);
      }
    }
    await _startLegacyMobilePush();
  }

  Future<void> _startMobilePushWebRtc() async {
    final camera = await _preferredMobilePushCamera();
    final detailedPrefs = await SharedPreferences.getInstance();
    final deviceStartMode =
        detailedPrefs.getString(_detailedSettingKey('device.start_mode')) ??
        'MANUAL';
    await _stopPreviewStream();
    _streamUrlController.text = _mobilePushStreamUrl;
    final status = await _deviceApiService.openSession(
      baseUrl: _baseUrlController.text,
      sessionCode: _sessionCodeController.text.trim(),
      streamUrl: _mobilePushStreamUrl,
      mirrorView: _MobilePushTools.requiresMirrorCorrection(
        camera.lensDirection,
      ),
      startMode: deviceStartMode,
    );
    final session = await _deviceWebRtcService.start(
      baseUrl: _baseUrlController.text,
      lensDirection: camera.lensDirection,
      onConnectionState: (RTCPeerConnectionState state) {
        _recordMobilePushDebug('WebRTC connection: $state');
        if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
            state ==
                RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
          _setMobilePushError('WebRTC 连接已断开，请检查设备运行时服务和局域网连接。');
        }
      },
      onDebug: _recordMobilePushDebug,
    );
    if (!mounted) {
      await session.dispose();
      return;
    }
    setState(() {
      _status = status;
      _lastStatusUpdatedAt = DateTime.now();
      _webRtcSession = session;
      _markMobilePushStarted(camera: camera, lastFrameAt: DateTime.now());
      _syncMessage = '手机画面 WebRTC 推流已启动。';
      _addActionRecord('system', '手机画面 WebRTC 推流已启动。');
    });
    _previewStreamController.clear(frameAt: DateTime.now());
    await _rememberCurrentConnection();
  }

  Future<void> _startLegacyMobilePush() async {
    if (!Platform.isAndroid) {
      throw const ApiException('手机 WebSocket fallback 目前仅支持 Android。');
    }
    final camera = await _preferredMobilePushCamera();
    final detailedPrefs = await SharedPreferences.getInstance();
    final deviceStartMode =
        detailedPrefs.getString(_detailedSettingKey('device.start_mode')) ??
        'MANUAL';
    final socketTimeout = Duration(
      milliseconds: math.max(
        1000,
        ((detailedPrefs.getDouble(
                      _detailedSettingKey('push.socket_timeout_seconds'),
                    ) ??
                    _mobilePushSocketTimeout.inSeconds) *
                1000)
            .round(),
      ),
    );
    _mobilePushCamera = camera;
    _mobilePushLensDirection = camera.lensDirection;
    _resetMobilePushFrameConfig();
    final controller = CameraController(
      camera,
      ResolutionPreset.medium,
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
      mirrorView: _MobilePushTools.requiresMirrorCorrection(
        camera.lensDirection,
      ),
      startMode: deviceStartMode,
    );
    setState(() {
      _status = status;
      _lastStatusUpdatedAt = DateTime.now();
      _markMobilePushStarted(camera: camera, lastFrameAt: null);
    });
    await _rememberCurrentConnection();
    try {
      await _mobilePushSocketSender.connect(
        uri: _buildDeviceWebSocketUri('/api/device/stream/mobile-ws'),
        timeout: socketTimeout,
        onError: _handleMobilePushSocketError,
        onClosed: _handleMobilePushSocketClosed,
      );
    } catch (_) {
      if (mounted) {
        setState(() {
          _useMobilePushHttpFallback = true;
          _syncMessage = 'WebSocket 推流不可用，已切换 JPEG 兼容推流。';
        });
      } else {
        _useMobilePushHttpFallback = true;
      }
    }
    await controller.startImageStream(_handleMobilePushFrame);
  }

  void _handleMobilePushSocketError() {
    if (_isMobilePushEnabled) {
      setState(() {
        _useMobilePushHttpFallback = true;
        _syncMessage = 'WebSocket 推流连接出错，已切换 JPEG 兼容推流。';
      });
    }
  }

  Future<Map<String, dynamic>> _buildLocalTemplateDataFromPhoto({
    required String name,
    required String filePath,
  }) async {
    final imageBytes = await File(filePath).readAsBytes();
    final image = img.decodeImage(imageBytes);
    if (image == null) {
      throw const ApiException('模板照片读取失败，请换一张图片再试。');
    }
    final poses = await _mobileTrackPoseDetector.processImage(
      InputImage.fromFilePath(filePath),
    );
    if (poses.isEmpty) {
      throw const ApiException('未检测到人体，请换一张人物更完整、更清晰的模板照片。');
    }

    final pose = poses.reduce((best, current) {
      return current.landmarks.length > best.landmarks.length ? current : best;
    });
    final imageSize = Size(image.width.toDouble(), image.height.toDouble());
    final points = _templatePointsFromPose(pose, imageSize);
    if (points.length < 6) {
      throw const ApiException('识别到的人体关键点太少，请选择无遮挡、身体更完整的照片。');
    }

    final bbox = _templateBboxFromPoints(points.values.toList(growable: false));
    final headBox = _templateHeadBoxFromPoints(points, fallbackBodyBox: bbox);
    final headAnchor = headBox == null
        ? null
        : NormalizedPoint(
            headBox.left + headBox.width * 0.5,
            headBox.top + headBox.height * 0.5,
          );
    final posePointsImage = <String, List<double>>{};
    final posePointsBbox = <String, List<double>>{};
    for (final entry in points.entries) {
      final key = entry.key.toString();
      final point = entry.value;
      posePointsImage[key] = <double>[point.x, point.y];
      posePointsBbox[key] = <double>[
        _safeNormalizeInBox(point.x, bbox.left, bbox.width),
        _safeNormalizeInBox(point.y, bbox.top, bbox.height),
      ];
    }

    return <String, dynamic>{
      'name': name,
      'image_path': filePath,
      'bbox_norm': <double>[bbox.left, bbox.top, bbox.width, bbox.height],
      if (headBox != null)
        'head_bbox_norm': <double>[
          headBox.left,
          headBox.top,
          headBox.width,
          headBox.height,
        ],
      if (headAnchor != null) 'head_anchor_norm_x': headAnchor.x,
      if (headAnchor != null) 'head_anchor_norm_y': headAnchor.y,
      'pose_points': posePointsBbox,
      'pose_points_image': posePointsImage,
      'pose_points_bbox': posePointsBbox,
      'created_by': 'mobile_local_pose',
    };
  }

  Map<int, NormalizedPoint> _templatePointsFromPose(Pose pose, Size imageSize) {
    final result = <int, NormalizedPoint>{};
    const mapping = <PoseLandmarkType, int>{
      PoseLandmarkType.nose: 0,
      PoseLandmarkType.leftEyeInner: 1,
      PoseLandmarkType.leftEye: 2,
      PoseLandmarkType.leftEyeOuter: 3,
      PoseLandmarkType.rightEyeInner: 4,
      PoseLandmarkType.rightEye: 5,
      PoseLandmarkType.rightEyeOuter: 6,
      PoseLandmarkType.leftEar: 7,
      PoseLandmarkType.rightEar: 8,
      PoseLandmarkType.leftMouth: 9,
      PoseLandmarkType.rightMouth: 10,
      PoseLandmarkType.leftShoulder: 11,
      PoseLandmarkType.rightShoulder: 12,
      PoseLandmarkType.leftElbow: 13,
      PoseLandmarkType.rightElbow: 14,
      PoseLandmarkType.leftWrist: 15,
      PoseLandmarkType.rightWrist: 16,
      PoseLandmarkType.leftPinky: 17,
      PoseLandmarkType.rightPinky: 18,
      PoseLandmarkType.leftIndex: 19,
      PoseLandmarkType.rightIndex: 20,
      PoseLandmarkType.leftThumb: 21,
      PoseLandmarkType.rightThumb: 22,
      PoseLandmarkType.leftHip: 23,
      PoseLandmarkType.rightHip: 24,
      PoseLandmarkType.leftKnee: 25,
      PoseLandmarkType.rightKnee: 26,
      PoseLandmarkType.leftAnkle: 27,
      PoseLandmarkType.rightAnkle: 28,
      PoseLandmarkType.leftHeel: 29,
      PoseLandmarkType.rightHeel: 30,
      PoseLandmarkType.leftFootIndex: 31,
      PoseLandmarkType.rightFootIndex: 32,
    };

    for (final entry in mapping.entries) {
      final landmark = pose.landmarks[entry.key];
      if (landmark == null || landmark.likelihood < 0.15) {
        continue;
      }
      result[entry.value] = NormalizedPoint(
        _clampUnit(landmark.x / imageSize.width),
        _clampUnit(landmark.y / imageSize.height),
      );
    }
    return result;
  }

  NormalizedRect _templateBboxFromPoints(List<NormalizedPoint> points) {
    var minX = 1.0;
    var minY = 1.0;
    var maxX = 0.0;
    var maxY = 0.0;
    for (final point in points) {
      minX = math.min(minX, point.x);
      minY = math.min(minY, point.y);
      maxX = math.max(maxX, point.x);
      maxY = math.max(maxY, point.y);
    }
    final width = math.max(0.12, maxX - minX);
    final height = math.max(0.20, maxY - minY);
    final padX = math.min(0.08, width * 0.16);
    final padY = math.min(0.10, height * 0.18);
    return NormalizedRect(
      left: _clampUnit(minX - padX),
      top: _clampUnit(minY - padY),
      width: _clampDimension(maxX - minX + padX * 2, minX - padX),
      height: _clampDimension(maxY - minY + padY * 2, minY - padY),
    );
  }

  NormalizedRect? _templateHeadBoxFromPoints(
    Map<int, NormalizedPoint> points, {
    required NormalizedRect fallbackBodyBox,
  }) {
    final facePoints = <NormalizedPoint>[
      for (final index in <int>[0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10])
        if (points[index] != null) points[index]!,
    ];
    if (facePoints.isNotEmpty) {
      return _templateHeadBoxFromFacePoints(facePoints);
    }

    final leftShoulder = points[11];
    final rightShoulder = points[12];
    if (leftShoulder != null && rightShoulder != null) {
      final shoulderCenter = NormalizedPoint(
        (leftShoulder.x + rightShoulder.x) * 0.5,
        (leftShoulder.y + rightShoulder.y) * 0.5,
      );
      final shoulderWidth = (rightShoulder.x - leftShoulder.x).abs();
      final width = _clampRange(shoulderWidth * 0.62, 0.10, 0.24);
      final height = _clampRange(width * 1.12, 0.11, 0.26);
      return _rectAroundPoint(
        NormalizedPoint(shoulderCenter.x, shoulderCenter.y - height * 0.82),
        width,
        height,
      );
    }

    return NormalizedRect(
      left: fallbackBodyBox.left + fallbackBodyBox.width * 0.22,
      top: _clampUnit(fallbackBodyBox.top - fallbackBodyBox.height * 0.04),
      width: fallbackBodyBox.width * 0.56,
      height: fallbackBodyBox.height * 0.25,
    );
  }

  NormalizedRect _templateHeadBoxFromFacePoints(List<NormalizedPoint> points) {
    var minX = 1.0;
    var minY = 1.0;
    var maxX = 0.0;
    var maxY = 0.0;
    for (final point in points) {
      minX = math.min(minX, point.x);
      minY = math.min(minY, point.y);
      maxX = math.max(maxX, point.x);
      maxY = math.max(maxY, point.y);
    }
    final width = _clampRange(maxX - minX, 0.10, 0.28);
    final height = _clampRange(maxY - minY, 0.10, 0.30);
    final center = NormalizedPoint((minX + maxX) * 0.5, (minY + maxY) * 0.5);
    return _rectAroundPoint(center, width * 1.55, height * 1.85);
  }

  NormalizedRect _rectAroundPoint(
    NormalizedPoint center,
    double width,
    double height,
  ) {
    final left = _clampUnit(center.x - width * 0.5);
    final top = _clampUnit(center.y - height * 0.5);
    return NormalizedRect(
      left: left,
      top: top,
      width: _clampDimension(width, left),
      height: _clampDimension(height, top),
    );
  }

  double _safeNormalizeInBox(double value, double origin, double size) {
    if (size.abs() < 1e-6) {
      return 0.5;
    }
    return _clampUnit((value - origin) / size);
  }

  double _clampDimension(double value, double origin) {
    return value.clamp(0.01, math.max(0.01, 1.0 - _clampUnit(origin)));
  }

  double _clampRange(double value, double min, double max) {
    return value.clamp(min, max);
  }

  void _handleMobilePushSocketClosed() {
    if (_isMobilePushEnabled && !_useMobilePushHttpFallback) {
      setState(() {
        _useMobilePushHttpFallback = true;
        _syncMessage = 'WebSocket 推流已关闭，已切换 JPEG 兼容推流。';
      });
    }
  }

  Future<void> _switchMobilePushCamera() async {
    if (_isStartingMobilePush || _isHandlingMobilePushOrientationChange) {
      return;
    }
    if (_isDeviceLinkRecordingVideo || _isFinalizingDeviceLinkVideo) {
      setState(() {
        _syncMessage = '录像中不能切换摄像头，请先停止录像。';
      });
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
          _markMobilePushStarting();
        });
        try {
          await _stopMobilePush(silent: true);
          await _startMobilePushWebRtc();
        } finally {
          if (mounted) {
            setState(() {
              _markMobilePushStartFinished();
            });
          }
        }
      });
      return;
    }

    await _runAction(() async {
      setState(() {
        _markMobilePushStarting();
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

        _mobilePushLensDirection = selectedCamera.lensDirection;
        await _stopMobilePush(silent: true);
        await _startLegacyMobilePush();
      } catch (_) {
        if (_isMobilePushEnabled && _mobilePushCameraController == null) {
          await _stopMobilePush(silent: true);
        }
        rethrow;
      } finally {
        _markMobilePushFrameSendFinished();
        if (mounted) {
          setState(() {
            _markMobilePushStartFinished();
          });
        }
      }
    }, successMessage: '手机画面推送已启动。');
  }

  Future<void> _stopMobilePush({bool silent = false}) async {
    final activeController = _mobilePushCameraController;
    if (activeController?.value.isRecordingVideo == true) {
      await _stopDeviceLinkVideoRecording(resumeStream: false, silent: true);
    }

    _resetMobilePushTransportState();

    await _stopWebRtcSession();

    await _mobilePushSocketSender.close();

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
      _resetMobilePushFrameConfig();
      return;
    }

    _beginMobilePushOrientationChange();
    if (mounted) {
      setState(() {
        _syncMessage = '屏幕方向变化，正在重新校正手机推流画面。';
      });
      _previewStreamController.clear(clearError: false);
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
      _resetMobilePushFrameConfig();
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
      _finishMobilePushOrientationChange();
    }
  }

  void _handleMobilePushFrame(CameraImage image) {
    unawaited(_handleMobilePushFrameAsync(image));
  }

  Future<void> _handleMobilePushFrameAsync(CameraImage image) async {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final rotationDegrees = _mobilePushRotationForCurrentFrame();
    _updateLatestMobileAiFrame(
      image: image,
      rotationDegrees: rotationDegrees,
      capturedAtMs: nowMs,
    );

    if (!_shouldSendMobilePushFrame(
      sender: _mobilePushSocketSender,
      image: image,
    )) {
      return;
    }

    if (_isMobilePushFrameThrottled(nowMs)) {
      return;
    }

    try {
      _markMobilePushFrameSending();
      _updateDeviceLinkRecordingPreviewFrame(
        image: image,
        rotationDegrees: rotationDegrees,
        sentAtMs: nowMs,
      );
      _scheduleMobileTrackTargetFromImage(
        image: image,
        rotationDegrees: rotationDegrees,
        sentAtMs: nowMs,
      );
      final frameBytes = _MobilePushTools.encodeCameraImageAsNv21(image);
      if (_useMobilePushHttpFallback || !_mobilePushSocketSender.isOpen) {
        await _pushMobileFrameAsJpeg(
          image: image,
          rotationDegrees: rotationDegrees,
          sentAtMs: nowMs,
        );
        return;
      }
      if (!_mobilePushConfigSent ||
          rotationDegrees != _mobilePushRotationDegrees) {
        _mobilePushSocketSender.sendConfig(
          image: image,
          rotationDegrees: rotationDegrees,
        );
        _mobilePushRotationDegrees = rotationDegrees;
        _mobilePushConfigSent = true;
      }
      if (frameBytes == null) {
        await _pushMobileFrameAsJpeg(
          image: image,
          rotationDegrees: rotationDegrees,
          sentAtMs: nowMs,
        );
        return;
      }
      _mobilePushSocketSender.sendFrame(frameBytes);
      _markMobilePushFrameSent(nowMs);

      if (mounted && _shouldRefreshMobilePushFrameUi(nowMs)) {
        setState(() {
          _markMobilePushFrameUiUpdated(nowMs);
        });
      }
    } on ApiException catch (error) {
      _setMobilePushError(error.message);
    } catch (_) {
      _setMobilePushError('手机画面推送失败，请检查设备运行时地址和网络连接。');
    } finally {
      _markMobilePushFrameSendFinished();
    }
  }

  void _updateDeviceLinkRecordingPreviewFrame({
    required CameraImage image,
    required int rotationDegrees,
    required int sentAtMs,
  }) {
    if (!_isDeviceLinkRecordingPreviewPaused ||
        !_isDeviceLinkRecordingVideo ||
        !mounted) {
      return;
    }
    if (sentAtMs - _lastRecordingPreviewFrameAtMs <
        _recordingPreviewFrameThrottle.inMilliseconds) {
      return;
    }

    final jpegBytes = _MobilePushTools.encodeCameraImageAsPreviewJpeg(
      image,
      rotationDegrees: rotationDegrees,
      maxSide: 420,
      quality: 48,
    );
    if (jpegBytes == null) {
      return;
    }

    _lastRecordingPreviewFrameAtMs = sentAtMs;
    setState(() {
      _deviceLinkRecordingPreviewBytes = jpegBytes;
    });
  }

  void _updateLatestMobileAiFrame({
    required CameraImage image,
    required int rotationDegrees,
    required int capturedAtMs,
  }) {
    if (capturedAtMs - _lastMobileAiFrameCachedAtMs <
        _mobileAiFrameCacheThrottle.inMilliseconds) {
      return;
    }
    final jpegBytes = _MobilePushTools.encodeCameraImageAsJpeg(
      image,
      rotationDegrees: rotationDegrees,
      maxSide: 960,
      quality: 72,
    );
    if (jpegBytes == null) {
      return;
    }
    _lastMobileAiFrameCachedAtMs = capturedAtMs;
    _latestMobileAiFrameAtMs = capturedAtMs;
    _latestMobileAiFrameBytes = jpegBytes;
  }

  Future<void> _pushMobileFrameAsJpeg({
    required CameraImage image,
    required int rotationDegrees,
    required int sentAtMs,
  }) async {
    final jpegBytes = _MobilePushTools.encodeCameraImageAsJpeg(
      image,
      rotationDegrees: rotationDegrees,
    );
    if (jpegBytes == null) {
      _setMobilePushError(
        '手机画面推送失败：${_MobilePushTools.describeCameraImage(image)}',
      );
      return;
    }

    if (!_useMobilePushHttpFallback) {
      if (mounted) {
        setState(() {
          _useMobilePushHttpFallback = true;
          _syncMessage = '已切换 JPEG 兼容推流。';
        });
      } else {
        _useMobilePushHttpFallback = true;
      }
    }

    await _deviceApiService.pushMobileFrameBytes(
      baseUrl: _baseUrlController.text,
      bytes: jpegBytes,
    );
    _markMobilePushFrameSent(sentAtMs);
    if (mounted && _shouldRefreshMobilePushFrameUi(sentAtMs)) {
      setState(() {
        _markMobilePushFrameUiUpdated(sentAtMs);
      });
    }
  }

  void _scheduleMobileTrackTargetFromImage({
    required CameraImage image,
    required int rotationDegrees,
    required int sentAtMs,
  }) {
    if (!_shouldSendMobileTrackTarget(sentAtMs)) {
      return;
    }
    _isProcessingMobileTrackTarget = true;
    _lastMobileTrackTargetSentAtMs = sentAtMs;
    unawaited(
      _processMobileTrackTargetFrame(
        image: image,
        rotationDegrees: rotationDegrees,
        sentAtMs: sentAtMs,
      ).whenComplete(() {
        _isProcessingMobileTrackTarget = false;
      }),
    );
  }

  bool _shouldSendMobileTrackTarget(int nowMs) {
    if (!_isMobilePushEnabled ||
        _status?.sessionOpened != true ||
        _isMobileAiScanning ||
        _isProcessingMobileTrackTarget) {
      return false;
    }
    final overlay =
        _status?.overlayStatus ?? const DeviceOverlayStatusSummary();
    final needsLiveOverlay =
        overlay.enabled &&
        (overlay.showLivePersonBbox ||
            overlay.showLiveBodySkeleton ||
            overlay.showAiLockBox);
    if (!_shouldDriveMobileTrackTarget && !needsLiveOverlay) {
      return false;
    }
    return nowMs - _lastMobileTrackTargetSentAtMs >=
        _mobileTrackTargetThrottle.inMilliseconds;
  }

  bool get _isAutoTrackMode {
    final mode = _status?.mode;
    return mode == 'AUTO_TRACK' || mode == 'gimbal_follow';
  }

  bool get _isTemplateGuideMode {
    final mode = _status?.mode;
    return mode == 'SMART_COMPOSE' || mode == 'gimbal_template';
  }

  bool get _shouldDriveMobileTrackTarget {
    return _isAutoTrackMode || _isTemplateGuideMode;
  }

  Future<void> _processMobileTrackTargetFrame({
    required CameraImage image,
    required int rotationDegrees,
    required int sentAtMs,
  }) async {
    final inputImage = _mobileInputImageFromCameraImage(
      image,
      rotationDegrees: rotationDegrees,
    );
    final metadata = inputImage?.metadata;
    if (inputImage == null || metadata == null) {
      _handleMobilePoseMiss();
      return;
    }

    try {
      final poses = await _mobileTrackPoseDetector.processImage(inputImage);
      final frameSize = _mobileTrackFrameSize(metadata);
      final overlay = _mobileVisionOverlayFromPoses(poses, frameSize);
      if (overlay == null) {
        _handleMobilePoseMiss();
      } else if (mounted) {
        _consecutiveMobilePoseMisses = 0;
        setState(() {
          _latestMobileVisionOverlay = overlay;
        });
      }
      if (!_sendPhoneTrackTargetCommands) {
        return;
      }
      final target = _bestMobileTrackTarget(poses, frameSize);
      if (target == null) {
        return;
      }
      if (!_isMobilePushEnabled ||
          _status?.sessionOpened != true ||
          !_shouldDriveMobileTrackTarget) {
        return;
      }
      await _deviceApiService.sendTrackTargetCommand(
        baseUrl: _baseUrlController.text,
        targetType: target.targetType,
        targetX: target.point.x,
        targetY: target.point.y,
        desiredX: target.desiredPoint.x,
        desiredY: target.desiredPoint.y,
        confidence: target.confidence,
        source: 'main_phone',
        frame: <String, dynamic>{
          'width': target.frameSize.width.round(),
          'height': target.frameSize.height.round(),
          'raw_width': image.width,
          'raw_height': image.height,
          'rotation_degrees': rotationDegrees,
          'lens': _mobilePushLensDirection.name,
          'mirror': _shouldMirrorMobileLiveOverlay,
        },
        timestampMs: sentAtMs,
      );
      return;
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _mobilePushErrorMessage = 'track-target failed: ${error.message}';
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _mobilePushErrorMessage = 'track-target failed';
      });
    }
  }

  InputImage? _mobileInputImageFromCameraImage(
    CameraImage image, {
    required int rotationDegrees,
  }) {
    final rotation = InputImageRotationValue.fromRawValue(rotationDegrees);
    if (rotation == null) {
      return null;
    }

    final format = InputImageFormatValue.fromRawValue(image.format.raw);
    if (image.planes.length == 1 &&
        format != null &&
        ((Platform.isAndroid && format == InputImageFormat.nv21) ||
            (Platform.isIOS && format == InputImageFormat.bgra8888))) {
      final plane = image.planes.first;
      return InputImage.fromBytes(
        bytes: plane.bytes,
        metadata: InputImageMetadata(
          size: Size(image.width.toDouble(), image.height.toDouble()),
          rotation: rotation,
          format: format,
          bytesPerRow: plane.bytesPerRow,
        ),
      );
    }

    if (!Platform.isAndroid) {
      return null;
    }
    final frameBytes = _MobilePushTools.encodeCameraImageAsNv21(image);
    if (frameBytes == null) {
      return null;
    }
    return InputImage.fromBytes(
      bytes: frameBytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: InputImageFormat.nv21,
        bytesPerRow: image.width,
      ),
    );
  }

  void _handleMobilePoseMiss() {
    if (!mounted) {
      return;
    }
    _consecutiveMobilePoseMisses += 1;
    if (_consecutiveMobilePoseMisses < _maxMobilePoseMissesBeforeClear) {
      return;
    }
    if (_latestMobileVisionOverlay == null) {
      return;
    }
    setState(() {
      _latestMobileVisionOverlay = null;
    });
  }

  _MobileVisionOverlay? _mobileVisionOverlayFromPoses(
    List<Pose> poses,
    Size frameSize,
  ) {
    _MobileVisionOverlay? best;
    double bestArea = -1;
    for (final pose in poses) {
      final overlay = _mobileVisionOverlayFromPose(pose, frameSize);
      if (overlay == null || overlay.bodyBox == null) {
        continue;
      }
      final area = overlay.bodyBox!.width * overlay.bodyBox!.height;
      if (area > bestArea) {
        best = overlay;
        bestArea = area;
      }
    }
    return best;
  }

  _MobileVisionOverlay? _mobileVisionOverlayFromPose(
    Pose pose,
    Size frameSize,
  ) {
    final points = <PoseLandmarkType, NormalizedPoint>{};
    for (final entry in pose.landmarks.entries) {
      final point = _mobilePosePoint(entry.value, frameSize);
      if (point == null || point.confidence < 0.2) {
        continue;
      }
      points[entry.key] = point.point;
    }
    if (points.isEmpty) {
      return null;
    }

    double left = 1;
    double top = 1;
    double right = 0;
    double bottom = 0;
    for (final point in points.values) {
      left = math.min(left, point.x);
      top = math.min(top, point.y);
      right = math.max(right, point.x);
      bottom = math.max(bottom, point.y);
    }
    if (right <= left || bottom <= top) {
      return null;
    }

    final skeleton = <_MobileVisionSegment>[];
    for (final pair in _mobilePoseSkeletonPairs) {
      final start = points[pair.start];
      final end = points[pair.end];
      if (start == null || end == null) {
        continue;
      }
      skeleton.add(_MobileVisionSegment(start: start, end: end));
    }

    final shoulderCenter = _shoulderCenterFromPose(pose, frameSize);
    final faceCenter = _faceCenterFromPose(pose, frameSize);
    final target = _mobileTrackTargetFromPose(pose, frameSize);
    return _MobileVisionOverlay(
      bodyBox: NormalizedRect(
        left: _clampUnit(left),
        top: _clampUnit(top),
        width: _clampUnit(right - left),
        height: _clampUnit(bottom - top),
      ),
      skeleton: skeleton,
      anchor: target?.point,
      targetType: target?.targetType ?? _mobileTrackTargetType(),
      shoulderCenter: shoulderCenter?.point,
      faceCenter: faceCenter?.point,
    );
  }

  Size _mobileTrackFrameSize(InputImageMetadata metadata) {
    switch (metadata.rotation) {
      case InputImageRotation.rotation90deg:
      case InputImageRotation.rotation270deg:
        return Size(metadata.size.height, metadata.size.width);
      case InputImageRotation.rotation0deg:
      case InputImageRotation.rotation180deg:
        return metadata.size;
    }
  }

  _MobileTrackTarget? _bestMobileTrackTarget(List<Pose> poses, Size frameSize) {
    _MobileTrackTarget? best;
    for (final pose in poses) {
      final target = _mobileTrackTargetFromPose(pose, frameSize);
      if (target == null) {
        continue;
      }
      if (best == null || target.confidence > best.confidence) {
        best = target;
      }
    }
    return best;
  }

  _MobileTrackTarget? _mobileTrackTargetFromPose(Pose pose, Size frameSize) {
    final targetType = _mobileTrackTargetType();
    final point = targetType == 'face_center'
        ? _faceCenterFromPose(pose, frameSize)
        : _shoulderCenterFromPose(pose, frameSize);
    if (point == null) {
      return null;
    }
    return _MobileTrackTarget(
      targetType: targetType,
      point: point.point,
      desiredPoint: _mobileTrackDesiredPoint(),
      confidence: point.confidence,
      frameSize: frameSize,
    );
  }

  NormalizedPoint _mobileTrackDesiredPoint() {
    final templatePoint = _isTemplateGuideMode
        ? _selectedTemplateFollowTargetPoint()
        : null;
    if (templatePoint == null) {
      return const NormalizedPoint(0.5, 0.5);
    }
    if (_shouldMirrorMobileLiveOverlay) {
      return NormalizedPoint(1 - templatePoint.x, templatePoint.y);
    }
    return templatePoint;
  }

  NormalizedPoint? _selectedTemplateFollowTargetPoint() {
    final scene = _selectedTemplateOverlayScene();
    if (scene == null) {
      return null;
    }
    final followMode = (_status?.followMode ?? 'shoulders').toLowerCase();
    if (followMode == 'face' || followMode == 'face_center') {
      return scene.templateFaceCenter ??
          scene.templateShoulderCenter ??
          _templateBoxCenterPoint(scene);
    }
    return scene.templateShoulderCenter ??
        scene.templateFaceCenter ??
        _templateBoxCenterPoint(scene);
  }

  NormalizedPoint? _templateBoxCenterPoint(OverlayScene scene) {
    if (!scene.hasTemplateBox) {
      return null;
    }
    final box = scene.templateBox;
    return NormalizedPoint(
      _clampUnit(box.left + box.width * 0.5),
      _clampUnit(box.top + box.height * 0.5),
    );
  }

  String _mobileTrackTargetType() {
    final followMode = (_status?.followMode ?? '').toLowerCase();
    if (followMode == 'face' || followMode == 'face_center') {
      return 'face_center';
    }
    return 'shoulder_center';
  }

  _MobilePosePoint? _faceCenterFromPose(Pose pose, Size frameSize) {
    return _averageMobilePosePoints(<_MobilePosePoint?>[
      _mobilePosePoint(pose.landmarks[PoseLandmarkType.nose], frameSize),
      _mobilePosePoint(pose.landmarks[PoseLandmarkType.leftEye], frameSize),
      _mobilePosePoint(pose.landmarks[PoseLandmarkType.rightEye], frameSize),
      _mobilePosePoint(pose.landmarks[PoseLandmarkType.leftEar], frameSize),
      _mobilePosePoint(pose.landmarks[PoseLandmarkType.rightEar], frameSize),
    ]);
  }

  _MobilePosePoint? _shoulderCenterFromPose(Pose pose, Size frameSize) {
    return _averageMobilePosePoints(<_MobilePosePoint?>[
      _mobilePosePoint(
        pose.landmarks[PoseLandmarkType.leftShoulder],
        frameSize,
      ),
      _mobilePosePoint(
        pose.landmarks[PoseLandmarkType.rightShoulder],
        frameSize,
      ),
    ]);
  }

  _MobilePosePoint? _mobilePosePoint(PoseLandmark? landmark, Size frameSize) {
    if (landmark == null) {
      return null;
    }
    return _MobilePosePoint(
      point: NormalizedPoint(
        _clampUnit(landmark.x / frameSize.width),
        _clampUnit(landmark.y / frameSize.height),
      ),
      confidence: _clampUnit(landmark.likelihood),
    );
  }

  _MobilePosePoint? _averageMobilePosePoints(List<_MobilePosePoint?> points) {
    final validPoints = points.whereType<_MobilePosePoint>().toList();
    if (validPoints.isEmpty) {
      return null;
    }
    final x =
        validPoints.fold<double>(0, (sum, item) => sum + item.point.x) /
        validPoints.length;
    final y =
        validPoints.fold<double>(0, (sum, item) => sum + item.point.y) /
        validPoints.length;
    final confidence =
        validPoints.fold<double>(0, (sum, item) => sum + item.confidence) /
        validPoints.length;
    return _MobilePosePoint(
      point: NormalizedPoint(_clampUnit(x), _clampUnit(y)),
      confidence: _clampUnit(confidence),
    );
  }

  double _clampUnit(double value) {
    if (!value.isFinite) {
      return 0;
    }
    return value.clamp(0.0, 1.0);
  }

  int _mobilePushRotationForCurrentFrame() {
    final controller = _mobilePushCameraController;
    final camera = _mobilePushCamera;
    return _MobilePushTools.resolveRotationDegrees(
      deviceOrientation: controller?.value.deviceOrientation,
      lensDirection: camera?.lensDirection,
      sensorOrientation: camera?.sensorOrientation,
      fallbackRotationDegrees: _mobilePushRotationDegrees,
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

  void _recordMobilePushDebug(String message) {
    if (!mounted) {
      return;
    }
    setState(() {
      _syncMessage = message;
      _addActionRecord('system', message);
    });
  }

  Future<void> _startPreviewStream() async {
    await _previewStreamController.start(
      uri: _buildDeviceWebSocketUri('/api/device/preview-ws'),
      hasSession: _status?.sessionOpened == true,
      timeout: _mobilePushSocketTimeout,
    );
  }

  Future<void> _stopPreviewStream() async {
    await _previewStreamController.stop();
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
    _manualMoveQueued = false;
    unawaited(_sendManualMoveStop());
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

  Future<void> _openDetailedSettingsFromDeviceLink() async {
    final builder = widget.detailedSettingsBuilder;
    if (builder == null) {
      setState(() {
        _syncMessage = '请从首页进入“详细设置”调整高级参数。';
      });
      return;
    }
    await Navigator.of(
      context,
    ).push<void>(MaterialPageRoute<void>(builder: builder));
  }

  void _setLandscapeControlsSide(bool left) {
    setState(() {
      _landscapeControlsOnLeft = left;
      _hasCustomJoystickAnchor = false;
    });
    _scheduleDraftPersist();
  }

  void _setSensitivity(double value) {
    setState(() {
      _sensitivity = value;
    });
    _scheduleDraftPersist();
    _syncSensitivityToDevice();
  }

  Future<void> _syncSensitivityToDevice() async {
    if (_status?.sessionOpened != true) {
      return;
    }
    try {
      await _deviceApiService.setSensitivity(
        baseUrl: _baseUrlController.text,
        sensitivity: _sensitivity,
      );
    } on ApiException {
      // device may not support sensitivity endpoint yet — ignore
    } catch (_) {}
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
    if (_status?.sessionOpened != true) {
      return;
    }
    if (_isManualMoveSending) {
      if (_activeManualMoveAction == action) {
        _manualMoveQueued = true;
      }
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
      _flushQueuedManualMove();
    }
  }

  Future<void> _sendManualMoveDelta(Offset vector) async {
    if (_status?.sessionOpened != true) {
      return;
    }
    if (_isManualMoveSending) {
      _manualMoveQueued = true;
      _activeManualMoveVector = vector;
      return;
    }
    _isManualMoveSending = true;
    final step = 4.5;
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
      _flushQueuedManualMove();
    }
  }

  Future<void> _sendManualMoveStop() async {
    if (_status?.sessionOpened != true) {
      return;
    }
    if (_isManualMoveSending) {
      _manualStopQueued = true;
      return;
    }
    _manualStopQueued = false;
    _isManualMoveSending = true;
    try {
      await _deviceApiService.sendManualMoveCommand(
        baseUrl: _baseUrlController.text,
        panDelta: 0,
        tiltDelta: 0,
      );
    } catch (_) {
      // Stop is best-effort; the device-side live hold will expire shortly.
    } finally {
      _isManualMoveSending = false;
      _flushQueuedManualMove();
    }
  }

  void _flushQueuedManualMove() {
    if (_isManualMoveSending || _status?.sessionOpened != true) {
      return;
    }
    if (_manualStopQueued) {
      _manualStopQueued = false;
      unawaited(_sendManualMoveStop());
      return;
    }
    if (!_manualMoveQueued) {
      return;
    }
    _manualMoveQueued = false;
    final action = _activeManualMoveAction;
    if (action != null) {
      unawaited(_sendManualMovePulse(action));
      return;
    }
    final vector = _activeManualMoveVector;
    if (vector != null && vector.distance >= 0.08) {
      unawaited(_sendManualMoveDelta(vector));
    }
  }

  Future<void> _setMode(String mode) async {
    if (mode == 'SMART_COMPOSE') {
      final templateReady = await _prepareSmartComposeTemplate();
      if (!templateReady || !mounted) {
        return;
      }
    }

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

  Future<bool> _prepareSmartComposeTemplate() async {
    while (mounted) {
      if (_templates.isEmpty && !_isLoadingTemplates) {
        await _loadTemplates();
      }
      if (!mounted) {
        return false;
      }

      final choice = await _showSmartComposeTemplatePicker();
      if (choice == null || !mounted) {
        return false;
      }
      switch (choice.action) {
        case _SmartComposeTemplateAction.create:
          await _createTemplate();
          break;
        case _SmartComposeTemplateAction.delete:
          final template = choice.mobileTemplate;
          if (template != null) {
            await _deleteTemplate(template);
          }
          break;
        case _SmartComposeTemplateAction.select:
          return _applySmartComposeTemplateChoice(choice);
      }
    }
    return false;
  }

  Future<_SmartComposeTemplateChoice?> _showSmartComposeTemplatePicker() {
    return showDialog<_SmartComposeTemplateChoice>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('选择模板引导模板'),
          contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520, maxHeight: 520),
            child: _templates.isEmpty
                ? const Center(child: Text('还没有可用模板，可以先新增一个模板。'))
                : SingleChildScrollView(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final columnCount = constraints.maxWidth >= 360 ? 3 : 2;
                        final cardWidth = math.max(
                          118.0,
                          (constraints.maxWidth - (columnCount - 1) * 10) /
                              columnCount,
                        );
                        return Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: _templates
                              .map((template) {
                                final meta = template.templateType.trim();
                                return SizedBox(
                                  width: cardWidth,
                                  child: _TemplatePreviewCard(
                                    name: template.name,
                                    imageUrl: _templatePreviewImageUrl(
                                      template,
                                    ),
                                    meta: meta.isEmpty ? null : meta,
                                    selected:
                                        _selectedTemplate?.id == template.id,
                                    onTap: () => Navigator.of(context).pop(
                                      _SmartComposeTemplateChoice.select(
                                        template,
                                      ),
                                    ),
                                    onDelete: template.isRecommendedDefault
                                        ? null
                                        : () => Navigator.of(context).pop(
                                            _SmartComposeTemplateChoice.delete(
                                              template,
                                            ),
                                          ),
                                  ),
                                );
                              })
                              .toList(growable: false),
                        );
                      },
                    ),
                  ),
          ),
          actions: <Widget>[
            TextButton.icon(
              onPressed: () => Navigator.of(
                context,
              ).pop(const _SmartComposeTemplateChoice.create()),
              icon: const Icon(Icons.add_photo_alternate_outlined),
              label: const Text('新增模板'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
          ],
        );
      },
    );
  }

  Future<bool> _applySmartComposeTemplateChoice(
    _SmartComposeTemplateChoice choice,
  ) async {
    final template = choice.mobileTemplate;
    if (template == null) {
      return false;
    }
    var ok = false;
    await _runAction(() async {
      final status = await _deviceApiService.selectTemplate(
        baseUrl: _baseUrlController.text,
        templateId: template.id,
        templateData: template.templateData,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _selectedTemplate = template;
        _selectedDeviceTemplate = null;
        _status = status;
        _lastStatusUpdatedAt = DateTime.now();
      });
      ok = true;
    }, successMessage: '模板已选择，准备进入模板构图。');
    return ok;
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
        _selectedDeviceTemplate = null;
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

  bool _guardRunningAiTask() {
    if (_status?.aiStatus.hasRunningTask == true) {
      setState(() {
        _syncMessage = _errorMessage = 'AI 任务正在运行，请等待当前任务完成。';
      });
      return true;
    }

    return false;
  }

  Future<void> _startAngleSearch() async {
    await _startAngleSearchWithConfig(_defaultAiScanConfig());
  }

  Future<void> _startAngleSearchAdvanced() async {
    if (_guardRunningAiTask()) {
      return;
    }
    final config = await _showAiScanConfigDialog(
      title: '自动找角度高级参数',
      includeDelay: true,
    );
    if (!mounted || config == null) {
      return;
    }
    await _startAngleSearchWithConfig(config);
  }

  Future<void> _startAngleSearchWithConfig(_AiScanConfig config) async {
    if (_guardRunningAiTask()) {
      return;
    }
    await _runAction(() async {
      setState(() {
        _setLastAiResult(
          title: 'AI 对话框',
          body: 'AI 正在扫描不同角度，完成后会在这里显示最佳照片和原因。',
          kind: 'angle',
        );
      });
      await _runBackendAngleSearchFromCurrentFrame(config);
    }, successMessage: '服务器 AI 自动找角度结果已下发到设备。');
  }

  Future<void> _startBackgroundLock() async {
    await _startBackgroundLockWithConfig(_defaultAiScanConfig());
  }

  Future<void> _startBackgroundLockAdvanced() async {
    if (_guardRunningAiTask()) {
      return;
    }
    final config = await _showAiScanConfigDialog(
      title: '背景锁定高级参数',
      includeDelay: true,
    );
    if (!mounted || config == null) {
      return;
    }
    await _startBackgroundLockWithConfig(config);
  }

  Future<void> _startBackgroundLockWithConfig(_AiScanConfig config) async {
    if (_guardRunningAiTask()) {
      return;
    }
    await _runAction(() async {
      setState(() {
        _setLastAiResult(
          title: 'AI 对话框',
          body: 'AI 正在扫描背景机位，完成后会在这里显示推荐原因和拍摄建议。',
          kind: 'background',
        );
      });
      await _runBackendBackgroundLockFromCurrentFrame(config);
    }, successMessage: '服务器 AI 背景锁定结果已下发到设备。');
  }

  Future<void> _unlockBackgroundLock() async {
    await _runAction(() async {
      await _deviceApiService.unlockBackgroundLock(
        baseUrl: _baseUrlController.text,
      );
      await _refreshStatusSilently();
    }, successMessage: 'AI 锁机位已解除。');
  }

  _AiScanConfig _defaultAiScanConfig() {
    return _AiScanConfig(
      panRange: _aiPanScanRange,
      tiltRange: _aiTiltScanRange,
      panStep: _aiScanStepDegrees,
      tiltStep: math.max(1, _aiScanStepDegrees * 0.75),
      maxCandidates: _aiMaxCandidates,
      settleSeconds: _aiSettleSeconds,
      delaySeconds: _aiStartDelaySeconds,
    );
  }

  Future<_AiScanConfig?> _showAiScanConfigDialog({
    required String title,
    required bool includeDelay,
  }) {
    final initialConfig = _defaultAiScanConfig();
    return showDialog<_AiScanConfig>(
      context: context,
      builder: (context) => _AiScanConfigDialog(
        title: title,
        includeDelay: includeDelay,
        initialConfig: initialConfig,
      ),
    );
  }

  Future<void> _triggerCapture() async {
    final controller = _mobilePushCameraController;
    if (controller != null && controller.value.isInitialized) {
      final capture = await _captureDeviceLinkPhoto();
      if (capture != null && _analyzeCaptureAfterShot) {
        await _analyzeDeviceLinkPhotoAfterCapture(
          capture,
          reason: 'mobile_manual',
          source: 'manual_button',
        );
      }
      return;
    }
    setState(() {
      _errorMessage = '手机本地画面还没有启动，设备联动拍照不会再保存到树莓派。';
    });
  }

  Future<_DeviceLinkPhotoCaptureResult?> _captureDeviceLinkPhoto() async {
    final controller = _mobilePushCameraController;
    if (controller == null || !controller.value.isInitialized) {
      setState(() {
        _errorMessage = '手机画面还没有启动，不能拍摄照片。';
      });
      return null;
    }
    if (_isDeviceLinkRecordingVideo || controller.value.isRecordingVideo) {
      setState(() {
        _syncMessage = '录像中暂不拍照，请先停止录像。';
      });
      return null;
    }
    if (_isDeviceLinkCapturingPhoto || _isFinalizingDeviceLinkVideo) {
      return null;
    }

    setState(() {
      _isDeviceLinkCapturingPhoto = true;
      _errorMessage = null;
      _syncMessage = null;
    });

    try {
      final lensDirection =
          _mobilePushCamera?.lensDirection ?? _mobilePushLensDirection;
      final capture = await _takeMobilePushPicture(controller);
      final normalizedCapture = await _normalizeDeviceLinkPhoto(
        capture,
        lensDirection: lensDirection,
      );
      final galleryPath = await _saveDeviceLinkPhotoToGallery(
        normalizedCapture,
      );
      if (!mounted) {
        return null;
      }
      setState(() {
        _lastCapturePath = normalizedCapture.path;
        _syncMessage = galleryPath == null || galleryPath.isEmpty
            ? '照片已拍摄。'
            : '照片已保存到手机相册。';
        _addActionRecord('capture', _syncMessage!);
      });
      return _DeviceLinkPhotoCaptureResult(
        imagePath: normalizedCapture.path,
        galleryPath: galleryPath,
      );
    } on CameraException catch (error) {
      if (!mounted) {
        return null;
      }
      setState(() {
        _errorMessage = _cameraErrorMessage(error, fallback: '手机拍照失败。');
        _addActionRecord('error', _errorMessage!);
      });
      return null;
    } catch (error) {
      if (!mounted) {
        return null;
      }
      setState(() {
        _errorMessage = '手机拍照失败：$error';
        _addActionRecord('error', _errorMessage!);
      });
      return null;
    } finally {
      if (mounted) {
        setState(() {
          _isDeviceLinkCapturingPhoto = false;
        });
      }
    }
  }

  Future<XFile> _takeMobilePushPicture(CameraController controller) async {
    try {
      return await controller.takePicture();
    } on CameraException {
      if (!controller.value.isStreamingImages ||
          controller.value.isRecordingVideo) {
        rethrow;
      }
      await controller.stopImageStream();
      _markMobilePushFrameSendFinished();
      try {
        return await controller.takePicture();
      } finally {
        await _restartMobilePushImageStreamIfNeeded(controller);
      }
    }
  }

  Future<void> _triggerDeviceRuntimeCapture() async {
    await _runAction(() async {
      final captureResult = await _deviceApiService.triggerCapture(
        baseUrl: _baseUrlController.text,
        autoAnalyze: _analyzeCaptureAfterShot,
      );
      await _refreshStatusSilently();

      if (!mounted) {
        return;
      }

      setState(() {
        _rememberDeviceCapturePath(
          captureResult.path,
          source: 'device_runtime',
        );
        if (captureResult.analysis != null) {
          _setLastAiResult(
            title: 'AI 对话框',
            body: _formatCaptureAnalysisMap(
              captureResult.analysis!,
              capturePath: captureResult.path,
            ),
            kind: 'capture',
          );
        } else if (captureResult.analysisError != null) {
          _setLastAiResult(
            title: 'AI 对话框',
            body: captureResult.analysisError!,
            kind: 'capture',
          );
        }
        if (captureResult.analysisError != null) {
          _errorMessage = captureResult.analysisError;
        }
      });
      _queueAutoSaveDeviceCapturePath(captureResult.path);
      _handleMobileCaptureRequest(captureResult.mobileCaptureRequest);
    }, successMessage: '设备抓拍已触发。');
  }

  void _handleMobileCaptureRequest(DeviceMobileCaptureRequestSummary? request) {
    if (request == null || !request.isPending) {
      return;
    }
    if (!_handledMobileCaptureRequestIds.add(request.id)) {
      return;
    }
    unawaited(_completeMobileCaptureRequest(request));
  }

  Future<void> _completeMobileCaptureRequest(
    DeviceMobileCaptureRequestSummary request,
  ) async {
    _DeviceLinkPhotoCaptureResult? capture;
    String? error;
    try {
      capture = await _captureDeviceLinkPhoto();
      if (capture == null || capture.imagePath.trim().isEmpty) {
        error = _errorMessage ?? _syncMessage ?? '手机拍照未完成。';
      } else if (request.autoAnalyze || _analyzeCaptureAfterShot) {
        await _analyzeDeviceLinkPhotoAfterCapture(
          capture,
          reason: request.reason ?? 'mobile_capture_request',
          source: 'device_mobile_capture_request',
        );
      }
    } catch (exception) {
      error = exception.toString();
    }

    try {
      final status = await _deviceApiService.acknowledgeMobileCapture(
        baseUrl: _baseUrlController.text,
        requestId: request.id,
        success: error == null,
        localPath: capture?.imagePath,
        error: error,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _status = status;
        _lastStatusUpdatedAt = DateTime.now();
      });
    } catch (exception) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = '手机抓拍已处理，但设备回执失败：$exception';
        _addActionRecord('error', _errorMessage!);
      });
    }
  }

  Future<AiTaskSummary?> _analyzeDeviceLinkPhotoAfterCapture(
    _DeviceLinkPhotoCaptureResult capture, {
    required String reason,
    required String source,
  }) async {
    if (_isAnalyzingDeviceLinkCapture) {
      return null;
    }
    if (!mounted) {
      return null;
    }

    setState(() {
      _isAnalyzingDeviceLinkCapture = true;
      _errorMessage = null;
      _syncMessage = '照片已保存到手机，正在上传服务器 AI 分析。';
      _setLastAiResult(
        title: 'AI 对话框',
        body: '照片已保存到手机相册，正在上传服务器并交给云端 AI 分析。',
        kind: 'capture',
      );
    });

    try {
      final historySession = await _ensureDeviceHistorySession();
      final uploadedFile = await widget.mobileApiService.uploadCaptureFile(
        accessToken: widget.accessToken,
        filePath: capture.imagePath,
      );
      final uploadedCapture = await widget.mobileApiService.createCapture(
        accessToken: widget.accessToken,
        sessionId: historySession.id,
        fileUrl: uploadedFile.fileUrl,
        captureType: 'single',
        width: _mobilePushCameraController?.value.previewSize?.height.round(),
        height: _mobilePushCameraController?.value.previewSize?.width.round(),
        storageProvider: uploadedFile.storageProvider,
        metadata: <String, dynamic>{
          'media_type': 'photo',
          'local_album_saved':
              capture.galleryPath != null && capture.galleryPath!.isNotEmpty,
          'duration_ms': null,
          'local_path': capture.imagePath,
          if (capture.galleryPath != null && capture.galleryPath!.isNotEmpty)
            'local_album_path': capture.galleryPath,
          'source': source,
          'entry': 'device_link_page',
          'device_capture_reason': reason,
          'device_base_url': _normalizedDeviceBaseUrl(_baseUrlController.text),
          'device_session_code':
              _status?.sessionCode ?? _sessionCodeController.text.trim(),
          'stream_url': _streamUrlController.text.trim(),
          'mobile_platform': Platform.operatingSystem,
          'storage_path': uploadedFile.storagePath,
          'relative_path': uploadedFile.relativePath,
          'original_filename': uploadedFile.originalFilename,
          'content_type': uploadedFile.contentType,
          'auto_analyze_requested': true,
          'selected_template_id': _selectedTemplate?.id,
          'selected_template_name': _selectedTemplate?.name,
        },
      );
      final task = await widget.mobileApiService.analyzePhoto(
        accessToken: widget.accessToken,
        sessionId: historySession.id,
        captureId: uploadedCapture.id,
      );
      if (!mounted) {
        return task;
      }
      setState(() {
        _deviceHistorySession = historySession;
        _deviceHistoryCaptureIds[capture.imagePath] = uploadedCapture.id;
        _lastBackendAiTask = task;
        _preferredAiResultKind = 'capture';
        _syncMessage = task.status == 'succeeded'
            ? '照片已交给服务器 AI 分析完成。'
            : '照片已上传，但本次 AI 分析未成功。';
        _errorMessage = task.status == 'succeeded'
            ? null
            : task.errorMessage ?? 'AI 分析失败，请检查后台 AI Provider 配置。';
        _setLastAiResult(
          title: 'AI 对话框',
          body: _formatDeviceLinkPhotoAiTask(
            task,
            capturePath: capture.imagePath,
          ),
          kind: 'capture',
        );
        _addActionRecord(
          task.status == 'succeeded' ? 'ai' : 'error',
          _syncMessage!,
        );
      });
      return task;
    } on ApiException catch (error) {
      if (mounted) {
        setState(() {
          _errorMessage = '照片已保存到手机，但 AI 分析失败：${error.message}';
          _setLastAiResult(
            title: 'AI 对话框',
            body: _errorMessage!,
            kind: 'capture',
          );
          _addActionRecord('error', _errorMessage!);
        });
      }
      return null;
    } catch (error) {
      if (mounted) {
        setState(() {
          _errorMessage = '照片已保存到手机，但上传或 AI 分析失败：$error';
          _setLastAiResult(
            title: 'AI 对话框',
            body: _errorMessage!,
            kind: 'capture',
          );
          _addActionRecord('error', _errorMessage!);
        });
      }
      return null;
    } finally {
      if (mounted) {
        setState(() {
          _isAnalyzingDeviceLinkCapture = false;
        });
      }
    }
  }

  Future<void> _pauseDeviceLinkPreviewForRecording(
    CameraController controller,
  ) async {
    if (_isDeviceLinkRecordingPreviewPaused) {
      return;
    }
    if (!controller.value.isInitialized) {
      return;
    }
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return;
    }
    if (controller.value.isPreviewPaused) {
      _isDeviceLinkRecordingPreviewPaused = true;
      return;
    }

    await controller.pausePreview();
    _isDeviceLinkRecordingPreviewPaused = true;
  }

  Future<void> _resumeDeviceLinkPreviewAfterRecording(
    CameraController controller,
  ) async {
    if (!_isDeviceLinkRecordingPreviewPaused) {
      return;
    }
    if (!controller.value.isInitialized || !controller.value.isPreviewPaused) {
      _isDeviceLinkRecordingPreviewPaused = false;
      return;
    }

    await controller.resumePreview();
    _isDeviceLinkRecordingPreviewPaused = false;
  }

  Future<void> _tryResumeDeviceLinkPreviewAfterRecording(
    CameraController controller,
  ) async {
    try {
      await _resumeDeviceLinkPreviewAfterRecording(controller);
    } catch (_) {
      // Best effort: the recording result and stream recovery should not be
      // masked by a preview rebind failure.
    }
  }

  Future<void> _startDeviceLinkVideoRecording() async {
    final controller = _mobilePushCameraController;
    if (controller == null || !controller.value.isInitialized) {
      setState(() {
        _errorMessage = '手机画面还没有启动，不能开始录像。';
      });
      return;
    }
    if (_isDeviceLinkRecordingVideo ||
        _isFinalizingDeviceLinkVideo ||
        _isDeviceLinkCapturingPhoto ||
        controller.value.isRecordingVideo) {
      return;
    }

    setState(() {
      _errorMessage = null;
      _syncMessage = null;
      _deviceLinkRecordingPreviewBytes = null;
      _lastRecordingPreviewFrameAtMs = 0;
    });

    var stoppedStream = false;
    var pausedPreviewForRecording = false;
    try {
      if (controller.value.isStreamingImages) {
        await controller.stopImageStream();
        _markMobilePushFrameSendFinished();
        stoppedStream = true;
      }
      await _pauseDeviceLinkPreviewForRecording(controller);
      pausedPreviewForRecording = _isDeviceLinkRecordingPreviewPaused;
      await controller.prepareForVideoRecording();
      await controller.startVideoRecording(
        onAvailable: _handleMobilePushFrame,
        enablePersistentRecording: true,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _isDeviceLinkRecordingVideo = true;
        _deviceLinkRecordingStartedAt = DateTime.now();
        _syncMessage = '录像已开始，自动跟随保持中。';
        _addActionRecord('capture', '设备联动录像已开始。');
      });
    } on CameraException catch (error) {
      if (pausedPreviewForRecording && !controller.value.isRecordingVideo) {
        await _tryResumeDeviceLinkPreviewAfterRecording(controller);
      }
      if (stoppedStream) {
        await _restartMobilePushImageStreamIfNeeded(controller);
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = _cameraErrorMessage(error, fallback: '手机录像启动失败。');
        _addActionRecord('error', _errorMessage!);
      });
    } catch (error) {
      if (pausedPreviewForRecording && !controller.value.isRecordingVideo) {
        await _tryResumeDeviceLinkPreviewAfterRecording(controller);
      }
      if (stoppedStream) {
        await _restartMobilePushImageStreamIfNeeded(controller);
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = '手机录像启动失败：$error';
        _addActionRecord('error', _errorMessage!);
      });
    }
  }

  Future<void> _stopDeviceLinkVideoRecording({
    bool resumeStream = true,
    bool silent = false,
  }) async {
    final controller = _mobilePushCameraController;
    if (controller == null ||
        !controller.value.isInitialized ||
        !controller.value.isRecordingVideo ||
        _isFinalizingDeviceLinkVideo) {
      return;
    }

    final startedAt = _deviceLinkRecordingStartedAt;
    if (mounted) {
      setState(() {
        _isFinalizingDeviceLinkVideo = true;
      });
    }

    try {
      final video = await controller.stopVideoRecording();
      if (resumeStream) {
        await _tryResumeDeviceLinkPreviewAfterRecording(controller);
      }
      final galleryPath = await _saveDeviceLinkVideoToGallery(video);
      if (resumeStream) {
        await _restartMobilePushImageStreamIfNeeded(controller);
      }
      if (!mounted) {
        return;
      }
      final duration = startedAt == null
          ? Duration.zero
          : DateTime.now().difference(startedAt);
      setState(() {
        _isDeviceLinkRecordingVideo = false;
        _isFinalizingDeviceLinkVideo = false;
        _deviceLinkRecordingPreviewBytes = null;
        _lastRecordingPreviewFrameAtMs = 0;
        _deviceLinkRecordingStartedAt = null;
        _syncMessage = galleryPath == null || galleryPath.isEmpty
            ? '视频已录制。'
            : '视频已保存到手机相册。';
        _addActionRecord('capture', '设备联动录像已保存 ${duration.inSeconds}s。');
      });
    } on CameraException catch (error) {
      if (resumeStream && !controller.value.isRecordingVideo) {
        await _tryResumeDeviceLinkPreviewAfterRecording(controller);
      }
      if (resumeStream) {
        await _restartMobilePushImageStreamIfNeeded(controller);
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _isDeviceLinkRecordingVideo = false;
        _isFinalizingDeviceLinkVideo = false;
        _deviceLinkRecordingPreviewBytes = null;
        _lastRecordingPreviewFrameAtMs = 0;
        _deviceLinkRecordingStartedAt = null;
        if (!silent) {
          _errorMessage = _cameraErrorMessage(error, fallback: '手机录像停止失败。');
          _addActionRecord('error', _errorMessage!);
        }
      });
    } finally {
      if (mounted) {
        setState(() {
          _isFinalizingDeviceLinkVideo = false;
        });
      }
    }
  }

  Future<void> _toggleDeviceLinkVideoRecording() {
    return _isDeviceLinkRecordingVideo
        ? _stopDeviceLinkVideoRecording()
        : _startDeviceLinkVideoRecording();
  }

  Future<void> _restartMobilePushImageStreamIfNeeded(
    CameraController controller,
  ) async {
    if (!_isMobilePushEnabled ||
        !controller.value.isInitialized ||
        controller.value.isRecordingVideo ||
        controller.value.isStreamingImages) {
      return;
    }
    await controller.startImageStream(_handleMobilePushFrame);
  }

  Future<XFile> _normalizeDeviceLinkPhoto(
    XFile capture, {
    required CameraLensDirection lensDirection,
  }) async {
    if (lensDirection != CameraLensDirection.front) {
      return capture;
    }

    try {
      final file = File(capture.path);
      final sourceBytes = await file.readAsBytes();
      final decoded = img.decodeImage(sourceBytes);
      if (decoded == null) {
        return capture;
      }

      final oriented = img.bakeOrientation(decoded);
      final corrected = img.flipHorizontal(oriented);
      final lowerPath = capture.path.toLowerCase();
      final encoded = lowerPath.endsWith('.png')
          ? img.encodePng(corrected)
          : img.encodeJpg(corrected, quality: 92);
      await file.writeAsBytes(encoded, flush: true);
    } catch (_) {
      // Keep capture responsive even if front-camera normalization fails.
    }

    return capture;
  }

  String _timestampedDeviceLinkMediaFileName({
    required String prefix,
    required String path,
    required String fallbackExtension,
  }) {
    final now = DateTime.now();
    final stamp =
        '${now.year.toString().padLeft(4, '0')}'
        '${now.month.toString().padLeft(2, '0')}'
        '${now.day.toString().padLeft(2, '0')}_'
        '${now.hour.toString().padLeft(2, '0')}'
        '${now.minute.toString().padLeft(2, '0')}'
        '${now.second.toString().padLeft(2, '0')}';
    final rawExtension = path.split('.').last.toLowerCase();
    final extension = rawExtension == path.toLowerCase() || rawExtension.isEmpty
        ? fallbackExtension
        : rawExtension;
    return '${prefix}_$stamp.$extension';
  }

  Future<String?> _saveDeviceLinkPhotoToGallery(XFile capture) async {
    return _gallerySaveService.saveImageFile(
      path: capture.path,
      fileName: _timestampedDeviceLinkMediaFileName(
        prefix: 'camera_assistant_device_photo',
        path: capture.path,
        fallbackExtension: 'jpg',
      ),
    );
  }

  Future<String?> _saveDeviceLinkVideoToGallery(XFile video) async {
    return _gallerySaveService.saveVideoFile(
      path: video.path,
      fileName: _timestampedDeviceLinkMediaFileName(
        prefix: 'camera_assistant_device_video',
        path: video.path,
        fallbackExtension: 'mp4',
      ),
    );
  }

  String _cameraErrorMessage(
    CameraException error, {
    required String fallback,
  }) {
    final description = error.description;
    if (description != null && description.trim().isNotEmpty) {
      return '$fallback ${description.trim()}';
    }
    return '$fallback ${error.code}';
  }

  Future<void> _runBackendAngleSearchFromCurrentFrame(
    _AiScanConfig config,
  ) async {
    await _waitForBackendAiStartDelay(
      config,
      actionLabel: '自动找角度',
      kind: 'angle',
    );
    if (!mounted) {
      return;
    }
    final scan = await _runBackendAiCandidateScan(
      config: config,
      aiIntent: 'auto_angle',
      taskType: 'auto_angle',
      kind: 'angle',
      startMessage: '手机将控制树莓派逐个候选角度转动，先缓存每个角度的手机画面，最后统一上传服务器评分。',
    );
    final bestFrame = _pickBestAiScanFrame(scan);
    final task = scan.task;
    final finalPanOffset = _clampAiDeltaToRange(
      bestFrame.candidate.panOffset + (task.recommendedPanDelta ?? 0),
      config.panRange,
    );
    final finalTiltOffset = _clampAiDeltaToRange(
      bestFrame.candidate.tiltOffset + (task.recommendedTiltDelta ?? 0),
      config.tiltRange,
    );
    await _returnGimbalToBestAiScanCandidate(
      scan: scan,
      bestFrame: bestFrame,
      kind: 'angle',
    );
    final status = await _deviceApiService.applyAngle(
      baseUrl: _baseUrlController.text,
      recommendedPanDelta: finalPanOffset - bestFrame.candidate.panOffset,
      recommendedTiltDelta: finalTiltOffset - bestFrame.candidate.tiltOffset,
      summary: task.resultSummary ?? '服务器 AI 已从多角度扫描中选出最佳角度。',
      score: (task.resultScore ?? 88).toDouble(),
    );

    if (!mounted) {
      return;
    }
    setState(() {
      _status = status;
      _lastBackendAiTask = task;
      _lastStatusUpdatedAt = DateTime.now();
      _setLastAiResult(
        title: 'AI 对话框',
        body: _formatBackendAiScanResultForHud(
          scan,
          bestFrame,
          finalPanOffset: finalPanOffset,
          finalTiltOffset: finalTiltOffset,
          fallback: '服务器 AI 已完成多角度自动找角度，并回到最佳机位。',
        ),
        kind: 'angle',
      );
    });
  }

  Future<void> _runBackendBackgroundLockFromCurrentFrame(
    _AiScanConfig config,
  ) async {
    await _waitForBackendAiStartDelay(
      config,
      actionLabel: '背景锁定',
      kind: 'background',
    );
    if (!mounted) {
      return;
    }
    final scan = await _runBackendAiCandidateScan(
      config: config,
      aiIntent: 'background_lock',
      taskType: 'analyze_background',
      kind: 'background',
      startMessage: '手机将控制树莓派逐个候选角度转动，先缓存每个角度的手机画面，最后统一上传服务器做背景锁定评分。',
    );
    final bestFrame = _pickBestAiScanFrame(scan);
    final task = scan.task;
    final targetBoxNorm = task.targetBoxNorm;
    final panDelta = task.recommendedPanDelta;
    final tiltDelta = task.recommendedTiltDelta;
    if (targetBoxNorm == null || panDelta == null || tiltDelta == null) {
      throw const ApiException('后端 AI 没有返回完整的背景锁定数据。');
    }
    final finalPanOffset = _clampAiDeltaToRange(
      bestFrame.candidate.panOffset + panDelta,
      config.panRange,
    );
    final finalTiltOffset = _clampAiDeltaToRange(
      bestFrame.candidate.tiltOffset + tiltDelta,
      config.tiltRange,
    );

    await _returnGimbalToBestAiScanCandidate(
      scan: scan,
      bestFrame: bestFrame,
      kind: 'background',
    );
    final status = await _deviceApiService.applyLock(
      baseUrl: _baseUrlController.text,
      recommendedPanDelta: finalPanOffset - bestFrame.candidate.panOffset,
      recommendedTiltDelta: finalTiltOffset - bestFrame.candidate.tiltOffset,
      targetBoxNorm: targetBoxNorm,
      summary: task.resultSummary ?? '服务器 AI 已从多角度扫描中选出背景锁定机位。',
      score: (task.resultScore ?? 92).toDouble(),
    );

    if (!mounted) {
      return;
    }
    setState(() {
      _status = status;
      _lastBackendAiTask = task;
      _lastStatusUpdatedAt = DateTime.now();
      _setLastAiResult(
        title: 'AI 对话框',
        body: _formatBackendAiScanResultForHud(
          scan,
          bestFrame,
          finalPanOffset: finalPanOffset,
          finalTiltOffset: finalTiltOffset,
          fallback: '服务器 AI 已完成多角度背景锁定，并显示锁定位框。',
        ),
        kind: 'background',
      );
    });
  }

  Future<void> _returnGimbalToBestAiScanCandidate({
    required _AiScanRunResult scan,
    required _AiScanFrame bestFrame,
    required String kind,
  }) async {
    final panDelta =
        bestFrame.candidate.panOffset - scan.lastCandidate.panOffset;
    final tiltDelta =
        bestFrame.candidate.tiltOffset - scan.lastCandidate.tiltOffset;
    if (panDelta.abs() <= 0.01 && tiltDelta.abs() <= 0.01) {
      return;
    }
    if (mounted) {
      setState(() {
        _setLastAiResult(
          title: 'AI 对话框',
          body:
              '正在转回 AI 评分最高的角度：水平 ${bestFrame.candidate.panOffset.toStringAsFixed(1)}°，俯仰 ${bestFrame.candidate.tiltOffset.toStringAsFixed(1)}°。',
          kind: kind,
        );
      });
    }
    final status = await _deviceApiService.manualMove(
      baseUrl: _baseUrlController.text,
      panDelta: panDelta,
      tiltDelta: tiltDelta,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _status = status;
      _lastStatusUpdatedAt = DateTime.now();
    });
  }

  Future<_AiScanRunResult> _runBackendAiCandidateScan({
    required _AiScanConfig config,
    required String aiIntent,
    required String taskType,
    required String kind,
    required String startMessage,
  }) async {
    final candidates = _buildAiScanCandidates(config);
    if (candidates.isEmpty) {
      throw const ApiException('没有可用的候选角度，请检查扫描参数。');
    }

    setState(() {
      _isMobileAiScanning = true;
      _setLastAiResult(
        title: 'AI 对话框',
        body: '$startMessage\n候选数量：${candidates.length}',
        kind: kind,
      );
    });

    final frames = <_AiScanFrame>[];
    var currentCandidate = const _AiScanCandidate(
      index: 0,
      panOffset: 0,
      tiltOffset: 0,
    );

    try {
      for (final candidate in candidates) {
        final panMove = candidate.panOffset - currentCandidate.panOffset;
        final tiltMove = candidate.tiltOffset - currentCandidate.tiltOffset;
        setState(() {
          _setLastAiResult(
            title: 'AI 对话框',
            body:
                '正在扫描 ${candidate.index}/${candidates.length}：'
                '水平 ${candidate.panOffset.toStringAsFixed(1)}°，'
                '俯仰 ${candidate.tiltOffset.toStringAsFixed(1)}°。',
            kind: kind,
          );
        });
        if (panMove.abs() > 0.01 || tiltMove.abs() > 0.01) {
          setState(() {
            _setLastAiResult(
              title: 'AI 对话框',
              body:
                  '正在转到 ${candidate.index}/${candidates.length}：'
                  '水平 ${candidate.panOffset.toStringAsFixed(1)}°，'
                  '俯仰 ${candidate.tiltOffset.toStringAsFixed(1)}°。',
              kind: kind,
            );
          });
          final status = await _deviceApiService.manualMove(
            baseUrl: _baseUrlController.text,
            panDelta: panMove,
            tiltDelta: tiltMove,
          );
          if (mounted) {
            setState(() {
              _status = status;
              _lastStatusUpdatedAt = DateTime.now();
            });
          }
        } else {
          setState(() {
            _setLastAiResult(
              title: 'AI 对话框',
              body:
                  '正在扫描 ${candidate.index}/${candidates.length}：'
                  '当前是中心基准位，不需要转动，准备抓取手机画面。',
              kind: kind,
            );
          });
        }
        currentCandidate = candidate;
        setState(() {
          _setLastAiResult(
            title: 'AI 对话框',
            body:
                '等待云台稳定 ${config.settleSeconds.toStringAsFixed(1)} 秒：'
                '${candidate.index}/${candidates.length}。',
            kind: kind,
          );
        });
        await _waitForAiScanSettle(config);
        final minFrameCapturedAtMs = DateTime.now().millisecondsSinceEpoch;

        setState(() {
          _setLastAiResult(
            title: 'AI 对话框',
            body:
                '正在缓存手机画面：'
                '${candidate.index}/${candidates.length}。',
            kind: kind,
          );
        });
        final frame = await _cacheBackendAiFrameFromCurrentFrame(
          aiIntent: aiIntent,
          config: config,
          candidate: candidate,
          candidateCount: candidates.length,
          minFrameCapturedAtMs: minFrameCapturedAtMs,
        );
        frames.add(frame);
        if (mounted) {
          setState(() {
            _setLastAiResult(
              title: 'AI 对话框',
              body:
                  '已缓存 ${candidate.index}/${candidates.length} 张候选图，'
                  '稍后统一发送给服务器 AI 比较。',
              kind: kind,
            );
          });
        }
      }

      if (frames.isEmpty) {
        throw const ApiException('多角度扫描没有得到可用的手机画面。');
      }
      if (mounted) {
        setState(() {
          _setLastAiResult(
            title: 'AI 对话框',
            body: '正在把 ${frames.length} 张候选图统一发送给服务器 AI。',
            kind: kind,
          );
        });
      }
      final task = await widget.mobileApiService.analyzeScan(
        accessToken: widget.accessToken,
        taskType: taskType,
        filePaths: frames.map((frame) => frame.path).toList(growable: false),
        candidates: frames
            .map((frame) => frame.toCandidateJson())
            .toList(growable: false),
        metadata: <String, dynamic>{
          'entry': 'device_link_page',
          'source': 'mobile_multi_angle_scan',
          'ai_intent': aiIntent,
          'ai_pipeline': 'mobile_cached_multi_angle_backend_cloud',
          'candidate_count': frames.length,
          'device_base_url': _normalizedDeviceBaseUrl(_baseUrlController.text),
          'device_session_code':
              _status?.sessionCode ?? _sessionCodeController.text.trim(),
          'stream_url': _streamUrlController.text.trim(),
          'mobile_platform': Platform.operatingSystem,
          'selected_template_id': _selectedTemplate?.id,
          'selected_template_name': _selectedTemplate?.name,
          'ai_config': _aiScanConfigMetadata(config),
        },
      );
      if (task.status != 'succeeded') {
        throw ApiException(
          task.errorMessage ?? '后端 AI 分析失败，请检查服务器 AI Provider 配置。',
        );
      }
      final bestFrame = _pickBestAiScanFrameFromFrames(frames, task);
      String? bestGalleryPath;
      String? bestGalleryError;
      if (taskType == 'auto_angle') {
        try {
          bestGalleryPath = await _saveAiScanBestFrameToGallery(bestFrame);
        } catch (error) {
          bestGalleryError = error.toString();
        }
      }
      if (mounted) {
        setState(() {
          _lastBackendAiTask = task;
          if (bestGalleryError != null) {
            _errorMessage = '最佳角度照片保存到手机相册失败：$bestGalleryError';
          }
          _setLastAiResult(
            title: 'AI 对话框',
            body:
                '服务器 AI 已统一比较 ${frames.length} 张候选图，'
                '正在应用最佳机位。',
            kind: kind,
          );
        });
      }
      return _AiScanRunResult(
        candidates: candidates,
        frames: List<_AiScanFrame>.unmodifiable(frames),
        task: task,
        lastCandidate: currentCandidate,
        bestGalleryPath: bestGalleryPath,
        bestGalleryError: bestGalleryError,
      );
    } finally {
      await _deleteAiScanTempFrames(frames);
      if (mounted) {
        setState(() {
          _isMobileAiScanning = false;
        });
      }
    }
  }

  Future<void> _waitForBackendAiStartDelay(
    _AiScanConfig config, {
    required String actionLabel,
    required String kind,
  }) async {
    final delayMs = (config.delaySeconds * 1000).round();
    if (delayMs <= 0) {
      return;
    }
    final delaySeconds = (delayMs / 1000).toStringAsFixed(
      delayMs % 1000 == 0 ? 0 : 1,
    );
    setState(() {
      _setLastAiResult(
        title: 'AI 对话框',
        body: '$actionLabel 将在 $delaySeconds 秒后开始扫描候选机位。',
        kind: kind,
      );
    });
    await Future<void>.delayed(Duration(milliseconds: delayMs));
  }

  Future<_AiScanFrame> _cacheBackendAiFrameFromCurrentFrame({
    required String aiIntent,
    required _AiScanConfig config,
    required _AiScanCandidate candidate,
    required int candidateCount,
    required int minFrameCapturedAtMs,
  }) async {
    final controller = _mobilePushCameraController;
    if (controller == null || !controller.value.isInitialized) {
      throw const ApiException('手机本地画面还没有启动，无法缓存当前画面给服务器 AI。');
    }
    if (_isFinalizingDeviceLinkVideo) {
      throw const ApiException('当前正在处理录像文件，请稍后再试。');
    }

    try {
      final lensDirection =
          _mobilePushCamera?.lensDirection ?? _mobilePushLensDirection;
      final snapshot = await _takeBackendAiSnapshot(
        controller,
        lensDirection: lensDirection,
        minFrameCapturedAtMs: minFrameCapturedAtMs,
      );
      return _AiScanFrame(
        candidate: candidate,
        path: snapshot.path,
        metadata: <String, dynamic>{
          'ai_intent': aiIntent,
          'candidate_count': candidateCount,
          'ai_config': _aiScanConfigMetadata(config),
        },
      );
    } on TimeoutException {
      throw const ApiException('手机画面抓取超时，请确认设备联动页推流画面正在刷新。');
    } on CameraException catch (error) {
      throw ApiException(_cameraErrorMessage(error, fallback: '手机画面抓取失败。'));
    }
  }

  Future<void> _deleteAiScanTempFrames(List<_AiScanFrame> frames) async {
    for (final frame in frames) {
      try {
        final file = File(frame.path);
        if (await file.exists()) {
          await file.delete();
        }
      } on FileSystemException {
        // Best effort cleanup for cached AI scan frames.
      }
    }
  }

  Future<void> _waitForAiScanSettle(_AiScanConfig config) async {
    final waitMs = math.max(0, (config.settleSeconds * 1000).round());
    if (waitMs <= 0) {
      return;
    }
    await Future<void>.delayed(Duration(milliseconds: waitMs));
  }

  List<_AiScanCandidate> _buildAiScanCandidates(_AiScanConfig config) {
    final panValues = _axisScanValues(config.panRange, config.panStep);
    final tiltValues = _axisScanValues(config.tiltRange, config.tiltStep);
    final grid = <_AiScanCandidate>[
      for (final pan in panValues)
        for (final tilt in tiltValues)
          _AiScanCandidate(index: 0, panOffset: pan, tiltOffset: tilt),
    ];
    if (grid.isEmpty) {
      return const <_AiScanCandidate>[];
    }

    final maxCount = math.min(math.max(1, config.maxCandidates), grid.length);
    final selected = <_AiScanCandidate>[];
    final origin = grid.reduce((best, item) {
      final bestDistance = best.panOffset.abs() + best.tiltOffset.abs();
      final itemDistance = item.panOffset.abs() + item.tiltOffset.abs();
      return itemDistance < bestDistance ? item : best;
    });
    selected.add(origin);

    while (selected.length < maxCount) {
      _AiScanCandidate? best;
      var bestScore = -1.0;
      for (final candidate in grid) {
        if (_containsAiCandidate(selected, candidate)) {
          continue;
        }
        final minDistance = selected
            .map((item) => _aiCandidateDistance(candidate, item, config))
            .reduce(math.min);
        final centerDistance = _aiCandidateDistance(candidate, origin, config);
        final score = minDistance + centerDistance * 0.04;
        if (score > bestScore) {
          bestScore = score;
          best = candidate;
        }
      }
      if (best == null) {
        break;
      }
      selected.add(best);
    }

    final ordered = <_AiScanCandidate>[origin];
    final remaining = selected
        .where((item) => !_sameAiCandidate(item, origin))
        .toList();
    var current = origin;
    while (remaining.isNotEmpty) {
      remaining.sort(
        (a, b) => _aiCandidateDistance(
          a,
          current,
          config,
        ).compareTo(_aiCandidateDistance(b, current, config)),
      );
      current = remaining.removeAt(0);
      ordered.add(current);
    }

    return <_AiScanCandidate>[
      for (var index = 0; index < ordered.length; index += 1)
        ordered[index].copyWith(index: index + 1),
    ];
  }

  List<double> _axisScanValues(double range, double step) {
    final safeRange = range.abs();
    final safeStep = step.abs();
    if (safeRange <= 0) {
      return const <double>[0];
    }
    final values = <double>{0, -safeRange, safeRange};
    if (safeStep > 0) {
      var next = safeStep;
      while (next < safeRange) {
        final value = _roundScanDegrees(next);
        values.add(-value);
        values.add(value);
        next += safeStep;
      }
    }
    final sorted = values.map(_roundScanDegrees).toList()..sort();
    return sorted;
  }

  bool _containsAiCandidate(
    List<_AiScanCandidate> candidates,
    _AiScanCandidate candidate,
  ) {
    return candidates.any((item) => _sameAiCandidate(item, candidate));
  }

  bool _sameAiCandidate(_AiScanCandidate a, _AiScanCandidate b) {
    return (a.panOffset - b.panOffset).abs() < 0.001 &&
        (a.tiltOffset - b.tiltOffset).abs() < 0.001;
  }

  double _aiCandidateDistance(
    _AiScanCandidate a,
    _AiScanCandidate b,
    _AiScanConfig config,
  ) {
    final panScale = math.max(1.0, config.panRange.abs());
    final tiltScale = math.max(1.0, config.tiltRange.abs());
    final pan = (a.panOffset - b.panOffset) / panScale;
    final tilt = (a.tiltOffset - b.tiltOffset) / tiltScale;
    return math.sqrt(pan * pan + tilt * tilt);
  }

  double _roundScanDegrees(double value) {
    return double.parse(value.toStringAsFixed(3));
  }

  _AiScanFrame _pickBestAiScanFrame(_AiScanRunResult scan) {
    return _pickBestAiScanFrameFromFrames(scan.frames, scan.task);
  }

  _AiScanFrame _pickBestAiScanFrameFromFrames(
    List<_AiScanFrame> frames,
    AiTaskSummary task,
  ) {
    if (frames.isEmpty) {
      throw const ApiException('没有可用的后端 AI 候选图结果。');
    }
    final bestIndex = _readBestCandidateIndex(task.responsePayload);
    if (bestIndex != null) {
      for (final frame in frames) {
        if (frame.candidate.index == bestIndex) {
          return frame;
        }
      }
    }
    return frames.first;
  }

  Future<String?> _saveAiScanBestFrameToGallery(_AiScanFrame frame) {
    return _gallerySaveService.saveImageFile(
      path: frame.path,
      fileName: _timestampedDeviceLinkMediaFileName(
        prefix: 'camera_assistant_best_angle',
        path: frame.path,
        fallbackExtension: 'jpg',
      ),
    );
  }

  int? _readBestCandidateIndex(Map<String, dynamic> responsePayload) {
    final raw = responsePayload['best_candidate_index'];
    if (raw is int) {
      return raw;
    }
    if (raw is num) {
      return raw.round();
    }
    if (raw is String) {
      return int.tryParse(raw.trim());
    }
    return null;
  }

  Future<XFile> _takeBackendAiSnapshot(
    CameraController controller, {
    required CameraLensDirection lensDirection,
    required int minFrameCapturedAtMs,
  }) async {
    final cachedSnapshot = await _takeCachedMobileAiSnapshot(
      lensDirection: lensDirection,
      minFrameCapturedAtMs: minFrameCapturedAtMs,
    );
    if (cachedSnapshot != null) {
      return cachedSnapshot;
    }

    if (controller.value.isRecordingVideo) {
      try {
        final capture = await controller.takePicture().timeout(
          const Duration(seconds: 3),
        );
        return _normalizeDeviceLinkPhoto(capture, lensDirection: lensDirection);
      } on CameraException {
        final previewBytes = _deviceLinkRecordingPreviewBytes;
        if (previewBytes == null || previewBytes.isEmpty) {
          throw const ApiException('录像中暂时还没有可用的手机画面，请等画面更新后再试。');
        }
        final tempDir = await getTemporaryDirectory();
        final file = File(
          '${tempDir.path}/device_link_ai_${DateTime.now().millisecondsSinceEpoch}.jpg',
        );
        await file.writeAsBytes(previewBytes, flush: true);
        return _normalizeDeviceLinkPhoto(
          XFile(file.path),
          lensDirection: lensDirection,
        );
      }
    }

    final capture = await _takeMobilePushPicture(
      controller,
    ).timeout(const Duration(seconds: 4));
    return _normalizeDeviceLinkPhoto(capture, lensDirection: lensDirection);
  }

  Future<XFile?> _takeCachedMobileAiSnapshot({
    required CameraLensDirection lensDirection,
    required int minFrameCapturedAtMs,
  }) async {
    final deadline = DateTime.now().add(_mobileAiFrameFreshTimeout);
    while (DateTime.now().isBefore(deadline)) {
      final bytes = _latestMobileAiFrameBytes;
      final frameAtMs = _latestMobileAiFrameAtMs;
      if (bytes != null &&
          bytes.isNotEmpty &&
          frameAtMs >= minFrameCapturedAtMs) {
        return _writeCachedMobileAiFrame(bytes, lensDirection: lensDirection);
      }
      await Future<void>.delayed(const Duration(milliseconds: 80));
    }
    final bytes = _latestMobileAiFrameBytes;
    final frameAtMs = _latestMobileAiFrameAtMs;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    if (bytes != null &&
        bytes.isNotEmpty &&
        nowMs - frameAtMs <= _mobileAiFrameMaxAge.inMilliseconds) {
      return _writeCachedMobileAiFrame(bytes, lensDirection: lensDirection);
    }
    return null;
  }

  Future<XFile> _writeCachedMobileAiFrame(
    Uint8List bytes, {
    required CameraLensDirection lensDirection,
  }) async {
    final tempDir = await getTemporaryDirectory();
    final file = File(
      '${tempDir.path}/device_link_ai_${DateTime.now().millisecondsSinceEpoch}.jpg',
    );
    await file.writeAsBytes(bytes, flush: true);
    return _normalizeDeviceLinkPhoto(
      XFile(file.path),
      lensDirection: lensDirection,
    );
  }

  Map<String, dynamic> _aiScanConfigMetadata(_AiScanConfig config) {
    return <String, dynamic>{
      'pan_range': config.panRange,
      'tilt_range': config.tiltRange,
      'pan_step': config.panStep,
      'tilt_step': config.tiltStep,
      'max_candidates': config.maxCandidates,
      'settle_s': config.settleSeconds,
      'delay_s': config.delaySeconds,
    };
  }

  double _clampAiDeltaToRange(double value, double range) {
    if (!value.isFinite) {
      return 0;
    }
    if (!range.isFinite || range <= 0) {
      return value;
    }
    return value.clamp(-range, range).toDouble();
  }

  String _formatBackendAiTaskForHud(
    AiTaskSummary task, {
    required String fallback,
  }) {
    final lines = <String>[
      if (task.resultSummary?.trim().isNotEmpty == true)
        task.resultSummary!.trim()
      else
        fallback,
    ];
    final score = task.resultScore;
    if (score != null) {
      lines.add('构图分数：${score.toStringAsFixed(1)}');
    }
    final panDelta = task.recommendedPanDelta;
    final tiltDelta = task.recommendedTiltDelta;
    if (panDelta != null || tiltDelta != null) {
      lines.add(
        '建议转动：水平 ${(panDelta ?? 0).toStringAsFixed(1)}°，俯仰 ${(tiltDelta ?? 0).toStringAsFixed(1)}°',
      );
    }
    return lines.join('\n');
  }

  String _formatBackendAiScanResultForHud(
    _AiScanRunResult scan,
    _AiScanFrame bestFrame, {
    required double finalPanOffset,
    required double finalTiltOffset,
    required String fallback,
  }) {
    final task = scan.task;
    final scoreLabel = task.resultScore?.toStringAsFixed(1) ?? '未返回';
    final lines = <String>[
      fallback,
      '已统一比较 ${scan.frames.length}/${scan.candidates.length} 个角度。',
      '最佳候选：水平 ${bestFrame.candidate.panOffset.toStringAsFixed(1)}°，俯仰 ${bestFrame.candidate.tiltOffset.toStringAsFixed(1)}°，分数 $scoreLabel。',
      '最终机位：水平 ${finalPanOffset.toStringAsFixed(1)}°，俯仰 ${finalTiltOffset.toStringAsFixed(1)}°。',
    ];
    final bestGalleryPath = scan.bestGalleryPath;
    if (bestGalleryPath != null && bestGalleryPath.isNotEmpty) {
      lines.add('最佳照片已保存到手机相册。');
    } else if (scan.bestGalleryError != null) {
      lines.add('最佳照片保存到相册失败：${scan.bestGalleryError}');
    }
    final summary = task.resultSummary?.trim();
    if (summary != null && summary.isNotEmpty) {
      lines.add(summary);
    }
    return lines.join('\n');
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

  OverlayScene? _selectedTemplateOverlayScene() {
    final deviceTemplate = _selectedDeviceTemplateForOverlay();
    if (deviceTemplate != null) {
      final templateData = Map<String, dynamic>.from(
        deviceTemplate.templateData,
      );
      if (!templateData.containsKey('bbox_norm') &&
          deviceTemplate.bboxNorm.length == 4) {
        templateData['bbox_norm'] = deviceTemplate.bboxNorm;
      }
      if (templateData.isNotEmpty) {
        return OverlayScene.fromTemplateData(templateData);
      }
    }

    final template = _selectedTemplate;
    if (template != null) {
      return OverlayScene.fromTemplateData(template.templateData);
    }
    return null;
  }

  DeviceTemplateSummary? _selectedDeviceTemplateForOverlay() {
    final selected = _selectedDeviceTemplate;
    if (selected != null) {
      return selected;
    }

    final selectedId = _status?.selectedTemplateId;
    if (selectedId != null) {
      for (final template in _deviceTemplates) {
        if (template.id == selectedId) {
          return template;
        }
      }
    }

    for (final template in _deviceTemplates) {
      if (template.selected) {
        return template;
      }
    }
    return null;
  }

  NormalizedRect? _normalizedRectFromBox(List<double>? box) {
    if (box == null || box.length != 4) {
      return null;
    }
    final rect = NormalizedRect(
      left: _clampUnit(box[0]),
      top: _clampUnit(box[1]),
      width: _clampUnit(box[2]),
      height: _clampUnit(box[3]),
    );
    if (rect.width <= 0 || rect.height <= 0) {
      return null;
    }
    return rect;
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

  void _setLastAiResult({
    required String title,
    required String body,
    String? kind,
    bool expand = true,
  }) {
    final normalizedBody = body.trim();
    if (normalizedBody.isEmpty) {
      return;
    }
    _lastAiResultTitle = title;
    _lastAiResultBody = normalizedBody;
    _preferredAiResultKind = kind;
    _lastAiResultAt = DateTime.now();
    _isHudAiResultExpanded = expand;
  }

  _AiResultText? _latestAiResultText() {
    final aiStatus = _status?.aiStatus ?? const DeviceAiStatusSummary();
    final backgroundResult = aiStatus.lastBackgroundLockResult;
    final angleResult = aiStatus.lastAngleSearchResult;
    final latestCapture = _status?.latestCapture;

    if (_preferredAiResultKind == 'capture') {
      final captureResult = _latestCaptureAiResult(latestCapture);
      if (captureResult != null) {
        return captureResult;
      }
    }

    if (_preferredAiResultKind == 'angle' && angleResult != null) {
      return _AiResultText(
        title: 'AI 对话框',
        body: _formatAngleSearchResult(angleResult),
      );
    }

    if (_preferredAiResultKind == 'background' && backgroundResult != null) {
      return _AiResultText(
        title: 'AI 对话框',
        body: _formatBackgroundLockResult(backgroundResult),
      );
    }

    if (_lastAiResultTitle != null && _lastAiResultBody != null) {
      final timeLabel = _lastAiResultAt == null
          ? null
          : '更新时间：${_formatClock(_lastAiResultAt!)}';
      return _AiResultText(
        title: _lastAiResultTitle!,
        body: [_lastAiResultBody!, ?timeLabel].join('\n'),
      );
    }

    if (backgroundResult != null) {
      return _AiResultText(
        title: 'AI 对话框',
        body: _formatBackgroundLockResult(backgroundResult),
      );
    }

    if (angleResult != null) {
      return _AiResultText(
        title: 'AI 对话框',
        body: _formatAngleSearchResult(angleResult),
      );
    }

    final captureResult = _latestCaptureAiResult(latestCapture);
    if (captureResult != null) {
      return captureResult;
    }

    return null;
  }

  _AiResultText? _latestCaptureAiResult(
    DeviceLatestCaptureSummary? latestCapture,
  ) {
    if (latestCapture?.analysisError != null) {
      return _AiResultText(
        title: 'AI 对话框',
        body: latestCapture!.analysisError!,
      );
    }
    if (latestCapture?.analysis != null) {
      return _AiResultText(
        title: 'AI 对话框',
        body: _formatCaptureAnalysis(
          latestCapture!.analysis!,
          capturePath: latestCapture.path,
        ),
      );
    }
    return null;
  }

  bool _usesPhoneCameraDeviceLink(DeviceStatusSummary? status) {
    return status?.previewSource == 'phone_camera' ||
        status?.streamUrl?.trim() == _mobilePushStreamUrl ||
        _streamUrlController.text.trim() == _mobilePushStreamUrl ||
        _isMobilePushEnabled;
  }

  Future<void> _syncDeviceCaptureFiles() async {
    if (_usesPhoneCameraDeviceLink(_status)) {
      return;
    }
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

  Future<CaptureRecord?> _tryRecordDeviceCaptureInHistory(
    String rawPath,
  ) async {
    final path = rawPath.trim();
    if (path.isEmpty) {
      return null;
    }
    try {
      final capture = await _recordDeviceCaptureInHistory(path);
      if (!mounted) {
        return null;
      }
      setState(() {
        _deviceHistoryCaptureIds[path] = capture.id;
        final index = _captureRecords.indexWhere((item) => item.path == path);
        if (index >= 0) {
          _captureRecords[index] = _captureRecords[index].copyWith(
            backendCaptureId: capture.id,
          );
        }
        _addActionRecord('capture', '设备抓拍已写入历史会话。');
      });
      return capture;
    } on ApiException catch (error) {
      if (!mounted) {
        return null;
      }
      setState(() {
        _errorMessage =
            'Device capture succeeded, but saving it to history failed: ${error.message}';
        _addActionRecord('error', _errorMessage!);
      });
      return null;
    } catch (_) {
      if (!mounted) {
        return null;
      }
      setState(() {
        _errorMessage =
            'Device capture succeeded, but saving it to history failed. Check the backend service and network.';
        _addActionRecord('error', _errorMessage!);
      });
      return null;
    }
  }

  Future<CaptureRecord> _recordDeviceCaptureInHistory(String path) async {
    final existingIndex = _captureRecords.indexWhere(
      (item) => item.path == path && item.backendCaptureId != null,
    );
    final existingCaptureId = existingIndex >= 0
        ? _captureRecords[existingIndex].backendCaptureId
        : _deviceHistoryCaptureIds[path];
    if (existingCaptureId != null) {
      final captures = await widget.mobileApiService.getHistoryCaptures(
        accessToken: widget.accessToken,
      );
      for (final capture in captures) {
        if (capture.id == existingCaptureId) {
          return capture;
        }
      }
    }

    final bytes = await _deviceApiService.downloadCaptureFile(
      baseUrl: _baseUrlController.text,
      path: path,
    );
    final rootDir = await getApplicationDocumentsDirectory();
    final uploadDir = Directory('${rootDir.path}/device_history_uploads');
    await uploadDir.create(recursive: true);
    final fileName = _deviceCaptureFileName(path);
    final localFile = File('${uploadDir.path}/$fileName');
    await localFile.writeAsBytes(bytes, flush: true);

    final historySession = await _ensureDeviceHistorySession();
    final uploadedFile = await widget.mobileApiService.uploadCaptureFile(
      accessToken: widget.accessToken,
      filePath: localFile.path,
    );
    return widget.mobileApiService.createCapture(
      accessToken: widget.accessToken,
      sessionId: historySession.id,
      fileUrl: uploadedFile.fileUrl,
      captureType: 'single',
      storageProvider: uploadedFile.storageProvider,
      metadata: <String, dynamic>{
        'media_type': 'photo',
        'local_album_saved': false,
        'duration_ms': null,
        'source': 'device_link',
        'entry': 'device_link_page',
        'device_capture_path': path,
        'device_capture_url': _deviceCaptureFileUrl(path),
        'device_base_url': _normalizedDeviceBaseUrl(_baseUrlController.text),
        'device_session_code':
            _status?.sessionCode ?? _sessionCodeController.text.trim(),
        'stream_url': _streamUrlController.text.trim(),
        'local_upload_path': localFile.path,
        'storage_path': uploadedFile.storagePath,
        'relative_path': uploadedFile.relativePath,
        'original_filename': uploadedFile.originalFilename,
        'content_type': uploadedFile.contentType,
        'auto_analyze_requested': _analyzeCaptureAfterShot,
        'selected_template_id': _selectedTemplate?.id,
        'selected_template_name': _selectedTemplate?.name,
      },
    );
  }

  Future<CaptureSessionSummary> _ensureDeviceHistorySession() async {
    final existing = _deviceHistorySession;
    if (existing != null) {
      return existing;
    }
    final session = await widget.mobileApiService.createCaptureSession(
      accessToken: widget.accessToken,
      templateId: _selectedTemplate?.id,
      mode: _deviceHistorySessionMode(),
      metadata: <String, dynamic>{
        'entry': 'device_link_page',
        'device_base_url': _normalizedDeviceBaseUrl(_baseUrlController.text),
        'device_session_code':
            _status?.sessionCode ?? _sessionCodeController.text.trim(),
        'stream_url': _streamUrlController.text.trim(),
        'mobile_platform': Platform.operatingSystem,
        'selected_template_name': _selectedTemplate?.name,
      },
    );
    _deviceHistorySession = session;
    return session;
  }

  String _deviceHistorySessionMode() {
    switch (_status?.mode ?? 'MANUAL') {
      case 'AUTO_TRACK':
        return 'gimbal_follow';
      case 'SMART_COMPOSE':
        return 'gimbal_template';
      case 'MANUAL':
      default:
        return 'gimbal_manual';
    }
  }

  void _queueAutoSaveDeviceCapturePath(String? rawPath) {
    final path = rawPath?.trim();
    if (path == null ||
        path.isEmpty ||
        _autoSavingDeviceCapturePaths.contains(path)) {
      return;
    }

    _DeviceCaptureRecord? record;
    for (final item in _captureRecords) {
      if (item.path == path) {
        record = item;
        break;
      }
    }
    if (record == null || record.localPath != null) {
      return;
    }

    _autoSavingDeviceCapturePaths.add(path);
    unawaited(
      _saveDeviceCaptureToPhone(record, automatic: true).whenComplete(() {
        _autoSavingDeviceCapturePaths.remove(path);
      }),
    );
  }

  Future<void> _saveDeviceCaptureToPhone(
    _DeviceCaptureRecord record, {
    bool automatic = false,
  }) async {
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
      final galleryPath = await _gallerySaveService.saveImageBytes(
        bytes: bytes,
        fileName: fileName,
      );

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
        _syncMessage = automatic
            ? '树莓派抓拍已自动保存到手机相册。'
            : galleryPath == null || galleryPath.isEmpty
            ? '已保存到手机：$fileName'
            : '已保存到手机相册：$fileName';
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

  Future<void> _refreshStatusSilently() async {
    final status = await _deviceApiService.getStatus(
      baseUrl: _baseUrlController.text,
    );
    if (!mounted) {
      return;
    }
    final latestCapturePath = status.latestCapture.path;
    setState(() {
      _status = status;
      _lastStatusUpdatedAt = DateTime.now();
      _rememberDeviceCapturePath(latestCapturePath, source: 'status');
      _selectedDeviceTemplate = null;
    });
    _queueAutoSaveDeviceCapturePath(latestCapturePath);
    _handleMobileCaptureRequest(status.mobileCaptureRequest);
    _syncPollingInterval(status);
    unawaited(_syncDeviceCaptureFiles());
    if (status.sessionOpened) {
      unawaited(_startPreviewStream());
      unawaited(_syncSensitivityToDevice());
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

  void _syncPollingInterval(DeviceStatusSummary? status) {
    final nextInterval = _resolvePollInterval(status);
    if (_pollInterval == nextInterval) {
      return;
    }
    _pollInterval = nextInterval;
    _restartPolling();
  }

  void _restartPolling() {
    _pollTimer?.cancel();
    if (!_autoRefreshEnabled) {
      return;
    }
    _pollInterval = _resolvePollInterval(_status);
    _pollTimer = Timer.periodic(_pollInterval, (_) async {
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

  static String _detailedSettingKey(String name) => 'detailed_settings.$name';

  Future<void> _loadPersistedConfig() async {
    final draft = await _preferenceStore.loadDraft(
      fallbackBaseUrl: _baseUrlController.text,
      fallbackStreamUrl: _streamUrlController.text,
      fallbackAutoRefreshEnabled: _autoRefreshEnabled,
      fallbackLandscapeControlsOnLeft: _landscapeControlsOnLeft,
      fallbackJoystickVisible: _isJoystickVisible,
      fallbackJoystickSensitivity: _sensitivity,
    );
    final detailedPrefs = await SharedPreferences.getInstance();
    if (!mounted) {
      return;
    }
    setState(() {
      _baseUrlController.text = draft.baseUrl;
      _streamUrlController.text = draft.streamUrl;
      _autoRefreshEnabled =
          detailedPrefs.getBool(_detailedSettingKey('device.auto_refresh')) ??
          draft.autoRefreshEnabled;
      _landscapeControlsOnLeft =
          detailedPrefs.getBool(_detailedSettingKey('device.landscape_left')) ??
          draft.landscapeControlsOnLeft;
      _isJoystickVisible =
          detailedPrefs.getBool(_detailedSettingKey('device.show_joystick')) ??
          draft.joystickVisible;
      _sensitivity =
          detailedPrefs.getDouble(_detailedSettingKey('device.sensitivity')) ??
          draft.joystickSensitivity;
      _analyzeCaptureAfterShot =
          detailedPrefs.getBool(
            _detailedSettingKey('gesture.analyze_after_capture'),
          ) ??
          _analyzeCaptureAfterShot;
      _aiPanScanRange =
          detailedPrefs.getDouble(_detailedSettingKey('ai.pan_scan_range')) ??
          _aiPanScanRange;
      _aiTiltScanRange =
          detailedPrefs.getDouble(_detailedSettingKey('ai.tilt_scan_range')) ??
          _aiTiltScanRange;
      _aiScanStepDegrees =
          detailedPrefs.getDouble(
            _detailedSettingKey('ai.scan_step_degrees'),
          ) ??
          _aiScanStepDegrees;
      _aiMaxCandidates =
          detailedPrefs
              .getDouble(_detailedSettingKey('ai.candidate_count'))
              ?.round() ??
          _aiMaxCandidates;
      _aiSettleSeconds =
          detailedPrefs.getDouble(_detailedSettingKey('ai.settle_seconds')) ??
          _aiSettleSeconds;
      _aiStartDelaySeconds =
          detailedPrefs.getDouble(
            _detailedSettingKey('ai.start_delay_seconds'),
          ) ??
          _aiStartDelaySeconds;
      _recentConnections = draft.recentConnections;
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
    await _preferenceStore.saveDraft(
      _DeviceLinkDraftConfig(
        baseUrl: _baseUrlController.text.trim(),
        streamUrl: _streamUrlController.text.trim(),
        autoRefreshEnabled: _autoRefreshEnabled,
        landscapeControlsOnLeft: _landscapeControlsOnLeft,
        joystickVisible: _isJoystickVisible,
        joystickSensitivity: _sensitivity,
        recentConnections: const <_DeviceConnectionPreset>[],
      ),
    );
  }

  Future<void> _rememberCurrentConnection() async {
    final preset = _DeviceConnectionPreset(
      baseUrl: _baseUrlController.text.trim(),
      streamUrl: _streamUrlController.text.trim(),
      sessionCode: _sessionCodeController.text.trim(),
      updatedAt: DateTime.now(),
    );
    final limited = await _preferenceStore.rememberConnection(
      preset,
      currentConnections: _recentConnections,
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
    await _preferenceStore.clearRecentConnections();
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
        final columns = constraints.maxWidth >= 680
            ? 4
            : constraints.maxWidth >= 360
            ? 2
            : 1;
        final buttonWidth =
            (constraints.maxWidth - (columns - 1) * 12) / columns;
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
              : 'WebSocket 推流中，已发送 $_mobilePushFrameCount 帧，最近 $lastFrame。')
        : '使用 GitHub 旧版 WebSocket/NV21 链路推送手机摄像头画面。';

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
                  label: Text(
                    _mobilePushSwitchTargetLabel(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
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
              Wrap(
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 10,
                runSpacing: 10,
                children: <Widget>[
                  _ManualMoveHoldButton(
                    enabled: canManualMove,
                    onStart: () => _startManualMoveRepeat('left'),
                    onStop: _stopManualMoveRepeat,
                    icon: const Icon(Icons.keyboard_arrow_left),
                    label: '左移',
                  ),
                  OutlinedButton.icon(
                    onPressed: _isBusy ? null : _home,
                    icon: const Icon(Icons.center_focus_strong_outlined),
                    label: const Text('回中'),
                  ),
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
        '当前还没有 AI 执行记录，可直接触发抓拍、自动找角度或背景锁定。',
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
            ],
          ),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, constraints) {
              final columnCount = constraints.maxWidth >= 360 ? 3 : 2;
              final cardWidth = math.max(
                112.0,
                (constraints.maxWidth - (columnCount - 1) * 10) / columnCount,
              );
              return Wrap(
                spacing: 10,
                runSpacing: 10,
                children: _templates
                    .map(
                      (template) => SizedBox(
                        width: cardWidth,
                        child: _TemplatePreviewCard(
                          name: template.name,
                          imageUrl: _templatePreviewImageUrl(template),
                          meta: template.templateType,
                          selected: _selectedTemplate?.id == template.id,
                          onDelete: template.isRecommendedDefault
                              ? null
                              : () => unawaited(_deleteTemplate(template)),
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
                    )
                    .toList(growable: false),
              );
            },
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
    final controller = _mobilePushCameraController;
    final Widget preview;

    if (controller != null && controller.value.isInitialized) {
      preview = _buildMobilePushLocalPreview(controller);
    } else if (_isStartingMobilePush) {
      preview = const _HudEmptyPreview(
        icon: Icons.mobile_screen_share_outlined,
        title: '正在启动手机画面',
        description: '设备联动会直接显示手机摄像头画面，树莓派只负责云台转动。',
      );
    } else if (!hasSession) {
      preview = const _HudEmptyPreview(
        title: '等待打开设备会话',
        description: '点击控制面板里的打开会话后，会自动启动手机画面和云台联动。',
      );
    } else if (_webRtcSession != null) {
      preview = _buildWebRtcPreview();
    } else {
      preview = const _HudEmptyPreview(
        icon: Icons.mobile_screen_share_outlined,
        title: '手机画面未启动',
        description: '请在设置里启动手机推流；主预览只使用手机摄像头画面。',
      );
    }

    return ColoredBox(
      color: Colors.black,
      child: SizedBox.expand(child: preview),
    );
  }

  bool _isMobilePushPreviewLandscape(CameraController controller) {
    final orientation =
        controller.value.previewPauseOrientation ??
        controller.value.lockedCaptureOrientation ??
        controller.value.deviceOrientation;
    return orientation == DeviceOrientation.landscapeLeft ||
        orientation == DeviceOrientation.landscapeRight;
  }

  double _mobilePushPreviewWidgetAspectRatio(CameraController controller) {
    return _isMobilePushPreviewLandscape(controller)
        ? controller.value.aspectRatio
        : 1 / controller.value.aspectRatio;
  }

  int _mobilePushPreviewQuarterTurns(CameraController controller) {
    final orientation =
        controller.value.previewPauseOrientation ??
        controller.value.lockedCaptureOrientation ??
        controller.value.deviceOrientation;
    switch (orientation) {
      case DeviceOrientation.portraitUp:
        return 0;
      case DeviceOrientation.landscapeRight:
        return 1;
      case DeviceOrientation.portraitDown:
        return 2;
      case DeviceOrientation.landscapeLeft:
        return 3;
    }
  }

  bool get _shouldMirrorMobileLiveOverlay =>
      _mobilePushLensDirection == CameraLensDirection.front;

  Widget _buildMobilePushLocalPreview(CameraController controller) {
    return ValueListenableBuilder<CameraValue>(
      valueListenable: controller,
      builder: (BuildContext context, CameraValue value, Widget? child) {
        final previewAspectRatio = _mobilePushPreviewWidgetAspectRatio(
          controller,
        );
        final previewWidth = previewAspectRatio >= 1
            ? 1600 * previewAspectRatio
            : 1600.0;
        final previewHeight = previewAspectRatio >= 1
            ? 1600.0
            : 1600 / previewAspectRatio;
        final recordingPreviewBytes = _isDeviceLinkRecordingPreviewPaused
            ? _deviceLinkRecordingPreviewBytes
            : null;
        Widget cameraPreview;
        if (recordingPreviewBytes != null) {
          cameraPreview = Image.memory(
            recordingPreviewBytes,
            fit: BoxFit.cover,
            gaplessPlayback: true,
            filterQuality: FilterQuality.low,
          );
          if (_mobilePushLensDirection == CameraLensDirection.front) {
            cameraPreview = Transform(
              alignment: Alignment.center,
              transform: Matrix4.diagonal3Values(-1.0, 1.0, 1.0),
              child: cameraPreview,
            );
          }
        } else {
          cameraPreview = controller.buildPreview();
        }
        if (recordingPreviewBytes == null &&
            !kIsWeb &&
            defaultTargetPlatform == TargetPlatform.android) {
          cameraPreview = RotatedBox(
            quarterTurns: _mobilePushPreviewQuarterTurns(controller),
            child: cameraPreview,
          );
        }
        final overlaySettings =
            _status?.overlayStatus ?? const DeviceOverlayStatusSummary();
        final overlay = _latestMobileVisionOverlay;
        final templateOverlay = _selectedTemplateOverlayScene();
        final aiLockBox = _normalizedRectFromBox(_status?.aiLockTargetBoxNorm);
        final hasOverlay =
            overlaySettings.enabled &&
            (overlay != null || templateOverlay != null || aiLockBox != null);

        return ClipRect(
          child: ColoredBox(
            color: Colors.black,
            child: SizedBox.expand(
              child: FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: previewWidth,
                  height: previewHeight,
                  child: Stack(
                    fit: StackFit.expand,
                    children: <Widget>[
                      cameraPreview,
                      if (hasOverlay)
                        CustomPaint(
                          painter: _MobileVisionOverlayPainter(
                            overlay: overlay,
                            templateScene: templateOverlay,
                            aiLockBox: aiLockBox,
                            settings: overlaySettings,
                            followMode: _status?.followMode ?? 'shoulders',
                            mirrorLiveOverlay: _shouldMirrorMobileLiveOverlay,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
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
              _mobilePushCameraController == null
                  ? Icons.image_outlined
                  : Icons.phone_android_outlined,
              size: 16,
              color: Colors.white.withValues(alpha: 0.86),
            ),
            const SizedBox(width: 8),
            Text(
              _mobilePushCameraController == null ? '等待手机画面' : '手机本地画面',
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
        icon: Icons.settings_outlined,
        label: '设置',
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
      final desiredPanelWidth = panel == _DeviceHudPanel.device ? 420.0 : 360.0;
      final availablePanelWidth =
          MediaQuery.sizeOf(context).width - sideInset - 104;
      final panelWidth = math.max(
        280.0,
        math.min(desiredPanelWidth, availablePanelWidth),
      );
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
      bottom: bottomPadding + 96,
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
      (label: '低', value: 0.5),
      (label: '中', value: 1.0),
      (label: '高', value: 1.6),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _HudPanelHeader(
          title: '控制',
          subtitle: _status?.sessionOpened == true
              ? '灵敏度同时影响手动控制、自动跟随和模板构图。'
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
                selected: (_sensitivity - item.value).abs() < 0.05,
                onTap: () => _setSensitivity(item.value),
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
        const SizedBox(height: 12),
        Text(
          '模板、画面辅助、连接和 AI 参数都在“设置”里。',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.62),
            height: 1.35,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  String _deviceTemplateStatusSummary() {
    final templateStatus = _status?.templateStatus;
    if (templateStatus == null) {
      return '未选择模板';
    }
    return '${templateStatus.templateName ?? _status?.selectedTemplateId ?? '未命名模板'} · ${templateStatus.ready ? 'ready' : 'waiting'}';
  }

  Widget _buildHudDetailedSettingsCard(
    BuildContext context, {
    bool showHeader = true,
  }) {
    final templateStatus = _status?.templateStatus;
    final templateSummary = _deviceTemplateStatusSummary();
    final pushSummary = _webRtcSession != null
        ? 'WebRTC 推流'
        : 'WebSocket $_mobilePushFrameCount 帧';
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (showHeader)
              _HudPanelHeader(
                title: '详细设置',
                subtitle: '模板、画面辅助、手势、连接和 AI 参数集中在这里。',
              )
            else ...<Widget>[
              Text(
                '详细设置',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                '模板、画面辅助、手势、连接和 AI 参数都收在这里。',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.62),
                  height: 1.35,
                ),
              ),
            ],
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                _HudStatusBadge(
                  label: templateStatus == null
                      ? '模板 未选'
                      : '模板 ${templateStatus.ready ? 'ready' : 'waiting'}',
                  active: templateStatus?.ready == true,
                ),
                _HudStatusBadge(
                  label: '会话 ${_status?.sessionOpened == true ? '已开' : '未开'}',
                  active: _status?.sessionOpened == true,
                ),
                _HudStatusBadge(
                  label: pushSummary,
                  active: _isMobilePushEnabled,
                ),
              ],
            ),
            const SizedBox(height: 6),
            _buildHudDetailedSection(
              context,
              icon: Icons.view_in_ar_outlined,
              title: '模板与构图',
              subtitle: templateSummary,
              initiallyExpanded: true,
              children: <Widget>[_buildHudTemplateSettingsSection(context)],
            ),
            _buildHudDetailedSection(
              context,
              icon: Icons.layers_outlined,
              title: '画面辅助',
              subtitle: '模板框、模板线、人体框、骨架线、中心点显示。',
              children: <Widget>[
                _buildHudOverlayOptions(context, showTitle: false),
              ],
            ),
            _buildHudDetailedSection(
              context,
              icon: Icons.pan_tool_alt_outlined,
              title: '手势抓拍',
              subtitle: '张手握拳、OK 手势和拍后设备 AI 分析。',
              children: <Widget>[_buildHudGestureOptions(context)],
            ),
            _buildHudDetailedSection(
              context,
              icon: Icons.settings_input_antenna_outlined,
              title: '连接与设备',
              subtitle: '地址、会话码、推流、诊断和横屏控制习惯。',
              children: <Widget>[_buildHudConnectionSettingsSection(context)],
            ),
            _buildHudDetailedSection(
              context,
              icon: Icons.tune_outlined,
              title: 'AI 高级参数',
              subtitle: '自定义找角度和背景锁定的扫描范围、步进与等待。',
              children: <Widget>[_buildHudAiAdvancedSettingsSection(context)],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHudDetailedSection(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required List<Widget> children,
    bool initiallyExpanded = false,
  }) {
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.fromLTRB(0, 6, 0, 10),
        initiallyExpanded: initiallyExpanded,
        leading: Icon(icon, color: const Color(0xFFBDF6EF), size: 20),
        title: Text(
          title,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w800,
          ),
        ),
        subtitle: Text(
          subtitle,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: Colors.white.withValues(alpha: 0.62)),
        ),
        iconColor: Colors.white.withValues(alpha: 0.76),
        collapsedIconColor: Colors.white.withValues(alpha: 0.52),
        children: children,
      ),
    );
  }

  Widget _buildHudTemplateSettingsSection(BuildContext context) {
    final templateStatus = _status?.templateStatus;
    final templateSummary = _deviceTemplateStatusSummary();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
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
            '构图分数${ScoreFormatter.formatHundred(templateStatus!.composeScore) ?? '-'}',
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
              label: _isCreatingDemoTemplate ? '新增中' : '新增模板',
              onTap: _isBusy || _isCreatingDemoTemplate
                  ? null
                  : _createTemplate,
            ),
            _HudActionChip(
              icon: Icons.refresh_outlined,
              label: _isLoadingTemplates ? '刷新中' : '刷新模板',
              onTap: _isBusy || _isLoadingTemplates ? null : _loadTemplates,
            ),
            _HudActionChip(
              icon: Icons.check_circle_outline,
              label: _selectedTemplate == null
                  ? '选择模板'
                  : '使用 ${_selectedTemplate!.name}',
              onTap: _isBusy || _selectedTemplate == null
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
              label: _isDeletingTemplate ? '删除中' : '删除模板',
              onTap: _isBusy || _isDeletingTemplate || _selectedTemplate == null
                  ? null
                  : _deleteSelectedTemplate,
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (_isLoadingTemplates)
          LinearProgressIndicator(
            minHeight: 3,
            color: const Color(0xFF9BE7DD),
            backgroundColor: Colors.white.withValues(alpha: 0.12),
          )
        else if (_templates.isEmpty)
          Text(
            '还没有模板，可以先新增一个人物模板。',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.66)),
          )
        else
          LayoutBuilder(
            builder: (context, constraints) {
              final columnCount = constraints.maxWidth >= 360 ? 3 : 2;
              final cardWidth = math.max(
                112.0,
                (constraints.maxWidth - (columnCount - 1) * 8) / columnCount,
              );
              return Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _templates
                    .map(
                      (template) => SizedBox(
                        width: cardWidth,
                        child: _TemplatePreviewCard(
                          name: template.name,
                          imageUrl: _templatePreviewImageUrl(template),
                          meta: template.templateType,
                          selected: _selectedTemplate?.id == template.id,
                          dark: true,
                          onDelete: template.isRecommendedDefault
                              ? null
                              : () => unawaited(_deleteTemplate(template)),
                          onTap: _isBusy
                              ? null
                              : () {
                                  setState(() {
                                    _selectedTemplate = template;
                                    _selectedDeviceTemplate = null;
                                    _syncMessage = '已选择模板：${template.name}';
                                  });
                                },
                        ),
                      ),
                    )
                    .toList(growable: false),
              );
            },
          ),
      ],
    );
  }

  Widget _buildHudConnectionSettingsSection(BuildContext context) {
    final lastFrame = _lastMobilePushFrameAt == null
        ? '-'
        : _formatClock(_lastMobilePushFrameAt!);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            _HudStatusBadge(
              label: '设备 ${_status?.deviceStatus ?? _health?.status ?? '未知'}',
              active:
                  _status?.deviceStatus == 'online' ||
                  _health?.status == 'online',
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
              icon: Icons.radar_outlined,
              label: '刷新',
              onTap: _isBusy ? null : _fetchStatus,
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
                      _isHandlingMobilePushOrientationChange ||
                      _isDeviceLinkRecordingVideo ||
                      _isFinalizingDeviceLinkVideo
                  ? null
                  : () => unawaited(_switchMobilePushCamera()),
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
        Align(
          alignment: Alignment.centerLeft,
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            children: <Widget>[
              _HudActionChip(
                icon: Icons.fact_check_outlined,
                label: '诊断',
                onTap: _isBusy ? null : _runConnectionDiagnostics,
              ),
              _HudActionChip(
                icon: Icons.video_settings_outlined,
                label: '设备预览源',
                onTap: _isBusy ? null : _restartDeviceStream,
              ),
              _HudActionChip(
                icon: Icons.swap_horiz_outlined,
                label: _landscapeControlsOnLeft ? '横屏左手' : '横屏右手',
                onTap: () =>
                    _setLandscapeControlsSide(!_landscapeControlsOnLeft),
              ),
            ],
          ),
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

  Widget _buildHudAiAdvancedSettingsSection(BuildContext context) {
    final aiStatus = _status?.aiStatus ?? const DeviceAiStatusSummary();
    final isRunning = aiStatus.hasRunningTask;
    final defaultConfig = _defaultAiScanConfig();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          '普通 AI 按钮会直接使用默认参数；这里可以手动调扫描范围、步进、候选数量和等待时间。',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.66),
            height: 1.35,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '默认：水平±${defaultConfig.panRange}°，垂直±${defaultConfig.tiltRange}°，步进 ${defaultConfig.panStep}/${defaultConfig.tiltStep}°。',
          style: TextStyle(color: Colors.white.withValues(alpha: 0.58)),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: <Widget>[
            _HudActionChip(
              icon: Icons.travel_explore_outlined,
              label: isRunning ? '运行中' : '找角度参数',
              onTap: _isBusy || isRunning ? null : _startAngleSearchAdvanced,
            ),
            _HudActionChip(
              icon: Icons.center_focus_weak_outlined,
              label: isRunning ? '运行中' : '背景锁定参数',
              onTap: _isBusy || isRunning ? null : _startBackgroundLockAdvanced,
            ),
            _HudActionChip(
              icon: Icons.lock_open_outlined,
              label: '解除锁定',
              onTap: _isBusy || !aiStatus.lockEnabled
                  ? null
                  : _unlockBackgroundLock,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildHudAiPanel(BuildContext context) {
    final aiStatus = _status?.aiStatus ?? const DeviceAiStatusSummary();
    final isRunning = aiStatus.hasRunningTask;
    final cameraReady =
        _mobilePushCameraController?.value.isInitialized == true;
    final canTakePhoto =
        !_isBusy &&
        cameraReady &&
        !_isDeviceLinkCapturingPhoto &&
        !_isAnalyzingDeviceLinkCapture &&
        !_isDeviceLinkRecordingVideo &&
        !_isFinalizingDeviceLinkVideo;
    final canToggleVideo =
        cameraReady &&
        !_isDeviceLinkCapturingPhoto &&
        !_isFinalizingDeviceLinkVideo &&
        (!_isBusy || _isDeviceLinkRecordingVideo);
    final aiCountdown = aiStatus.countdown;
    final aiCountdownRemaining = aiCountdown.remainingSeconds;
    final aiCountdownLabel = aiCountdownRemaining == null
        ? null
        : math.max(1, aiCountdownRemaining.ceil());
    final isAiCountdownActive = aiCountdown.active && aiCountdownLabel != null;
    final aiCountdownMessage = switch (aiCountdown.task) {
      'background_lock' => 'AI 背景锁定倒计时中，准备开始扫描',
      'angle_search' => 'AI 自动找角度倒计时中，准备开始扫描',
      _ => 'AI 倒计时中，准备开始扫描',
    };
    final lastError =
        aiStatus.lastAngleSearchError ?? aiStatus.lastBackgroundLockError;
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
              label: _isDeviceLinkCapturingPhoto
                  ? '拍照中'
                  : _isAnalyzingDeviceLinkCapture
                  ? '分析中'
                  : '拍照',
              onTap: canTakePhoto ? _triggerCapture : null,
            ),
            _HudActionChip(
              icon: _isDeviceLinkRecordingVideo
                  ? Icons.stop_circle_outlined
                  : Icons.videocam_outlined,
              label: _isFinalizingDeviceLinkVideo
                  ? '保存中'
                  : _isDeviceLinkRecordingVideo
                  ? '停止录像'
                  : '开始录像',
              selected: _isDeviceLinkRecordingVideo,
              onTap: canToggleVideo
                  ? () => unawaited(_toggleDeviceLinkVideoRecording())
                  : null,
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
          ],
        ),
        if (_isDeviceLinkRecordingVideo) ...<Widget>[
          const SizedBox(height: 10),
          Text(
            '正在录像，停止后会直接保存到手机相册。',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.72),
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
        _buildHudAiResultButton(context),
        if (isAiCountdownActive) ...<Widget>[
          const SizedBox(height: 12),
          _TaskCountdownBanner(
            countdown: aiCountdownLabel,
            message: aiCountdownMessage,
          ),
        ],
        if (isRunning) ...<Widget>[
          const SizedBox(height: 12),
          LinearProgressIndicator(
            minHeight: 3,
            color: const Color(0xFF9BE7DD),
            backgroundColor: Colors.white.withValues(alpha: 0.12),
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

  Widget _buildHudAiResultButton(BuildContext context) {
    final result = _latestAiResultText();
    if (result == null) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(22),
                onTap: () {
                  setState(() {
                    _isHudAiResultExpanded = !_isHudAiResultExpanded;
                  });
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  child: Row(
                    children: <Widget>[
                      const Icon(
                        Icons.article_outlined,
                        color: Color(0xFF9BE7DD),
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          result.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      Icon(
                        _isHudAiResultExpanded
                            ? Icons.expand_less
                            : Icons.expand_more,
                        color: Colors.white.withValues(alpha: 0.72),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            AnimatedCrossFade(
              firstChild: const SizedBox.shrink(),
              secondChild: Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                child: Text(
                  result.body,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.76),
                    height: 1.45,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              crossFadeState: _isHudAiResultExpanded
                  ? CrossFadeState.showSecond
                  : CrossFadeState.showFirst,
              duration: const Duration(milliseconds: 180),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHudGestureOptions(BuildContext context) {
    final gesture =
        _status?.gestureStatus ?? const DeviceGestureStatusSummary();
    final latestCapture =
        _status?.latestCapture ?? const DeviceLatestCaptureSummary();
    final canUpdate = _status?.sessionOpened == true && !_isBusy;
    final recentCaptures = _captureRecords.take(4).toList(growable: false);
    final countdownRemaining = gesture.captureCountdownRemainingSeconds;
    final countdownLabel = countdownRemaining == null
        ? null
        : math.max(1, countdownRemaining.ceil());

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
              label: '拍后AI分析',
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
        if (gesture.captureCountdownActive &&
            countdownLabel != null) ...<Widget>[
          const SizedBox(height: 10),
          _GestureCountdownBanner(countdown: countdownLabel),
        ],
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
        if (recentCaptures.isNotEmpty) ...<Widget>[
          const SizedBox(height: 10),
          DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(22),
                    onTap: () {
                      setState(() {
                        _isHudCapturesExpanded = !_isHudCapturesExpanded;
                      });
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      child: Row(
                        children: <Widget>[
                          const Icon(
                            Icons.photo_library_outlined,
                            color: Color(0xFF9BE7DD),
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '设备照片',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          Text(
                            '${recentCaptures.length}',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.62),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Icon(
                            _isHudCapturesExpanded
                                ? Icons.expand_less
                                : Icons.expand_more,
                            color: Colors.white.withValues(alpha: 0.72),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                AnimatedCrossFade(
                  firstChild: const SizedBox.shrink(),
                  secondChild: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: <Widget>[
                            for (
                              var index = 0;
                              index < recentCaptures.length;
                              index++
                            )
                              SizedBox(
                                width: 118,
                                child: _HudGlass(
                                  compact: true,
                                  tint: const Color(0x6610181C),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: <Widget>[
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(10),
                                        child: AspectRatio(
                                          aspectRatio: 1,
                                          child: Image.network(
                                            _deviceCaptureFileUrl(
                                              recentCaptures[index].path,
                                            ),
                                            fit: BoxFit.cover,
                                            errorBuilder:
                                                (context, error, stackTrace) {
                                                  return Container(
                                                    color: Colors.white
                                                        .withValues(
                                                          alpha: 0.08,
                                                        ),
                                                    alignment: Alignment.center,
                                                    child: Icon(
                                                      Icons
                                                          .image_not_supported_outlined,
                                                      color: Colors.white
                                                          .withValues(
                                                            alpha: 0.52,
                                                          ),
                                                    ),
                                                  );
                                                },
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        _shortDeviceCaptureName(
                                          recentCaptures[index].path,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: Colors.white.withValues(
                                            alpha: 0.72,
                                          ),
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      _HudActionChip(
                                        icon:
                                            recentCaptures[index].localPath ==
                                                null
                                            ? Icons.download_outlined
                                            : Icons.check_circle_outline,
                                        label:
                                            recentCaptures[index].localPath ==
                                                null
                                            ? '保存'
                                            : '已保存',
                                        selected:
                                            recentCaptures[index].localPath !=
                                            null,
                                        onTap:
                                            _isSavingDeviceCapture ||
                                                recentCaptures[index]
                                                        .localPath !=
                                                    null
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
                          '树莓派手势抓拍会自动保存到手机相册，也可以在这里再次保存。',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.58),
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                  crossFadeState: _isHudCapturesExpanded
                      ? CrossFadeState.showSecond
                      : CrossFadeState.showFirst,
                  duration: const Duration(milliseconds: 180),
                ),
              ],
            ),
          ),
        ],
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

  Widget _buildGestureCaptureOverlay(
    BuildContext context, {
    required bool isLandscape,
  }) {
    final gesture =
        _status?.gestureStatus ?? const DeviceGestureStatusSummary();
    final remaining = gesture.captureCountdownRemainingSeconds;
    final isCountingDown = gesture.captureCountdownActive && remaining != null;
    final isCapturing = gesture.captureInProgress;
    if (!isCountingDown && !isCapturing) {
      return const SizedBox.shrink();
    }

    final countdown = remaining == null ? null : math.max(1, remaining.ceil());
    final event = gesture.captureCountdownEvent;
    final title = isCapturing
        ? '正在抓拍'
        : event == 'force_capture'
        ? 'OK 手势已识别'
        : '手势已识别';
    final subtitle = isCapturing ? '正在保存本次照片，期间不会响应新的手势。' : '倒计时期间不会重复计数。';

    return Positioned.fill(
      child: IgnorePointer(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: isLandscape ? 360 : 300,
              minWidth: isLandscape ? 280 : 240,
            ),
            child: _HudGlass(
              tint: const Color(0xD910181C),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 160),
                    child: Container(
                      key: ValueKey<String>(
                        isCapturing ? 'capturing' : 'countdown_$countdown',
                      ),
                      width: isLandscape ? 88 : 104,
                      height: isLandscape ? 88 : 104,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isCapturing
                            ? const Color(0xFF2D8C7A)
                            : const Color(0xFFBDF6EF),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.74),
                          width: 2,
                        ),
                      ),
                      child: isCapturing
                          ? const SizedBox(
                              width: 32,
                              height: 32,
                              child: CircularProgressIndicator(
                                strokeWidth: 3,
                                color: Colors.white,
                              ),
                            )
                          : Text(
                              '${countdown ?? 1}',
                              style: TextStyle(
                                color: const Color(0xFF0D3F43),
                                fontSize: isLandscape ? 42 : 52,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: isLandscape ? 20 : 22,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    subtitle,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.74),
                      fontWeight: FontWeight.w700,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
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
                  _buildGestureCaptureOverlay(
                    context,
                    isLandscape: isLandscape,
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

enum _SmartComposeTemplateAction { select, create, delete }

class _SmartComposeTemplateChoice {
  const _SmartComposeTemplateChoice.select(this.mobileTemplate)
    : action = _SmartComposeTemplateAction.select;

  const _SmartComposeTemplateChoice.delete(this.mobileTemplate)
    : action = _SmartComposeTemplateAction.delete;

  const _SmartComposeTemplateChoice.create()
    : action = _SmartComposeTemplateAction.create,
      mobileTemplate = null;

  final _SmartComposeTemplateAction action;
  final TemplateSummary? mobileTemplate;
}

class _AiScanCandidate {
  const _AiScanCandidate({
    required this.index,
    required this.panOffset,
    required this.tiltOffset,
  });

  final int index;
  final double panOffset;
  final double tiltOffset;

  _AiScanCandidate copyWith({int? index}) {
    return _AiScanCandidate(
      index: index ?? this.index,
      panOffset: panOffset,
      tiltOffset: tiltOffset,
    );
  }
}

class _AiScanFrame {
  const _AiScanFrame({
    required this.candidate,
    required this.path,
    this.metadata = const <String, dynamic>{},
  });

  final _AiScanCandidate candidate;
  final String path;
  final Map<String, dynamic> metadata;

  Map<String, dynamic> toCandidateJson() {
    return <String, dynamic>{
      'candidate_index': candidate.index,
      'pan_offset': candidate.panOffset,
      'tilt_offset': candidate.tiltOffset,
      ...metadata,
    };
  }
}

class _AiScanRunResult {
  const _AiScanRunResult({
    required this.candidates,
    required this.frames,
    required this.task,
    required this.lastCandidate,
    this.bestGalleryPath,
    this.bestGalleryError,
  });

  final List<_AiScanCandidate> candidates;
  final List<_AiScanFrame> frames;
  final AiTaskSummary task;
  final _AiScanCandidate lastCandidate;
  final String? bestGalleryPath;
  final String? bestGalleryError;
}

class _DeviceLinkPhotoCaptureResult {
  const _DeviceLinkPhotoCaptureResult({
    required this.imagePath,
    this.galleryPath,
  });

  final String imagePath;
  final String? galleryPath;
}

class _MobilePosePoint {
  const _MobilePosePoint({required this.point, required this.confidence});

  final NormalizedPoint point;
  final double confidence;
}

class _MobileTrackTarget {
  const _MobileTrackTarget({
    required this.targetType,
    required this.point,
    required this.desiredPoint,
    required this.confidence,
    required this.frameSize,
  });

  final String targetType;
  final NormalizedPoint point;
  final NormalizedPoint desiredPoint;
  final double confidence;
  final Size frameSize;
}

class _MobileVisionSegment {
  const _MobileVisionSegment({required this.start, required this.end});

  final NormalizedPoint start;
  final NormalizedPoint end;
}

class _MobileVisionOverlay {
  const _MobileVisionOverlay({
    required this.bodyBox,
    required this.skeleton,
    required this.anchor,
    required this.targetType,
    required this.shoulderCenter,
    required this.faceCenter,
  });

  final NormalizedRect? bodyBox;
  final List<_MobileVisionSegment> skeleton;
  final NormalizedPoint? anchor;
  final String targetType;
  final NormalizedPoint? shoulderCenter;
  final NormalizedPoint? faceCenter;
}

class _MobileVisionOverlayPainter extends CustomPainter {
  const _MobileVisionOverlayPainter({
    required this.overlay,
    required this.templateScene,
    required this.aiLockBox,
    required this.settings,
    required this.followMode,
    required this.mirrorLiveOverlay,
  });

  final _MobileVisionOverlay? overlay;
  final OverlayScene? templateScene;
  final NormalizedRect? aiLockBox;
  final DeviceOverlayStatusSummary settings;
  final String followMode;
  final bool mirrorLiveOverlay;

  @override
  void paint(Canvas canvas, Size size) {
    final templateTransform = PreviewTransform(viewportSize: size);
    final liveTransform = PreviewTransform(
      viewportSize: size,
      mirrorX: mirrorLiveOverlay,
    );
    _drawTemplateOverlay(canvas, size, templateTransform);
    _drawLiveOverlay(canvas, size, liveTransform);
    _drawAiLockBox(canvas, size, liveTransform);
  }

  void _drawTemplateOverlay(
    Canvas canvas,
    Size size,
    PreviewTransform transform,
  ) {
    final scene = templateScene;
    if (scene == null) {
      return;
    }

    final templatePaint = Paint()
      ..color = const Color(0xFFFFB84D)
      ..strokeWidth = math.max(2.0, size.shortestSide * 0.003)
      ..strokeCap = StrokeCap.round;
    final pointPaint = Paint()
      ..color = const Color(0xFFFFF2C2)
      ..style = PaintingStyle.fill;

    if (settings.showTemplateSkeleton) {
      for (final segment in scene.templateSegments) {
        final start = transform.pointToViewport(segment.start);
        final end = transform.pointToViewport(segment.end);
        canvas.drawLine(start, end, templatePaint);
        canvas.drawCircle(start, 3.0, pointPaint);
        canvas.drawCircle(end, 3.0, pointPaint);
      }
    }

    if (settings.showTemplateBbox && scene.hasTemplateBox) {
      final rect = transform.rectToViewport(scene.templateBox);
      final boxPaint = Paint()
        ..color = const Color(0xFFFFB84D)
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(2.0, size.shortestSide * 0.0035);
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(8)),
        boxPaint,
      );
    }

    if (settings.showTemplateBbox && scene.hasTemplateHeadBox) {
      final rect = transform.rectToViewport(scene.templateHeadBox);
      final headPaint = Paint()
        ..color = const Color(0xFFFFD27A)
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.5, size.shortestSide * 0.0024);
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(6)),
        headPaint,
      );
    }

    if (settings.showAiLockBox) {
      final target = _selectedTemplateCenter(scene);
      if (target != null) {
        _drawCenterMarker(
          canvas,
          transform.pointToViewport(target),
          size,
          const Color(0xFFFFF2C2),
          radius: 8,
        );
      }
    }
  }

  void _drawLiveOverlay(Canvas canvas, Size size, PreviewTransform transform) {
    final liveOverlay = overlay;
    if (liveOverlay == null) {
      return;
    }

    if (settings.showLiveBodySkeleton) {
      final skeletonPaint = Paint()
        ..color = const Color(0xFF7CF7E9)
        ..strokeWidth = math.max(2.0, size.shortestSide * 0.003)
        ..strokeCap = StrokeCap.round;
      final jointPaint = Paint()
        ..color = const Color(0xFFE8FFF9)
        ..style = PaintingStyle.fill;
      for (final segment in liveOverlay.skeleton) {
        final start = transform.pointToViewport(segment.start);
        final end = transform.pointToViewport(segment.end);
        canvas.drawLine(start, end, skeletonPaint);
        canvas.drawCircle(start, 3.2, jointPaint);
        canvas.drawCircle(end, 3.2, jointPaint);
      }
    }

    if (settings.showLivePersonBbox && liveOverlay.bodyBox != null) {
      final rect = transform.rectToViewport(liveOverlay.bodyBox!);
      final boxPaint = Paint()
        ..color = const Color(0xFFEFD067)
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(2.0, size.shortestSide * 0.0035);
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(8)),
        boxPaint,
      );
    }

    if (settings.showAiLockBox) {
      final anchor = _selectedLiveCenter(liveOverlay);
      if (anchor != null) {
        _drawCenterMarker(
          canvas,
          transform.pointToViewport(anchor),
          size,
          const Color(0xFFFFF4A8),
          radius: 9,
        );
      }
    }
  }

  void _drawAiLockBox(Canvas canvas, Size size, PreviewTransform transform) {
    final box = aiLockBox;
    if (!settings.showAiLockBox || box == null) {
      return;
    }
    final rect = transform.rectToViewport(box);
    final boxPaint = Paint()
      ..color = const Color(0xFF5BE7FF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(2.2, size.shortestSide * 0.0038);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(10)),
      boxPaint,
    );
    _drawCenterMarker(
      canvas,
      rect.center,
      size,
      const Color(0xFFB8F7FF),
      radius: 8,
    );
  }

  NormalizedPoint? _selectedTemplateCenter(OverlayScene scene) {
    final mode = followMode.toLowerCase();
    if (mode == 'face' || mode == 'face_center') {
      return scene.templateFaceCenter ??
          scene.templateShoulderCenter ??
          _templateBoxCenter(scene);
    }
    return scene.templateShoulderCenter ??
        scene.templateFaceCenter ??
        _templateBoxCenter(scene);
  }

  NormalizedPoint? _selectedLiveCenter(_MobileVisionOverlay overlay) {
    final mode = followMode.toLowerCase();
    if (mode == 'face' || mode == 'face_center') {
      return overlay.faceCenter ?? overlay.anchor ?? overlay.shoulderCenter;
    }
    return overlay.shoulderCenter ?? overlay.anchor ?? overlay.faceCenter;
  }

  NormalizedPoint? _templateBoxCenter(OverlayScene scene) {
    if (!scene.hasTemplateBox) {
      return null;
    }
    final box = scene.templateBox;
    return NormalizedPoint(
      box.left + box.width * 0.5,
      box.top + box.height * 0.5,
    );
  }

  void _drawCenterMarker(
    Canvas canvas,
    Offset center,
    Size size,
    Color color, {
    required double radius,
  }) {
    final markerPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(2.0, size.shortestSide * 0.003);
    final dotPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius, markerPaint);
    canvas.drawCircle(center, math.max(2.2, radius * 0.28), dotPaint);
    canvas.drawLine(
      center.translate(-radius - 5, 0),
      center.translate(radius + 5, 0),
      markerPaint,
    );
    canvas.drawLine(
      center.translate(0, -radius - 5),
      center.translate(0, radius + 5),
      markerPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _MobileVisionOverlayPainter oldDelegate) {
    return oldDelegate.overlay != overlay ||
        oldDelegate.templateScene != templateScene ||
        oldDelegate.aiLockBox != aiLockBox ||
        oldDelegate.settings != settings ||
        oldDelegate.followMode != followMode ||
        oldDelegate.mirrorLiveOverlay != mirrorLiveOverlay;
  }
}
