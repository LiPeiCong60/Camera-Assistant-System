import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

import '../../models/ai_task_summary.dart';
import '../../models/capture_record.dart';
import '../../models/capture_session_summary.dart';
import '../../models/device_link_result.dart';
import '../../models/normalized_geometry.dart';
import '../../models/template_summary.dart';
import '../../services/api_client.dart';
import '../../services/local_image_resolver.dart';
import '../../services/media_pipe_pose_detector_service.dart';
import '../../services/mobile_api_service.dart';
import '../device_link/device_link_page.dart';
import '../overlay/camera_overlay_painter.dart';
import '../overlay/overlay_scene.dart';
import '../template/template_photo_dialog.dart';

class CameraCapturePage extends StatefulWidget {
  const CameraCapturePage({
    super.key,
    required this.apiService,
    required this.accessToken,
  });

  final MobileApiService apiService;
  final String accessToken;

  @override
  State<CameraCapturePage> createState() => _CameraCapturePageState();
}

enum _CameraShootMode { normal, templateGuided, aiBurst, background }

class _CameraCapturePageState extends State<CameraCapturePage> {
  static const Map<DeviceOrientation, int> _cameraOrientations =
      <DeviceOrientation, int>{
        DeviceOrientation.portraitUp: 0,
        DeviceOrientation.landscapeLeft: 90,
        DeviceOrientation.portraitDown: 180,
        DeviceOrientation.landscapeRight: 270,
      };
  static const int _poseFrameIntervalMs = 90;
  static const int _maxPoseMissesBeforeClear = 4;
  static const double _liveBoxSmoothing = 0.22;
  static const double _livePointSmoothing = 0.28;

  List<CameraDescription> _cameras = const <CameraDescription>[];
  List<TemplateSummary> _templates = const <TemplateSummary>[];
  CameraController? _controller;
  bool _isPreparing = true;
  bool _isCapturing = false;
  bool _isSubmitting = false;
  bool _isLoadingTemplates = false;
  bool _isCreatingDemoTemplate = false;
  bool _isDeletingTemplate = false;
  String? _errorMessage;
  String? _syncMessage;
  XFile? _lastCapture;
  CaptureSessionSummary? _captureSession;
  CaptureRecord? _lastUploadedCapture;
  AiTaskSummary? _lastAiTask;
  DeviceLinkResult? _lastDeviceLinkResult;
  TemplateSummary? _selectedTemplate;
  OverlayScene? _templateOverlayScene;
  OverlayScene? _analysisOverlayScene;
  OverlayScene? _liveOverlayScene;
  OverlayScene _overlayScene = OverlayScene.empty();
  _CameraShootMode _shootMode = _CameraShootMode.normal;
  int _selectedCameraIndex = 0;
  bool _mirrorPreview = true;
  bool _isBannerVisible = false;
  bool _isShootModePickerExpanded = false;
  bool _isImageStreamActive = false;
  bool _isProcessingPoseFrame = false;
  bool _isHandlingOrientationChange = false;
  int _lastPoseFrameAtMs = 0;
  int _consecutivePoseMisses = 0;
  String _livePoseBackendLabel = '等待检测';
  Timer? _bannerTimer;
  final List<XFile> _pendingBurstCaptures = <XFile>[];
  OverlaySettings _overlaySettings = const OverlaySettings();
  Orientation? _lastScreenOrientation;
  late final PoseDetector _poseDetector = PoseDetector(
    options: PoseDetectorOptions(mode: PoseDetectionMode.stream),
  );
  final MediaPipePoseDetectorService _mediaPipePoseDetector =
      MediaPipePoseDetectorService();

  @override
  void initState() {
    super.initState();
    unawaited(_applyCameraPageOrientations());
    _setupCamera();
    _loadTemplates();
  }

  @override
  void dispose() {
    _bannerTimer?.cancel();
    unawaited(_restoreAppOrientations());
    _stopLivePoseDetection();
    unawaited(_mediaPipePoseDetector.close());
    _poseDetector.close();
    _controller?.dispose();
    super.dispose();
  }

  CameraDescription? get _activeCamera =>
      _cameras.isEmpty ? null : _cameras[_selectedCameraIndex];

  bool get _shouldMirrorPreview => _mirrorPreview;

  bool get _shouldMirrorDynamicOverlays {
    final isFrontCamera =
        _activeCamera?.lensDirection == CameraLensDirection.front;
    return isFrontCamera ? !_shouldMirrorPreview : _shouldMirrorPreview;
  }

  bool _isPreviewLandscape(CameraController controller) {
    final orientation = controller.value.isRecordingVideo
        ? controller.value.recordingOrientation
        : (controller.value.previewPauseOrientation ??
              controller.value.lockedCaptureOrientation ??
              controller.value.deviceOrientation);
    return orientation == DeviceOrientation.landscapeLeft ||
        orientation == DeviceOrientation.landscapeRight;
  }

  double _previewWidgetAspectRatio(CameraController controller) {
    return _isPreviewLandscape(controller)
        ? controller.value.aspectRatio
        : 1 / controller.value.aspectRatio;
  }

  DeviceOrientation _applicablePreviewOrientation(CameraController controller) {
    return controller.value.isRecordingVideo
        ? controller.value.recordingOrientation!
        : (controller.value.previewPauseOrientation ??
              controller.value.lockedCaptureOrientation ??
              controller.value.deviceOrientation);
  }

  int _previewQuarterTurns(CameraController controller) {
    switch (_applicablePreviewOrientation(controller)) {
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

  Widget _buildPlatformPreview(CameraController controller) {
    return ValueListenableBuilder<CameraValue>(
      valueListenable: controller,
      builder: (BuildContext context, CameraValue value, Widget? child) {
        Widget preview = controller.buildPreview();
        if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
          preview = RotatedBox(
            quarterTurns: _previewQuarterTurns(controller),
            child: preview,
          );
        }
        return preview;
      },
    );
  }

  Widget _buildCameraOverlay() {
    return IgnorePointer(
      child: CustomPaint(
        painter: CameraOverlayPainter(
          scene: _overlayScene,
          settings: _overlaySettings,
          mirrorDynamicOverlays: _shouldMirrorDynamicOverlays,
        ),
      ),
    );
  }

  bool get _hasPendingBurstCaptures => _pendingBurstCaptures.isNotEmpty;

  bool get _canAnalyzeCurrentSelection {
    if (_shootMode == _CameraShootMode.aiBurst) {
      return _pendingBurstCaptures.length >= 2;
    }
    return _lastCapture != null;
  }

  String get _shootModeLabel => _labelForShootMode(_shootMode);

  void _showBanner({String? errorMessage, String? syncMessage}) {
    _bannerTimer?.cancel();
    setState(() {
      if (errorMessage != null) {
        _errorMessage = errorMessage;
      }
      if (syncMessage != null) {
        _syncMessage = syncMessage;
      }
      _isBannerVisible = _errorMessage != null || _syncMessage != null;
    });
    if (_isBannerVisible) {
      _bannerTimer = Timer(const Duration(seconds: 3), () {
        if (!mounted) {
          return;
        }
        setState(() {
          _isBannerVisible = false;
        });
      });
    }
  }

  Future<void> _applyCameraPageOrientations() {
    return SystemChrome.setPreferredOrientations(const <DeviceOrientation>[
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  Future<void> _restoreAppOrientations() {
    return SystemChrome.setPreferredOrientations(DeviceOrientation.values);
  }

  Future<void> _setupCamera() async {
    setState(() {
      _isPreparing = true;
      _errorMessage = null;
    });

    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        setState(() {
          _isPreparing = false;
        });
        _showBanner(
          errorMessage:
              '没有发现可用摄像头。若你在安卓模拟器中调试，请把 Camera 设置为 Virtual Scene 或 Webcam0。',
        );
        return;
      }

      _selectedCameraIndex = _preferredCameraIndex(_cameras);
      await _openCamera(_selectedCameraIndex);
    } on CameraException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isPreparing = false;
      });
      _showBanner(errorMessage: _mapCameraException(error));
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isPreparing = false;
      });
      _showBanner(errorMessage: '摄像头初始化失败，请稍后重试。');
    }
  }

  Future<void> _loadTemplates() async {
    setState(() {
      _isLoadingTemplates = true;
      _errorMessage = null;
    });

    try {
      final templates = await widget.apiService.listTemplates(
        accessToken: widget.accessToken,
      );
      if (!mounted) {
        return;
      }

      setState(() {
        _templates = templates;
        _selectedTemplate = _resolvePreferredTemplate(templates);
        _templateOverlayScene = _selectedTemplate == null
            ? null
            : _overlaySceneFromTemplate(_selectedTemplate!);
        _isLoadingTemplates = false;
      });
    } on ApiException catch (error) {
      final cachedTemplates = await widget.apiService.getCachedTemplates();
      if (!mounted) {
        return;
      }

      if (cachedTemplates.isNotEmpty) {
        setState(() {
          _templates = cachedTemplates;
          _selectedTemplate = _resolvePreferredTemplate(cachedTemplates);
          _templateOverlayScene = _selectedTemplate == null
              ? null
              : _overlaySceneFromTemplate(_selectedTemplate!);
          _isLoadingTemplates = false;
        });
        _showBanner(syncMessage: '模板列表加载失败，已切换到本地缓存回显。');
        return;
      }

      setState(() {
        _isLoadingTemplates = false;
      });
      _showBanner(errorMessage: error.message);
    } catch (_) {
      final cachedTemplates = await widget.apiService.getCachedTemplates();
      if (!mounted) {
        return;
      }

      if (cachedTemplates.isNotEmpty) {
        setState(() {
          _templates = cachedTemplates;
          _selectedTemplate = _resolvePreferredTemplate(cachedTemplates);
          _templateOverlayScene = _selectedTemplate == null
              ? null
              : _overlaySceneFromTemplate(_selectedTemplate!);
          _isLoadingTemplates = false;
        });
        _showBanner(syncMessage: '模板列表暂时不可用，已展示本地缓存模板。');
        return;
      }

      setState(() {
        _isLoadingTemplates = false;
      });
      _showBanner(errorMessage: '模板列表拉取失败，请稍后重试。');
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
      final template = await widget.apiService.createTemplate(
        accessToken: widget.accessToken,
        name: '手机端示例模板',
        templateData: <String, dynamic>{
          'bbox_norm': <double>[0.30, 0.12, 0.38, 0.72],
          'pose_points': <String, List<double>>{
            '00': <double>[0.49, 0.16],
            '01': <double>[0.43, 0.26],
            '02': <double>[0.55, 0.26],
            '03': <double>[0.39, 0.38],
            '04': <double>[0.59, 0.38],
            '05': <double>[0.45, 0.50],
            '06': <double>[0.53, 0.50],
            '07': <double>[0.44, 0.66],
            '08': <double>[0.56, 0.66],
          },
        },
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _templates = <TemplateSummary>[template, ..._templates];
      });
      _showBanner(syncMessage: '已创建示例模板并自动选中。');
      _selectTemplate(template);
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      _showBanner(errorMessage: error.message);
    } catch (_) {
      if (!mounted) {
        return;
      }
      _showBanner(errorMessage: '示例模板创建失败，请稍后重试。');
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
      final template = await widget.apiService.createTemplateFromPhoto(
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
      });
      _showBanner(syncMessage: '已新增模板并自动选中：${template.name}');
      _selectTemplate(template);
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      _showBanner(errorMessage: error.message);
    } catch (_) {
      if (!mounted) {
        return;
      }
      _showBanner(errorMessage: '模板创建失败，请稍后重试。');
    } finally {
      if (mounted) {
        setState(() {
          _isCreatingDemoTemplate = false;
        });
      }
    }
  }

  TemplateSummary? _resolvePreferredTemplate(List<TemplateSummary> templates) {
    if (templates.isEmpty) {
      return null;
    }

    final currentTemplateId = _selectedTemplate?.id;
    if (currentTemplateId == null) {
      return null;
    }

    for (final template in templates) {
      if (template.id == currentTemplateId) {
        return template;
      }
    }
    return null;
  }

  Future<void> _deleteSelectedTemplate() async {
    final template = _selectedTemplate;
    if (template == null || _isDeletingTemplate) {
      return;
    }
    if (template.isRecommendedDefault) {
      _showBanner(syncMessage: '后台推荐模板不能在手机端删除，如需调整请到管理后台维护。');
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除模板'),
        content: Text('确认删除模板“${template.name}”吗？删除后将无法继续在手机端和设备联动页选中它。'),
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
      await widget.apiService.deleteTemplate(
        accessToken: widget.accessToken,
        templateId: template.id,
      );
      if (!mounted) {
        return;
      }

      final nextTemplates = _templates
          .where((item) => item.id != template.id)
          .toList(growable: false);
      final nextSelectedTemplate = _resolveTemplateSelection(nextTemplates);
      setState(() {
        _templates = nextTemplates;
      });

      if (nextSelectedTemplate != null) {
        _selectTemplate(nextSelectedTemplate, autoPick: true);
      } else {
        _clearSelectedTemplate(syncMessage: '已删除模板：${template.name}');
      }
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      _showBanner(errorMessage: error.message);
    } catch (_) {
      if (!mounted) {
        return;
      }
      _showBanner(errorMessage: '模板删除失败，请稍后重试。');
    } finally {
      if (mounted) {
        setState(() {
          _isDeletingTemplate = false;
        });
      }
    }
  }

  TemplateSummary? _resolveTemplateSelection(
    List<TemplateSummary> templates, {
    int? preferredTemplateId,
  }) {
    if (templates.isEmpty || preferredTemplateId == null) {
      return null;
    }
    for (final template in templates) {
      if (template.id == preferredTemplateId) {
        return template;
      }
    }
    return null;
  }

  void _clearSelectedTemplate({String? syncMessage}) {
    setState(() {
      _selectedTemplate = null;
      _templateOverlayScene = null;
      _captureSession = null;
      _overlayScene = _composeOverlayScene();
    });
    if (syncMessage != null && syncMessage.isNotEmpty) {
      _showBanner(syncMessage: syncMessage);
    }
  }

  void _selectShootMode(_CameraShootMode mode) {
    if (_shootMode == mode) {
      setState(() {
        _isShootModePickerExpanded = false;
      });
      return;
    }
    setState(() {
      _shootMode = mode;
      _isShootModePickerExpanded = false;
      _captureSession = null;
      _lastUploadedCapture = null;
      _lastAiTask = null;
      _analysisOverlayScene = null;
      if (mode != _CameraShootMode.aiBurst) {
        _pendingBurstCaptures.clear();
      }
      _overlayScene = _composeOverlayScene();
    });
    _showBanner(syncMessage: '已切换到$_shootModeLabel');
  }

  void _toggleShootModePicker() {
    setState(() {
      _isShootModePickerExpanded = !_isShootModePickerExpanded;
    });
  }

  String _labelForShootMode(_CameraShootMode mode) {
    switch (mode) {
      case _CameraShootMode.normal:
        return '正常拍摄';
      case _CameraShootMode.templateGuided:
        return '模板引导';
      case _CameraShootMode.aiBurst:
        return 'AI连拍';
      case _CameraShootMode.background:
        return '背景拍摄';
    }
  }

  String _keyForShootMode(_CameraShootMode mode) {
    switch (mode) {
      case _CameraShootMode.normal:
        return 'normal';
      case _CameraShootMode.templateGuided:
        return 'template_guided';
      case _CameraShootMode.aiBurst:
        return 'ai_burst';
      case _CameraShootMode.background:
        return 'background';
    }
  }

  String _sessionModeForCurrentShot() {
    if (_shootMode == _CameraShootMode.templateGuided &&
        _selectedTemplate != null) {
      return 'SMART_COMPOSE';
    }
    return 'mobile_only';
  }

  String _captureTypeForCurrentMode() {
    switch (_shootMode) {
      case _CameraShootMode.aiBurst:
        return 'burst';
      case _CameraShootMode.background:
        return 'background';
      case _CameraShootMode.normal:
      case _CameraShootMode.templateGuided:
        return 'single';
    }
  }

  String _currentCaptureStatusLabel() {
    if (_shootMode == _CameraShootMode.aiBurst && _hasPendingBurstCaptures) {
      return '待分析 ${_pendingBurstCaptures.length} 张';
    }
    if (_lastAiTask != null) {
      return _analysisStatusLabel();
    }
    if (_lastUploadedCapture != null) {
      return '已上传';
    }
    if (_lastCapture != null) {
      return '已拍摄';
    }
    return '待拍摄';
  }

  String _modeHintLabel() {
    switch (_shootMode) {
      case _CameraShootMode.normal:
        return '单张拍摄后可直接分析';
      case _CameraShootMode.templateGuided:
        return _selectedTemplate == null
            ? '未选择模板，可先拍照或进入详情选择模板'
            : '按当前模板辅助构图与分析';
      case _CameraShootMode.aiBurst:
        return _hasPendingBurstCaptures
            ? '已缓存 ${_pendingBurstCaptures.length} 张，点击分析开始AI选优'
            : '连续拍摄多张后再进行AI选优';
      case _CameraShootMode.background:
        return '用于背景观察与场景分析';
    }
  }

  CaptureRecord? _findCaptureById(
    List<CaptureRecord> captures,
    int? captureId,
  ) {
    if (captureId == null) {
      return null;
    }
    for (final capture in captures) {
      if (capture.id == captureId) {
        return capture;
      }
    }
    return null;
  }

  int _preferredCameraIndex(List<CameraDescription> cameras) {
    final index = cameras.indexWhere(
      (camera) => camera.lensDirection == CameraLensDirection.back,
    );
    return index >= 0 ? index : 0;
  }

  int? _cameraIndexForDirection(CameraLensDirection direction) {
    final index = _cameras.indexWhere(
      (camera) => camera.lensDirection == direction,
    );
    return index >= 0 ? index : null;
  }

  int? _switchTargetCameraIndex() {
    final activeCamera = _activeCamera;
    if (activeCamera == null) {
      return null;
    }

    final targetDirection =
        activeCamera.lensDirection == CameraLensDirection.front
        ? CameraLensDirection.back
        : CameraLensDirection.front;
    return _cameraIndexForDirection(targetDirection);
  }

  String _cameraSwitchUnavailableMessage() {
    final activeCamera = _activeCamera;
    if (activeCamera?.lensDirection == CameraLensDirection.front) {
      return '没有发现可用后摄，请确认设备相机配置。';
    }
    return '没有发现可用前摄，请确认系统或模拟器已启用前置摄像头。';
  }

  Future<void> _openCamera(int index) async {
    final previousController = _controller;
    await _stopLivePoseDetection(clearOverlay: false);
    final nextController = CameraController(
      _cameras[index],
      ResolutionPreset.high,
      enableAudio: false,
      imageFormatGroup: Platform.isAndroid
          ? ImageFormatGroup.nv21
          : ImageFormatGroup.bgra8888,
    );

    _controller = nextController;
    await previousController?.dispose();
    await nextController.initialize();

    if (!mounted) {
      await nextController.dispose();
      return;
    }

    setState(() {
      _selectedCameraIndex = index;
      _isPreparing = false;
      _errorMessage = null;
    });
    await _syncLivePoseDetection();
  }

  Future<void> _toggleCamera() async {
    if (_isPreparing) {
      return;
    }

    final nextIndex = _switchTargetCameraIndex();
    if (nextIndex == null) {
      _showBanner(errorMessage: _cameraSwitchUnavailableMessage());
      return;
    }

    setState(() {
      _isPreparing = true;
      _errorMessage = null;
    });

    try {
      await _openCamera(nextIndex);
      if (!mounted) {
        return;
      }
      _showBanner(
        syncMessage:
            '已切换到${_lensDirectionLabel(_cameras[_selectedCameraIndex])}镜头',
      );
    } on CameraException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isPreparing = false;
      });
      _showBanner(errorMessage: _mapCameraException(error));
    }
  }

  void _togglePreviewMirror() {
    setState(() {
      _mirrorPreview = !_mirrorPreview;
    });
    _showBanner(syncMessage: _mirrorPreview ? '画面镜像已开启。' : '画面镜像已关闭。');
  }

  Future<void> _capturePhoto() async {
    final controller = _controller;
    if (controller == null ||
        !controller.value.isInitialized ||
        _isCapturing ||
        _isPreparing ||
        _isSubmitting) {
      return;
    }

    setState(() {
      _isCapturing = true;
      _errorMessage = null;
    });

    try {
      await _stopLivePoseDetection(clearOverlay: false);
      final capture = await controller.takePicture();
      if (!mounted) {
        return;
      }

      setState(() {
        _lastCapture = capture;
        if (_shootMode == _CameraShootMode.aiBurst) {
          _pendingBurstCaptures.add(capture);
        } else {
          _pendingBurstCaptures.clear();
        }
        _captureSession = null;
        _lastUploadedCapture = null;
        _lastAiTask = null;
        _analysisOverlayScene = null;
        _overlayScene = _composeOverlayScene();
      });
      _showBanner(
        syncMessage: _shootMode == _CameraShootMode.aiBurst
            ? '已加入AI连拍序列，当前共 ${_pendingBurstCaptures.length} 张'
            : '照片已拍摄，可继续上传并生成分析结果。',
      );
    } on CameraException catch (error) {
      if (!mounted) {
        return;
      }
      _showBanner(errorMessage: _mapCameraException(error));
    } finally {
      await _syncLivePoseDetection();
      if (mounted) {
        setState(() {
          _isCapturing = false;
        });
      }
    }
  }

  Future<void> _uploadAndAnalyze() async {
    if (!_canAnalyzeCurrentSelection || _isSubmitting) {
      return;
    }
    if (_shootMode == _CameraShootMode.aiBurst &&
        _pendingBurstCaptures.length < 2) {
      _showBanner(errorMessage: 'AI连拍至少需要先拍摄 2 张照片。');
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
      _syncMessage = null;
    });

    try {
      final captureSession =
          _captureSession ??
          await widget.apiService.createCaptureSession(
            accessToken: widget.accessToken,
            templateId: _selectedTemplate?.id,
            mode: _sessionModeForCurrentShot(),
            metadata: <String, dynamic>{
              'mobile_platform': Platform.operatingSystem,
              'entry': 'camera_capture_page',
              'shoot_mode': _keyForShootMode(_shootMode),
              'shoot_mode_label': _shootModeLabel,
              'selected_template_name': _selectedTemplate?.name,
              'mirror_preview': _shouldMirrorPreview,
            },
          );

      if (_shootMode == _CameraShootMode.aiBurst) {
        final uploadedCaptures = <CaptureRecord>[];
        for (final capture in _pendingBurstCaptures) {
          final uploadedFile = await widget.apiService.uploadCaptureFile(
            accessToken: widget.accessToken,
            filePath: capture.path,
          );
          final uploadedCapture = await widget.apiService.createCapture(
            accessToken: widget.accessToken,
            sessionId: captureSession.id,
            fileUrl: uploadedFile.fileUrl,
            captureType: _captureTypeForCurrentMode(),
            width: _controller?.value.previewSize?.height.round(),
            height: _controller?.value.previewSize?.width.round(),
            storageProvider: uploadedFile.storageProvider,
            metadata: <String, dynamic>{
              'local_path': capture.path,
              'storage_path': uploadedFile.storagePath,
              'relative_path': uploadedFile.relativePath,
              'original_filename': uploadedFile.originalFilename,
              'content_type': uploadedFile.contentType,
              'shoot_mode': _keyForShootMode(_shootMode),
              'overlay': <String, dynamic>{
                'show_body_box': _overlaySettings.showBodyBox,
                'show_skeleton': _overlaySettings.showSkeleton,
                'show_template': _overlaySettings.showTemplate,
              },
              'selected_template_id': _selectedTemplate?.id,
            },
          );
          uploadedCaptures.add(uploadedCapture);
        }

        final batchPickResult = await widget.apiService.batchPick(
          accessToken: widget.accessToken,
          sessionId: captureSession.id,
          captureIds: uploadedCaptures.map((item) => item.id).toList(),
        );
        if (!mounted) {
          return;
        }

        final aiTask = batchPickResult.task;
        final bestCapture =
            _findCaptureById(uploadedCaptures, batchPickResult.bestCaptureId) ??
            uploadedCaptures.last;
        final analysisScene = _overlaySceneFromTask(aiTask);
        setState(() {
          _captureSession = captureSession;
          _lastUploadedCapture = bestCapture;
          _lastAiTask = aiTask;
          _analysisOverlayScene = aiTask.status == 'succeeded'
              ? analysisScene
              : null;
          _pendingBurstCaptures.clear();
          _overlayScene = _composeOverlayScene();
        });
        if (aiTask.status == 'succeeded') {
          _showBanner(
            syncMessage: 'AI连拍已完成选优，已从 ${uploadedCaptures.length} 张中生成结果。',
          );
        } else {
          _showBanner(
            syncMessage: '连拍序列已上传，但本次选优未成功完成。',
            errorMessage: aiTask.errorMessage ?? 'AI连拍选优失败，请稍后重试。',
          );
        }
        return;
      }

      final capture = _lastCapture!;
      final uploadedFile = await widget.apiService.uploadCaptureFile(
        accessToken: widget.accessToken,
        filePath: capture.path,
      );

      final uploadedCapture = await widget.apiService.createCapture(
        accessToken: widget.accessToken,
        sessionId: captureSession.id,
        fileUrl: uploadedFile.fileUrl,
        captureType: _captureTypeForCurrentMode(),
        width: _controller?.value.previewSize?.height.round(),
        height: _controller?.value.previewSize?.width.round(),
        storageProvider: uploadedFile.storageProvider,
        metadata: <String, dynamic>{
          'local_path': capture.path,
          'storage_path': uploadedFile.storagePath,
          'relative_path': uploadedFile.relativePath,
          'original_filename': uploadedFile.originalFilename,
          'content_type': uploadedFile.contentType,
          'shoot_mode': _keyForShootMode(_shootMode),
          'overlay': <String, dynamic>{
            'show_body_box': _overlaySettings.showBodyBox,
            'show_skeleton': _overlaySettings.showSkeleton,
            'show_template': _overlaySettings.showTemplate,
          },
          'selected_template_id': _selectedTemplate?.id,
        },
      );

      final aiTask = _shootMode == _CameraShootMode.background
          ? await widget.apiService.analyzeBackground(
              accessToken: widget.accessToken,
              sessionId: captureSession.id,
              captureId: uploadedCapture.id,
            )
          : await widget.apiService.analyzePhoto(
              accessToken: widget.accessToken,
              sessionId: captureSession.id,
              captureId: uploadedCapture.id,
            );

      if (!mounted) {
        return;
      }

      final analysisScene = _overlaySceneFromTask(aiTask);
      setState(() {
        _captureSession = captureSession;
        _lastUploadedCapture = uploadedCapture;
        _lastAiTask = aiTask;
        _analysisOverlayScene = aiTask.status == 'succeeded'
            ? analysisScene
            : null;
        _overlayScene = _composeOverlayScene();
      });
      if (aiTask.status == 'succeeded') {
        _showBanner(
          syncMessage: _shootMode == _CameraShootMode.background
              ? '已完成背景拍摄分析。'
              : '已完成上传并生成分析结果。',
        );
      } else {
        _showBanner(
          syncMessage: '图片已上传并写入记录，但本次分析未成功。',
          errorMessage: aiTask.errorMessage ?? 'AI分析失败，请检查管理端 AI 配置后重试。',
        );
      }
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      _showBanner(errorMessage: error.message);
    } catch (_) {
      if (!mounted) {
        return;
      }
      _showBanner(errorMessage: '上传或 AI 分析失败，请检查后端服务和网络后重试。');
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  Future<void> _openDeviceLinkPage() async {
    final result = await Navigator.of(context).push<DeviceLinkResult>(
      MaterialPageRoute<DeviceLinkResult>(
        builder: (_) => DeviceLinkPage(
          mobileApiService: widget.apiService,
          accessToken: widget.accessToken,
          initialTemplate: _selectedTemplate,
          initialSessionCode: _captureSession?.sessionCode,
          entryLabel: 'camera_capture_page',
        ),
      ),
    );

    if (!mounted || result == null) {
      return;
    }

    final matchedTemplate = _findTemplateById(result.selectedTemplateId);
    setState(() {
      _lastDeviceLinkResult = result;
      if (matchedTemplate != null) {
        _selectedTemplate = matchedTemplate;
        _templateOverlayScene = _overlaySceneFromTemplate(matchedTemplate);
        _overlayScene = _composeOverlayScene();
      }
    });
    _showBanner(syncMessage: _buildDeviceLinkReturnMessage(result));
  }

  TemplateSummary? _findTemplateById(int? templateId) {
    if (templateId == null) {
      return null;
    }
    for (final template in _templates) {
      if (template.id == templateId) {
        return template;
      }
    }
    return null;
  }

  String _buildDeviceLinkReturnMessage(DeviceLinkResult result) {
    final parts = <String>['已从设备联动页同步结果'];
    if (result.selectedTemplateName != null) {
      parts.add('模板：${result.selectedTemplateName}');
    }
    if (result.deviceSessionCode != null &&
        result.deviceSessionCode!.isNotEmpty) {
      parts.add('设备会话：${result.deviceSessionCode}');
    }
    if (result.lastCapturePath != null && result.lastCapturePath!.isNotEmpty) {
      parts.add('已带回最近抓拍路径');
    }
    if (result.aiLockEnabled) {
      parts.add('AI 锁机位已开启');
    }
    return parts.join('；');
  }

  File? _resolveDeviceCaptureFile() {
    final rawPath = _lastDeviceLinkResult?.lastCapturePath;
    if (rawPath == null || rawPath.trim().isEmpty) {
      return null;
    }

    final directFile = File(rawPath);
    if (directFile.existsSync()) {
      return directFile;
    }

    final relativeFile = File(
      '${Directory.current.path}${Platform.pathSeparator}$rawPath',
    );
    if (relativeFile.existsSync()) {
      return relativeFile;
    }

    return null;
  }

  void _clearDeviceLinkResult() {
    setState(() {
      _lastDeviceLinkResult = null;
    });
    _showBanner(syncMessage: '已清空本次设备联动回流信息。');
  }

  void _selectTemplate(TemplateSummary template, {bool autoPick = false}) {
    final templateScene = _overlaySceneFromTemplate(template);
    setState(() {
      _selectedTemplate = template;
      _templateOverlayScene = templateScene;
      _captureSession = null;
      _overlayScene = _composeOverlayScene();
    });
    _showBanner(
      syncMessage: autoPick
          ? '已自动载入模板：${template.name}'
          : '已切换模板：${template.name}',
    );
  }

  void _updateOverlaySettings(OverlaySettings nextSettings) {
    setState(() {
      _overlaySettings = nextSettings;
      _overlayScene = _composeOverlayScene();
    });
    unawaited(_syncLivePoseDetection());
  }

  String _overlayStatusLabel() {
    final enabled = <String>[];
    if (_overlaySettings.showBodyBox) {
      enabled.add('人体框');
    }
    if (_overlaySettings.showSkeleton) {
      enabled.add('骨架线');
    }
    if (_overlaySettings.showTemplate && _selectedTemplate != null) {
      enabled.add('模板线');
    }
    if (enabled.isEmpty) {
      return '全部关闭';
    }
    return enabled.join(' / ');
  }

  String _poseDetectionStatusLabel() {
    if (!_shouldRunLivePoseDetection) {
      return '未启用';
    }
    return _livePoseBackendLabel;
  }

  String _analysisStatusLabel() {
    final task = _lastAiTask;
    if (task == null) {
      return '未发起';
    }
    switch (task.status) {
      case 'succeeded':
        return '分析完成';
      case 'failed':
        return '分析失败';
      case 'pending':
        return '已创建任务';
      case 'running':
        return '分析中';
      case 'cancelled':
        return '已取消';
      default:
        return task.status;
    }
  }

  String? _analysisSummaryLabel() {
    final task = _lastAiTask;
    if (task == null) {
      return null;
    }

    final summary = task.resultSummary?.trim();
    if (summary != null && summary.isNotEmpty) {
      return summary;
    }

    final errorMessage = task.errorMessage?.trim();
    if (errorMessage != null && errorMessage.isNotEmpty) {
      return errorMessage;
    }

    return null;
  }

  String? _analysisScoreLabel() {
    final score = _lastAiTask?.resultScore;
    if (score == null) {
      return null;
    }
    return score.toStringAsFixed(2);
  }

  String _deviceFlowStatusLabel() {
    final result = _lastDeviceLinkResult;
    if (result == null) {
      return '未返回';
    }
    if (result.aiLockEnabled) {
      return '联动已回流';
    }
    return '已返回结果';
  }

  String _orientationLabel(Orientation orientation) {
    return orientation == Orientation.landscape ? '横屏' : '竖屏';
  }

  String _mirrorStatusLabel() {
    if (!_mirrorPreview) {
      return '已关闭';
    }
    return '已开启';
  }

  OverlayScene _composeOverlayScene() {
    final dynamicScene =
        _liveOverlayScene ?? _analysisOverlayScene ?? OverlayScene.empty();
    return dynamicScene.copyWith(
      templateSegments: _overlaySettings.showTemplate
          ? (_templateOverlayScene?.templateSegments ??
                const <OverlaySegment>[])
          : const <OverlaySegment>[],
    );
  }

  OverlayScene? _overlaySceneFromTask(AiTaskSummary task) {
    final targetBoxNorm = task.targetBoxNorm;
    if (targetBoxNorm == null || targetBoxNorm.length != 4) {
      return null;
    }

    return OverlayScene.fromTargetBox(
      NormalizedRect(
        left: targetBoxNorm[0],
        top: targetBoxNorm[1],
        width: targetBoxNorm[2],
        height: targetBoxNorm[3],
      ),
    );
  }

  OverlayScene _overlaySceneFromTemplate(TemplateSummary template) {
    return OverlayScene.fromTemplateData(template.templateData);
  }

  bool get _shouldRunLivePoseDetection {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return false;
    }
    if (!Platform.isAndroid && !Platform.isIOS) {
      return false;
    }
    if (_isPreparing || _isCapturing || _isSubmitting) {
      return false;
    }
    return _overlaySettings.showBodyBox || _overlaySettings.showSkeleton;
  }

  Future<void> _syncLivePoseDetection() async {
    if (_shouldRunLivePoseDetection) {
      await _startLivePoseDetection();
      return;
    }
    await _stopLivePoseDetection();
  }

  Future<void> _startLivePoseDetection() async {
    final controller = _controller;
    if (controller == null ||
        !controller.value.isInitialized ||
        _isImageStreamActive) {
      return;
    }

    final activeCamera = _cameras[_selectedCameraIndex];
    _lastPoseFrameAtMs = 0;
    _consecutivePoseMisses = 0;
    try {
      await controller.startImageStream((CameraImage image) {
        if (!mounted ||
            _isProcessingPoseFrame ||
            !_shouldRunLivePoseDetection) {
          return;
        }
        final nowMs = DateTime.now().millisecondsSinceEpoch;
        if (nowMs - _lastPoseFrameAtMs < _poseFrameIntervalMs) {
          return;
        }
        _lastPoseFrameAtMs = nowMs;
        _isProcessingPoseFrame = true;
        unawaited(
          _processPoseFrame(image, activeCamera).whenComplete(() {
            _isProcessingPoseFrame = false;
          }),
        );
      });
      _isImageStreamActive = true;
    } catch (_) {
      _isImageStreamActive = false;
    }
  }

  Future<void> _stopLivePoseDetection({bool clearOverlay = true}) async {
    final controller = _controller;
    final wasStreaming =
        _isImageStreamActive &&
        controller != null &&
        controller.value.isInitialized;
    _isImageStreamActive = false;
    _isProcessingPoseFrame = false;
    _lastPoseFrameAtMs = 0;
    _consecutivePoseMisses = 0;

    if (wasStreaming && controller.value.isStreamingImages) {
      try {
        await controller.stopImageStream();
      } catch (_) {
        // Ignore shutdown errors from rapidly switching camera states.
      }
    }

    if (clearOverlay && mounted) {
      setState(() {
        _liveOverlayScene = null;
        _overlayScene = _composeOverlayScene();
      });
    }
  }

  Future<void> _processPoseFrame(
    CameraImage image,
    CameraDescription camera,
  ) async {
    final rotationDegrees = _cameraImageRotationDegrees(camera);
    if (rotationDegrees == null) {
      return;
    }
    final mediaPipeScene = await _processMediaPipePoseFrame(
      image,
      rotationDegrees: rotationDegrees,
    );
    if (mediaPipeScene != null) {
      if (!mounted) {
        return;
      }
      _consecutivePoseMisses = 0;
      final nextScene = _stabilizeLiveOverlayScene(
        _liveOverlayScene,
        mediaPipeScene,
      );
      setState(() {
        _liveOverlayScene = nextScene;
        _livePoseBackendLabel = 'MediaPipe';
        _overlayScene = _composeOverlayScene();
      });
      return;
    }

    final inputImage = _inputImageFromCameraImage(image, camera);
    if (inputImage == null) {
      return;
    }

    try {
      final poses = await _poseDetector.processImage(inputImage);
      if (!mounted) {
        return;
      }

      if (poses.isEmpty) {
        _consecutivePoseMisses += 1;
        if (_consecutivePoseMisses < _maxPoseMissesBeforeClear) {
          return;
        }
        setState(() {
          _liveOverlayScene = OverlayScene.empty();
          _livePoseBackendLabel = '未检测到';
          _overlayScene = _composeOverlayScene();
        });
        return;
      }

      final rawScene = _overlaySceneFromPose(
        poses.first,
        inputImage.metadata!.size,
        inputImage.metadata!.rotation,
      );
      if (rawScene == null) {
        _consecutivePoseMisses += 1;
        if (_consecutivePoseMisses < _maxPoseMissesBeforeClear) {
          return;
        }
        setState(() {
          _liveOverlayScene = OverlayScene.empty();
          _livePoseBackendLabel = '未检测到';
          _overlayScene = _composeOverlayScene();
        });
        return;
      }

      _consecutivePoseMisses = 0;
      final nextScene = _stabilizeLiveOverlayScene(_liveOverlayScene, rawScene);
      setState(() {
        _liveOverlayScene = nextScene;
        _livePoseBackendLabel = 'ML Kit';
        _overlayScene = _composeOverlayScene();
      });
    } catch (_) {
      // Keep the preview responsive; pose failures should not interrupt capture.
    }
  }

  Future<OverlayScene?> _processMediaPipePoseFrame(
    CameraImage image, {
    required int rotationDegrees,
  }) async {
    final result = await _mediaPipePoseDetector.detect(
      image: image,
      rotationDegrees: rotationDegrees,
      timestampMs: DateTime.now().millisecondsSinceEpoch,
    );
    if (result == null) {
      return null;
    }
    if (!result.hasPose) {
      return null;
    }
    return _overlaySceneFromMediaPipePose(result);
  }

  InputImage? _inputImageFromCameraImage(
    CameraImage image,
    CameraDescription camera,
  ) {
    final rotationDegrees = _cameraImageRotationDegrees(camera);
    if (rotationDegrees == null) {
      return null;
    }
    final rotation = InputImageRotationValue.fromRawValue(rotationDegrees);
    if (rotation == null) {
      return null;
    }

    final format = InputImageFormatValue.fromRawValue(image.format.raw);
    if (format == null ||
        (Platform.isAndroid && format != InputImageFormat.nv21) ||
        (Platform.isIOS && format != InputImageFormat.bgra8888)) {
      return null;
    }
    if (image.planes.length != 1) {
      return null;
    }

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

  int? _cameraImageRotationDegrees(CameraDescription camera) {
    final controller = _controller;
    if (controller == null) {
      return null;
    }
    final sensorOrientation = camera.sensorOrientation;
    if (Platform.isIOS) {
      return sensorOrientation;
    }
    if (!Platform.isAndroid) {
      return null;
    }
    final deviceOrientation =
        _cameraOrientations[controller.value.deviceOrientation];
    if (deviceOrientation == null) {
      return null;
    }
    if (camera.lensDirection == CameraLensDirection.front) {
      return (sensorOrientation + deviceOrientation) % 360;
    }
    return (sensorOrientation - deviceOrientation + 360) % 360;
  }

  OverlayScene? _overlaySceneFromPose(
    Pose pose,
    Size imageSize,
    InputImageRotation rotation,
  ) {
    if (pose.landmarks.isEmpty) {
      return null;
    }

    final normalizedImageSize = _poseProcessingSize(imageSize, rotation);

    final sampledPoints = pose.landmarks.values
        .where((landmark) => landmark.likelihood >= 0.25)
        .map(
          (landmark) =>
              _normalizePosePoint(landmark.x, landmark.y, normalizedImageSize),
        )
        .toList(growable: false);
    if (sampledPoints.isEmpty) {
      return null;
    }

    final landmarks = pose.landmarks;
    const stableTypes = <PoseLandmarkType>[
      PoseLandmarkType.nose,
      PoseLandmarkType.leftEye,
      PoseLandmarkType.rightEye,
      PoseLandmarkType.leftEar,
      PoseLandmarkType.rightEar,
      PoseLandmarkType.leftShoulder,
      PoseLandmarkType.rightShoulder,
      PoseLandmarkType.leftElbow,
      PoseLandmarkType.rightElbow,
      PoseLandmarkType.leftHip,
      PoseLandmarkType.rightHip,
      PoseLandmarkType.leftKnee,
      PoseLandmarkType.rightKnee,
      PoseLandmarkType.leftAnkle,
      PoseLandmarkType.rightAnkle,
      PoseLandmarkType.leftHeel,
      PoseLandmarkType.rightHeel,
      PoseLandmarkType.leftFootIndex,
      PoseLandmarkType.rightFootIndex,
    ];
    final corePoints = stableTypes
        .map(
          (PoseLandmarkType type) => _normalizedPosePoint(
            landmarks,
            normalizedImageSize,
            <PoseLandmarkType>[type],
            minLikelihood: 0.25,
          ),
        )
        .whereType<NormalizedPoint>()
        .toList(growable: false);
    final boxPoints = corePoints.length >= 6 ? corePoints : sampledPoints;

    var minX = 1.0;
    var minY = 1.0;
    var maxX = 0.0;
    var maxY = 0.0;
    for (final point in boxPoints) {
      minX = math.min(minX, point.x);
      minY = math.min(minY, point.y);
      maxX = math.max(maxX, point.x);
      maxY = math.max(maxY, point.y);
    }

    final width = math.max(0.12, maxX - minX);
    final height = math.max(0.20, maxY - minY);
    final padX = math.min(0.08, width * 0.16);
    final padY = math.min(0.10, height * 0.18);
    final bodyBox = NormalizedRect(
      left: _clamp01(minX - padX),
      top: _clamp01(minY - padY),
      width: _clampDimension(maxX - minX + padX * 2, minX - padX),
      height: _clampDimension(maxY - minY + padY * 2, minY - padY),
    );

    final hiddenPoint = NormalizedPoint(double.nan, double.nan);
    final skeletonPoints = <NormalizedPoint>[
      _normalizedPosePoint(landmarks, normalizedImageSize, <PoseLandmarkType>[
            PoseLandmarkType.nose,
            PoseLandmarkType.leftEye,
            PoseLandmarkType.rightEye,
          ], minLikelihood: 0.3) ??
          hiddenPoint,
      _normalizedPosePoint(landmarks, normalizedImageSize, <PoseLandmarkType>[
            PoseLandmarkType.leftShoulder,
          ], minLikelihood: 0.22) ??
          hiddenPoint,
      _normalizedPosePoint(landmarks, normalizedImageSize, <PoseLandmarkType>[
            PoseLandmarkType.rightShoulder,
          ], minLikelihood: 0.22) ??
          hiddenPoint,
      _normalizedPosePoint(landmarks, normalizedImageSize, <PoseLandmarkType>[
            PoseLandmarkType.leftElbow,
          ], minLikelihood: 0.25) ??
          hiddenPoint,
      _normalizedPosePoint(landmarks, normalizedImageSize, <PoseLandmarkType>[
            PoseLandmarkType.rightElbow,
          ], minLikelihood: 0.25) ??
          hiddenPoint,
      _normalizedPosePoint(landmarks, normalizedImageSize, <PoseLandmarkType>[
            PoseLandmarkType.leftWrist,
          ], minLikelihood: 0.25) ??
          hiddenPoint,
      _normalizedPosePoint(landmarks, normalizedImageSize, <PoseLandmarkType>[
            PoseLandmarkType.rightWrist,
          ], minLikelihood: 0.25) ??
          hiddenPoint,
      _normalizedPosePoint(landmarks, normalizedImageSize, <PoseLandmarkType>[
            PoseLandmarkType.leftHip,
          ], minLikelihood: 0.22) ??
          hiddenPoint,
      _normalizedPosePoint(landmarks, normalizedImageSize, <PoseLandmarkType>[
            PoseLandmarkType.rightHip,
          ], minLikelihood: 0.22) ??
          hiddenPoint,
      _normalizedPosePoint(landmarks, normalizedImageSize, <PoseLandmarkType>[
            PoseLandmarkType.leftKnee,
          ], minLikelihood: 0.25) ??
          hiddenPoint,
      _normalizedPosePoint(landmarks, normalizedImageSize, <PoseLandmarkType>[
            PoseLandmarkType.rightKnee,
          ], minLikelihood: 0.25) ??
          hiddenPoint,
      _normalizedPosePoint(landmarks, normalizedImageSize, <PoseLandmarkType>[
            PoseLandmarkType.leftAnkle,
            PoseLandmarkType.leftHeel,
            PoseLandmarkType.leftFootIndex,
          ], minLikelihood: 0.25) ??
          hiddenPoint,
      _normalizedPosePoint(landmarks, normalizedImageSize, <PoseLandmarkType>[
            PoseLandmarkType.rightAnkle,
            PoseLandmarkType.rightHeel,
            PoseLandmarkType.rightFootIndex,
          ], minLikelihood: 0.25) ??
          hiddenPoint,
      _normalizedPosePoint(landmarks, normalizedImageSize, <PoseLandmarkType>[
            PoseLandmarkType.leftFootIndex,
          ], minLikelihood: 0.25) ??
          hiddenPoint,
      _normalizedPosePoint(landmarks, normalizedImageSize, <PoseLandmarkType>[
            PoseLandmarkType.rightFootIndex,
          ], minLikelihood: 0.25) ??
          hiddenPoint,
    ];

    return OverlayScene(
      bodyBox: bodyBox,
      skeletonPoints: skeletonPoints,
      templateSegments: const <OverlaySegment>[],
    );
  }

  OverlayScene? _overlaySceneFromMediaPipePose(MediaPipePoseResult result) {
    final landmarks = <int, MediaPipePoseLandmark>{
      for (final landmark in result.landmarks) landmark.index: landmark,
    };
    if (landmarks.isEmpty) {
      return null;
    }

    const stableIndices = <int>[
      0,
      2,
      5,
      7,
      8,
      11,
      12,
      13,
      14,
      23,
      24,
      25,
      26,
      27,
      28,
      29,
      30,
      31,
      32,
    ];
    final corePoints = stableIndices
        .map(
          (int index) => _normalizedMediaPipePoint(landmarks, <int>[
            index,
          ], minConfidence: 0.25),
        )
        .whereType<NormalizedPoint>()
        .toList(growable: false);
    final sampledPoints = landmarks.values
        .where((landmark) => landmark.confidence >= 0.25)
        .map(
          (landmark) =>
              NormalizedPoint(_clamp01(landmark.x), _clamp01(landmark.y)),
        )
        .toList(growable: false);
    final boxPoints = corePoints.length >= 6 ? corePoints : sampledPoints;
    if (boxPoints.isEmpty) {
      return null;
    }

    var minX = 1.0;
    var minY = 1.0;
    var maxX = 0.0;
    var maxY = 0.0;
    for (final point in boxPoints) {
      minX = math.min(minX, point.x);
      minY = math.min(minY, point.y);
      maxX = math.max(maxX, point.x);
      maxY = math.max(maxY, point.y);
    }

    final width = math.max(0.12, maxX - minX);
    final height = math.max(0.20, maxY - minY);
    final padX = math.min(0.08, width * 0.16);
    final padY = math.min(0.10, height * 0.18);
    final bodyBox = NormalizedRect(
      left: _clamp01(minX - padX),
      top: _clamp01(minY - padY),
      width: _clampDimension(maxX - minX + padX * 2, minX - padX),
      height: _clampDimension(maxY - minY + padY * 2, minY - padY),
    );

    final hiddenPoint = NormalizedPoint(double.nan, double.nan);
    final skeletonPoints = <NormalizedPoint>[
      _normalizedMediaPipePoint(landmarks, const <int>[
            0,
            2,
            5,
          ], minConfidence: 0.3) ??
          hiddenPoint,
      _normalizedMediaPipePoint(landmarks, const <int>[
            11,
          ], minConfidence: 0.22) ??
          hiddenPoint,
      _normalizedMediaPipePoint(landmarks, const <int>[
            12,
          ], minConfidence: 0.22) ??
          hiddenPoint,
      _normalizedMediaPipePoint(landmarks, const <int>[
            13,
          ], minConfidence: 0.25) ??
          hiddenPoint,
      _normalizedMediaPipePoint(landmarks, const <int>[
            14,
          ], minConfidence: 0.25) ??
          hiddenPoint,
      _normalizedMediaPipePoint(landmarks, const <int>[
            15,
          ], minConfidence: 0.25) ??
          hiddenPoint,
      _normalizedMediaPipePoint(landmarks, const <int>[
            16,
          ], minConfidence: 0.25) ??
          hiddenPoint,
      _normalizedMediaPipePoint(landmarks, const <int>[
            23,
          ], minConfidence: 0.22) ??
          hiddenPoint,
      _normalizedMediaPipePoint(landmarks, const <int>[
            24,
          ], minConfidence: 0.22) ??
          hiddenPoint,
      _normalizedMediaPipePoint(landmarks, const <int>[
            25,
          ], minConfidence: 0.25) ??
          hiddenPoint,
      _normalizedMediaPipePoint(landmarks, const <int>[
            26,
          ], minConfidence: 0.25) ??
          hiddenPoint,
      _normalizedMediaPipePoint(landmarks, const <int>[
            27,
            29,
            31,
          ], minConfidence: 0.25) ??
          hiddenPoint,
      _normalizedMediaPipePoint(landmarks, const <int>[
            28,
            30,
            32,
          ], minConfidence: 0.25) ??
          hiddenPoint,
      _normalizedMediaPipePoint(landmarks, const <int>[
            31,
          ], minConfidence: 0.25) ??
          hiddenPoint,
      _normalizedMediaPipePoint(landmarks, const <int>[
            32,
          ], minConfidence: 0.25) ??
          hiddenPoint,
    ];

    return OverlayScene(
      bodyBox: bodyBox,
      skeletonPoints: skeletonPoints,
      templateSegments: const <OverlaySegment>[],
    );
  }

  Size _poseProcessingSize(Size rawSize, InputImageRotation rotation) {
    switch (rotation) {
      case InputImageRotation.rotation90deg:
      case InputImageRotation.rotation270deg:
        return Size(rawSize.height, rawSize.width);
      case InputImageRotation.rotation0deg:
      case InputImageRotation.rotation180deg:
        return rawSize;
    }
  }

  OverlayScene _stabilizeLiveOverlayScene(
    OverlayScene? previous,
    OverlayScene next,
  ) {
    if (previous == null || !previous.hasBodyBox || !previous.hasSkeleton) {
      return next;
    }
    if (!next.hasBodyBox || !next.hasSkeleton) {
      return next;
    }

    return OverlayScene(
      bodyBox: _blendRect(previous.bodyBox, next.bodyBox, _liveBoxSmoothing),
      skeletonPoints: _blendPoints(
        previous.skeletonPoints,
        next.skeletonPoints,
        _livePointSmoothing,
      ),
      templateSegments: next.templateSegments,
    );
  }

  NormalizedPoint _normalizePosePoint(double x, double y, Size imageSize) {
    return NormalizedPoint(
      _clamp01(x / imageSize.width),
      _clamp01(y / imageSize.height),
    );
  }

  NormalizedPoint? _normalizedPosePoint(
    Map<PoseLandmarkType, PoseLandmark> landmarks,
    Size imageSize,
    List<PoseLandmarkType> types, {
    double minLikelihood = 0.15,
  }) {
    for (final type in types) {
      final landmark = landmarks[type];
      if (landmark == null || landmark.likelihood < minLikelihood) {
        continue;
      }
      return _normalizePosePoint(landmark.x, landmark.y, imageSize);
    }
    return null;
  }

  NormalizedPoint? _normalizedMediaPipePoint(
    Map<int, MediaPipePoseLandmark> landmarks,
    List<int> indices, {
    double minConfidence = 0.15,
  }) {
    for (final index in indices) {
      final landmark = landmarks[index];
      if (landmark == null || landmark.confidence < minConfidence) {
        continue;
      }
      return NormalizedPoint(_clamp01(landmark.x), _clamp01(landmark.y));
    }
    return null;
  }

  List<NormalizedPoint> _blendPoints(
    List<NormalizedPoint> previous,
    List<NormalizedPoint> next,
    double alpha,
  ) {
    if (previous.length != next.length) {
      return next;
    }
    return List<NormalizedPoint>.generate(next.length, (int index) {
      return _blendPoint(previous[index], next[index], alpha);
    }, growable: false);
  }

  NormalizedRect _blendRect(
    NormalizedRect previous,
    NormalizedRect next,
    double alpha,
  ) {
    return NormalizedRect(
      left: _blendValue(previous.left, next.left, alpha),
      top: _blendValue(previous.top, next.top, alpha),
      width: _blendValue(previous.width, next.width, alpha),
      height: _blendValue(previous.height, next.height, alpha),
    );
  }

  NormalizedPoint _blendPoint(
    NormalizedPoint previous,
    NormalizedPoint next,
    double alpha,
  ) {
    if (!next.x.isFinite || !next.y.isFinite) {
      return next;
    }
    if (!previous.x.isFinite || !previous.y.isFinite) {
      return next;
    }
    return NormalizedPoint(
      _blendValue(previous.x, next.x, alpha),
      _blendValue(previous.y, next.y, alpha),
    );
  }

  double _blendValue(double previous, double next, double alpha) {
    return previous + (next - previous) * alpha;
  }

  double _clamp01(double value) => value.clamp(0.0, 1.0);

  double _clampDimension(double value, double start) {
    final clampedStart = _clamp01(start);
    return math.max(0.0, math.min(1.0 - clampedStart, value));
  }

  String _mapCameraException(CameraException error) {
    switch (error.code) {
      case 'CameraAccessDenied':
      case 'CameraAccessDeniedWithoutPrompt':
        return '没有摄像头权限，请在系统设置中允许访问。';
      case 'AudioAccessDenied':
        return '音频权限被拒绝，但当前拍照模式不需要音频。';
      default:
        return '摄像头错误：${error.description ?? error.code}';
    }
  }

  String _lensDirectionLabel(CameraDescription camera) {
    switch (camera.lensDirection) {
      case CameraLensDirection.back:
        return '后置';
      case CameraLensDirection.front:
        return '前置';
      case CameraLensDirection.external:
        return '外接';
    }
  }

  @override
  Widget build(BuildContext context) {
    final orientation = MediaQuery.orientationOf(context);
    final isLandscape = orientation == Orientation.landscape;
    _syncScreenOrientation(orientation);

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          _buildPreviewRegion(),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: <Color>[
                    Colors.black.withValues(alpha: 0.42),
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.12),
                    Colors.black.withValues(alpha: 0.64),
                  ],
                  stops: const <double>[0.0, 0.22, 0.58, 1.0],
                ),
              ),
            ),
          ),
          _buildChrome(context, isLandscape: isLandscape),
        ],
      ),
    );
  }

  Widget _buildChrome(BuildContext context, {required bool isLandscape}) {
    return isLandscape
        ? _buildLandscapeChrome(context)
        : _buildPortraitChrome(context);
  }

  Widget _buildPortraitChrome(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
        child: Stack(
          children: <Widget>[
            Column(
              children: <Widget>[
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    _buildTopBar(context, isLandscape: false),
                    const SizedBox(height: 12),
                    _buildTopBanners(),
                  ],
                ),
                const Spacer(),
                _buildBottomHud(context, isLandscape: false),
              ],
            ),
            if (_isPreparing) const Center(child: CircularProgressIndicator()),
          ],
        ),
      ),
    );
  }

  Widget _buildLandscapeChrome(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Stack(
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                _buildLandscapeLeftPanel(context),
                const Spacer(),
                _buildLandscapeRightPanel(context),
              ],
            ),
            if (_isPreparing) const Center(child: CircularProgressIndicator()),
          ],
        ),
      ),
    );
  }

  Widget _buildPreviewRegion() {
    return Positioned.fill(
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          _buildPreview(),
          const Positioned.fill(child: _CompositionGuide()),
        ],
      ),
    );
  }

  Widget _buildPreview() {
    final controller = _controller;
    if (_isPreparing) {
      return const ColoredBox(color: Color(0xFF11161A));
    }

    if (_errorMessage != null && controller == null) {
      return _buildPreviewHint(
        '当前没有可用画面。\n如果你在安卓模拟器里调试，请到 Device Manager 把 Camera 设置成 Virtual Scene 或 Webcam0。',
      );
    }

    if (controller == null || !controller.value.isInitialized) {
      return _buildPreviewHint('摄像头还没有就绪，请稍等片刻。\n如果长时间没有画面，通常是模拟器相机没有启用。');
    }

    final previewAspectRatio = _previewWidgetAspectRatio(controller);
    final previewWidth = previewAspectRatio >= 1
        ? 1600 * previewAspectRatio
        : 1600.0;
    final previewHeight = previewAspectRatio >= 1
        ? 1600.0
        : 1600 / previewAspectRatio;

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
                  Transform(
                    alignment: Alignment.center,
                    transform: _shouldMirrorPreview
                        ? Matrix4.diagonal3Values(-1.0, 1.0, 1.0)
                        : Matrix4.identity(),
                    child: KeyedSubtree(
                      key: ValueKey<String>(
                        'camera-preview-$_selectedCameraIndex',
                      ),
                      child: _buildPlatformPreview(controller),
                    ),
                  ),
                  Positioned.fill(child: _buildCameraOverlay()),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPreviewHint(String text) {
    return ColoredBox(
      color: const Color(0xFF11161A),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70, height: 1.6),
          ),
        ),
      ),
    );
  }

  void _syncScreenOrientation(Orientation orientation) {
    final previousOrientation = _lastScreenOrientation;
    _lastScreenOrientation = orientation;
    if (previousOrientation == null || previousOrientation == orientation) {
      return;
    }
    if (_isHandlingOrientationChange || _isPreparing || _isCapturing) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _isHandlingOrientationChange) {
        return;
      }
      unawaited(_reinitializeCameraForOrientationChange());
    });
  }

  Future<void> _reinitializeCameraForOrientationChange() async {
    final controller = _controller;
    if (controller == null ||
        !controller.value.isInitialized ||
        _isPreparing ||
        _isCapturing) {
      return;
    }

    _isHandlingOrientationChange = true;
    if (mounted) {
      setState(() {
        _isPreparing = true;
        _errorMessage = null;
      });
    }

    try {
      await _openCamera(_selectedCameraIndex);
    } on CameraException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isPreparing = false;
      });
      _showBanner(errorMessage: _mapCameraException(error));
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isPreparing = false;
      });
      _showBanner(errorMessage: '屏幕旋转后重新载入摄像头失败，请稍后重试。');
    } finally {
      _isHandlingOrientationChange = false;
    }
  }

  Widget _buildLandscapeLeftPanel(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 196),
      child: Align(
        alignment: Alignment.centerLeft,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _buildTopBanners(),
              if (_isBannerVisible) const SizedBox(height: 14),
              if (_isShootModePickerExpanded) ...<Widget>[
                _buildModePopup(isLandscape: true),
                const SizedBox(height: 12),
              ],
              Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: <Widget>[
                  _buildLandscapeControlRail(),
                  const SizedBox(width: 10),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      _buildLandscapeOverlayColumn(),
                      const SizedBox(height: 10),
                      _buildLandscapeStatusColumn(),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLandscapeControlRail() {
    final railButtonSize = 48.0;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.28),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            _DockActionButton(
              icon: Icons.tune_rounded,
              label: '详情',
              size: railButtonSize,
              onTap: _openDetailsSheet,
              child: _buildRecentCaptureThumb(),
            ),
            const SizedBox(height: 10),
            _ModeMenuButton(
              label: '模式',
              size: railButtonSize,
              compact: true,
              expanded: _isShootModePickerExpanded,
              onTap: _toggleShootModePicker,
            ),
            const SizedBox(height: 10),
            _ShutterButton(
              size: 68,
              isBusy: _isCapturing,
              onTap: _isPreparing || _isCapturing || _isSubmitting
                  ? null
                  : _capturePhoto,
            ),
            const SizedBox(height: 10),
            _DockActionButton(
              icon: Icons.cameraswitch_outlined,
              label: '切换',
              size: railButtonSize,
              onTap: _cameras.isNotEmpty && !_isPreparing && !_isSubmitting
                  ? _toggleCamera
                  : null,
            ),
            const SizedBox(height: 10),
            _DockActionButton(
              icon: Icons.auto_awesome_outlined,
              label: _isSubmitting ? '分析中' : '分析',
              size: railButtonSize,
              onTap:
                  _canAnalyzeCurrentSelection &&
                      !_isPreparing &&
                      !_isCapturing &&
                      !_isSubmitting
                  ? _uploadAndAnalyze
                  : null,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLandscapeOverlayColumn() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _OverlayChip(
          label: '人体框',
          selected: _overlaySettings.showBodyBox,
          color: const Color(0xFF00D084),
          compact: true,
          onTap: () {
            _updateOverlaySettings(
              _overlaySettings.copyWith(
                showBodyBox: !_overlaySettings.showBodyBox,
              ),
            );
          },
        ),
        const SizedBox(height: 10),
        _OverlayChip(
          label: '骨架线',
          selected: _overlaySettings.showSkeleton,
          color: const Color(0xFF42C6FF),
          compact: true,
          onTap: () {
            _updateOverlaySettings(
              _overlaySettings.copyWith(
                showSkeleton: !_overlaySettings.showSkeleton,
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildLandscapeStatusColumn() {
    final statusItems = <({String label, String value})>[
      (label: '模式', value: _shootModeLabel),
      (label: '状态', value: _currentCaptureStatusLabel()),
      (label: '识别', value: _poseDetectionStatusLabel()),
    ];
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: statusItems
          .map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 96),
                child: _StatusPill(label: item.label, value: item.value),
              ),
            ),
          )
          .toList(growable: false),
    );
  }

  Widget _buildLandscapeRightPanel(BuildContext context) {
    return SizedBox(
      width: 56,
      child: Column(
        children: <Widget>[
          Align(
            alignment: Alignment.topRight,
            child: _GlassIconButton(
              icon: Icons.arrow_back_ios_new,
              tooltip: '返回',
              onPressed: () => Navigator.of(context).maybePop(),
            ),
          ),
          const Spacer(),
          RotatedBox(
            quarterTurns: 1,
            child: Text(
              '拍摄',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const Spacer(),
        ],
      ),
    );
  }

  Widget _buildTopBar(BuildContext context, {required bool isLandscape}) {
    return Row(
      children: <Widget>[
        _GlassIconButton(
          icon: Icons.arrow_back_ios_new,
          tooltip: '返回',
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                '拍摄',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: isLandscape ? 24 : 28,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                _cameras.isEmpty
                    ? '摄像头未就绪'
                    : '当前镜头：${_lensDirectionLabel(_cameras[_selectedCameraIndex])} · $_shootModeLabel',
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTopBanners() {
    if (_errorMessage == null && _syncMessage == null) {
      return const SizedBox.shrink();
    }
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, animation) {
        final offsetAnimation = Tween<Offset>(
          begin: const Offset(0, -0.08),
          end: Offset.zero,
        ).animate(animation);
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(position: offsetAnimation, child: child),
        );
      },
      child: _isBannerVisible
          ? Column(
              key: const ValueKey<String>('top-banners-visible'),
              children: <Widget>[
                if (_errorMessage != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _MessageBanner(
                      message: _errorMessage!,
                      backgroundColor: const Color(0xCC9E2A2B),
                    ),
                  ),
                if (_syncMessage != null)
                  _MessageBanner(
                    message: _syncMessage!,
                    backgroundColor: const Color(0xB32C6E49),
                  ),
              ],
            )
          : const SizedBox(key: ValueKey<String>('top-banners-hidden')),
    );
  }

  Widget _buildBottomHud(BuildContext context, {required bool isLandscape}) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: isLandscape ? 720 : 520),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            _buildStatusPills(isLandscape: isLandscape),
            SizedBox(height: isLandscape ? 6 : 8),
            Align(
              alignment: Alignment.center,
              child: _OverlayToggleBar(
                settings: _overlaySettings,
                onChanged: _updateOverlaySettings,
                compact: isLandscape,
                showTemplateToggle: false,
              ),
            ),
            SizedBox(height: isLandscape ? 8 : 10),
            _buildCaptureDock(isLandscape: isLandscape),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusPills({required bool isLandscape}) {
    final statusItems = <({String label, String value})>[
      (label: '模式', value: _shootModeLabel),
      if (_selectedTemplate != null)
        (label: '模板', value: _selectedTemplate!.name),
      (label: '状态', value: _currentCaptureStatusLabel()),
      (label: '识别', value: _poseDetectionStatusLabel()),
      if (_lastDeviceLinkResult != null)
        (label: '联动', value: _deviceFlowStatusLabel()),
    ];

    return Wrap(
      alignment: WrapAlignment.center,
      spacing: isLandscape ? 6 : 8,
      runSpacing: isLandscape ? 6 : 8,
      children: statusItems
          .map((item) => _StatusPill(label: item.label, value: item.value))
          .toList(growable: false),
    );
  }

  Widget _buildCaptureDock({required bool isLandscape}) {
    final sideButtonSize = isLandscape ? 52.0 : 56.0;
    final shutterSize = isLandscape ? 70.0 : 78.0;
    final modeGap = isLandscape ? 8.0 : 10.0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (_isShootModePickerExpanded) ...<Widget>[
          _buildModePopup(isLandscape: isLandscape),
          SizedBox(height: isLandscape ? 8 : 10),
        ],
        DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.28),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
          ),
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              isLandscape ? 12 : 14,
              isLandscape ? 8 : 10,
              isLandscape ? 12 : 14,
              isLandscape ? 8 : 10,
            ),
            child: SizedBox(
              height: isLandscape ? 72 : 82,
              child: Stack(
                children: <Widget>[
                  Align(
                    alignment: Alignment.centerLeft,
                    child: _DockActionButton(
                      icon: Icons.tune_rounded,
                      label: '详情',
                      size: sideButtonSize,
                      onTap: _openDetailsSheet,
                      child: _buildRecentCaptureThumb(),
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: _DockActionButton(
                      icon: Icons.auto_awesome_outlined,
                      label: _isSubmitting ? '分析中' : '分析',
                      size: sideButtonSize,
                      onTap:
                          _canAnalyzeCurrentSelection &&
                              !_isPreparing &&
                              !_isCapturing &&
                              !_isSubmitting
                          ? _uploadAndAnalyze
                          : null,
                    ),
                  ),
                  Align(
                    alignment: Alignment.center,
                    child: _ShutterButton(
                      size: shutterSize,
                      isBusy: _isCapturing,
                      onTap: _isPreparing || _isCapturing || _isSubmitting
                          ? null
                          : _capturePhoto,
                    ),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 0,
                    bottom: 0,
                    child: IgnorePointer(
                      ignoring: true,
                      child: Center(
                        child: SizedBox(
                          width: shutterSize + sideButtonSize * 2 + modeGap * 2,
                        ),
                      ),
                    ),
                  ),
                  Align(
                    alignment: Alignment.center,
                    child: Transform.translate(
                      offset: Offset(
                        -(shutterSize / 2 + sideButtonSize / 2 + modeGap),
                        0,
                      ),
                      child: _ModeMenuButton(
                        label: '模式',
                        size: sideButtonSize,
                        compact: isLandscape,
                        expanded: _isShootModePickerExpanded,
                        onTap: _toggleShootModePicker,
                      ),
                    ),
                  ),
                  Align(
                    alignment: Alignment.center,
                    child: Transform.translate(
                      offset: Offset(
                        shutterSize / 2 + sideButtonSize / 2 + modeGap,
                        0,
                      ),
                      child: _DockActionButton(
                        icon: Icons.cameraswitch_outlined,
                        label: '切换',
                        size: sideButtonSize,
                        onTap:
                            _cameras.isNotEmpty &&
                                !_isPreparing &&
                                !_isSubmitting
                            ? _toggleCamera
                            : null,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildModePopup({required bool isLandscape}) {
    return Align(
      alignment: Alignment.center,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.24),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        ),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: isLandscape ? 8 : 10,
            vertical: isLandscape ? 8 : 9,
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: _CameraShootMode.values
                  .map(
                    (mode) => Padding(
                      padding: EdgeInsets.only(
                        right: mode == _CameraShootMode.values.last ? 0 : 8,
                      ),
                      child: _ModeChip(
                        label: _labelForShootMode(mode),
                        selected: _shootMode == mode,
                        compact: true,
                        onTap: () => _selectShootMode(mode),
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

  Widget _buildRecentCaptureThumb() {
    if (_lastCapture == null) {
      return const Center(
        child: Icon(Icons.tune_rounded, color: Colors.white, size: 22),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Image.file(
        File(_lastCapture!.path),
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          return const Center(
            child: Icon(Icons.tune_rounded, color: Colors.white, size: 22),
          );
        },
      ),
    );
  }

  Future<void> _openDetailsSheet() async {
    if (_isShootModePickerExpanded) {
      setState(() {
        _isShootModePickerExpanded = false;
      });
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.56),
      builder: (sheetContext) {
        return _BottomSheetShell(
          title: '\u62cd\u6444\u8be6\u60c5',
          child: _buildResultsSheetContent(sheetContext),
        );
      },
    );
  }

  Widget _buildResultsSheetContent(BuildContext sheetContext) {
    final orientation = MediaQuery.orientationOf(sheetContext);
    final hasRecentCapture = _lastCapture != null;
    final hasUploadResult = _captureSession != null || _lastAiTask != null;
    final hasDeviceResult = _lastDeviceLinkResult != null;
    final hasAnyResult = hasRecentCapture || hasUploadResult || hasDeviceResult;
    final analysisSummary = _analysisSummaryLabel();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (!hasAnyResult) ...<Widget>[
          const SizedBox(height: 16),
          const _SheetHintBlock(message: '拍摄后可在这里查看最近照片、分析结果和设备联动回流。'),
        ],
        if (hasAnyResult) ...<Widget>[
          const SizedBox(height: 16),
          _SheetSection(
            title: '结果与回流',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                if (hasUploadResult)
                  _buildUploadedCapturePreview()
                else if (hasDeviceResult)
                  _buildDeviceLinkCapturePreview()
                else if (hasRecentCapture)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: AspectRatio(
                      aspectRatio: orientation == Orientation.landscape
                          ? 1.45
                          : 1.15,
                      child: Image.file(
                        File(_lastCapture!.path),
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return const _CapturePlaceholder();
                        },
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: <Widget>[
                    if (_lastAiTask != null)
                      _ResultTag(label: 'AI', value: _analysisStatusLabel()),
                    if (_analysisScoreLabel() != null)
                      _ResultTag(label: '评分', value: _analysisScoreLabel()!),
                    _ResultTag(label: '联动', value: _deviceFlowStatusLabel()),
                    if (_lastUploadedCapture != null)
                      _ResultTag(
                        label: '抓拍',
                        value: '#${_lastUploadedCapture!.id}',
                      ),
                  ],
                ),
                if (analysisSummary != null &&
                    analysisSummary.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.08),
                      ),
                    ),
                    child: Text(
                      analysisSummary,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        height: 1.55,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
                if (_shootMode == _CameraShootMode.aiBurst &&
                    !_hasPendingBurstCaptures &&
                    _lastUploadedCapture != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: const _SheetHintBlock(message: 'AI 已从本轮连拍中选出最佳照片。'),
                  ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 16),
        _SheetSection(
          title: '拍摄与取景',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: _CameraShootMode.values
                      .map(
                        (mode) => Padding(
                          padding: EdgeInsets.only(
                            right: mode == _CameraShootMode.values.last ? 0 : 8,
                          ),
                          child: _ModeChip(
                            label: _labelForShootMode(mode),
                            selected: _shootMode == mode,
                            onTap: () => _selectShootMode(mode),
                          ),
                        ),
                      )
                      .toList(growable: false),
                ),
              ),
              const SizedBox(height: 12),
              _SheetHintBlock(message: _modeHintLabel()),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: <Widget>[
                  _SheetActionButton(
                    icon: Icons.cameraswitch_outlined,
                    label: '切换镜头',
                    onTap:
                        _cameras.isNotEmpty && !_isPreparing && !_isSubmitting
                        ? _toggleCamera
                        : null,
                  ),
                  _SheetActionButton(
                    icon: _mirrorPreview
                        ? Icons.flip_camera_android_outlined
                        : Icons.flip_camera_android,
                    label: _mirrorPreview ? '关闭画面镜像' : '开启画面镜像',
                    onTap: _isPreparing ? null : _togglePreviewMirror,
                  ),
                  _SheetActionButton(
                    icon: Icons.router_outlined,
                    label: '进入设备联动',
                    onTap: _isPreparing || _isSubmitting
                        ? null
                        : () async {
                            Navigator.of(sheetContext).pop();
                            await _openDeviceLinkPage();
                          },
                  ),
                  if (_lastDeviceLinkResult != null)
                    _SheetActionButton(
                      icon: Icons.layers_clear_outlined,
                      label: '清空联动结果',
                      onTap: _clearDeviceLinkResult,
                    ),
                ],
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: <Widget>[
                  _SheetStatCard(
                    label: '镜头方向',
                    value: _cameras.isEmpty
                        ? '未就绪'
                        : _lensDirectionLabel(_cameras[_selectedCameraIndex]),
                  ),
                  _SheetStatCard(
                    label: '画面方向',
                    value: _orientationLabel(orientation),
                  ),
                  _SheetStatCard(label: '画面镜像', value: _mirrorStatusLabel()),
                  if (_selectedTemplate != null)
                    _SheetStatCard(
                      label: '当前模板',
                      value: _selectedTemplate!.name,
                    ),
                ],
              ),
              const SizedBox(height: 14),
              _SheetExpandableSection(
                title: _selectedTemplate == null
                    ? '模板（可选）'
                    : '模板（已选择：${_selectedTemplate!.name}）',
                initiallyExpanded: _selectedTemplate != null,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    if (_selectedTemplate != null) ...<Widget>[
                      _OverlayToggleBar(
                        settings: _overlaySettings,
                        onChanged: _updateOverlaySettings,
                        compact: true,
                        showBodyToggle: false,
                        showSkeletonToggle: false,
                        showTemplateToggle: true,
                      ),
                      const SizedBox(height: 12),
                    ],
                    _buildTemplateSelectionContent(sheetContext),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _SheetSection(
          title: '当前状态',
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            children: <Widget>[
              _SheetStatCard(
                label: '拍摄状态',
                value: _currentCaptureStatusLabel(),
              ),
              _SheetStatCard(label: '分析状态', value: _analysisStatusLabel()),
              _SheetStatCard(label: '设备联动', value: _deviceFlowStatusLabel()),
              _SheetStatCard(label: '识别引擎', value: _poseDetectionStatusLabel()),
              _SheetStatCard(
                label: '取景状态',
                value: _overlayStatusLabel(),
                wide: true,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _SheetSection(
          title: '拍摄详情',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              if (_captureSession != null)
                _SheetInfoLine(
                  label: '拍摄会话',
                  value:
                      '${_captureSession!.sessionCode} / ${_captureSession!.status}',
                ),
              if (_lastUploadedCapture != null)
                _SheetInfoLine(
                  label: '抓拍记录',
                  value:
                      '#${_lastUploadedCapture!.id} · ${_lastUploadedCapture!.captureType}',
                ),
              if (_lastAiTask != null)
                _SheetInfoLine(label: '任务编号', value: _lastAiTask!.taskCode),
              if (_lastDeviceLinkResult?.deviceSessionCode != null)
                _SheetInfoLine(
                  label: '设备会话',
                  value: _lastDeviceLinkResult!.deviceSessionCode!,
                ),
              if (_lastDeviceLinkResult?.selectedTemplateName != null)
                _SheetInfoLine(
                  label: '同步模板',
                  value: _lastDeviceLinkResult!.selectedTemplateName!,
                ),
              if (_lastDeviceLinkResult != null)
                _SheetInfoLine(
                  label: 'AI 锁机位',
                  value: _lastDeviceLinkResult!.aiLockEnabled ? '已开启' : '未开启',
                ),
              if (_lastDeviceLinkResult?.backendTaskCode != null)
                _SheetInfoLine(
                  label: '后端任务编号',
                  value: _lastDeviceLinkResult!.backendTaskCode!,
                ),
              if (_lastDeviceLinkResult?.lastCapturePath != null)
                _SheetInfoLine(
                  label: '最近抓拍路径',
                  value: _lastDeviceLinkResult!.lastCapturePath!,
                  multiline: true,
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTemplateSelectionContent(BuildContext sheetContext) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: <Widget>[
            if (_selectedTemplate != null)
              _SheetActionButton(
                icon: Icons.layers_clear_outlined,
                label: '不使用模板',
                onTap: () {
                  _clearSelectedTemplate(syncMessage: '已切换为无模板拍摄。');
                },
              ),
            _SheetActionButton(
              icon: Icons.add_circle_outline,
              label: _isCreatingDemoTemplate ? '新增中' : '新增模板',
              onTap: _isCreatingDemoTemplate
                  ? null
                  : () async {
                      Navigator.of(sheetContext).pop();
                      await _createTemplate();
                    },
            ),
            if (_selectedTemplate != null)
              _SheetActionButton(
                icon: Icons.delete_outline,
                label: _isDeletingTemplate ? '删除中' : '删除当前模板',
                onTap: _isDeletingTemplate
                    ? null
                    : () async {
                        Navigator.of(sheetContext).pop();
                        await _deleteSelectedTemplate();
                      },
              ),
          ],
        ),
        const SizedBox(height: 14),
        if (_isLoadingTemplates)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: LinearProgressIndicator(minHeight: 3),
          )
        else if (_templates.isEmpty)
          const _SheetHintBlock(message: '暂无模板。当前仍可直接拍照，也可以稍后新增模板继续构图。')
        else
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: <Widget>[
              _TemplateChip(
                label: '不使用模板',
                selected: _selectedTemplate == null,
                onTap: () {
                  _clearSelectedTemplate(syncMessage: '已切换为无模板拍摄。');
                },
              ),
              ..._templates.map(
                (template) => _TemplateChip(
                  label: template.name,
                  selected: _selectedTemplate?.id == template.id,
                  onTap: () {
                    _selectTemplate(template);
                  },
                ),
              ),
            ],
          ),
      ],
    );
  }

  Widget _buildDeviceLinkCapturePreview() {
    final result = _lastDeviceLinkResult;
    final captureFile = _resolveDeviceCaptureFile();
    if (result?.lastCapturePath == null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Text(
          '本次设备联动没有带回抓拍路径。',
          style: TextStyle(color: Colors.white70, height: 1.5),
        ),
      );
    }

    if (captureFile == null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text(
              '设备抓拍已回流，但当前页面无法直接预览该文件。',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              result!.lastCapturePath!,
              style: const TextStyle(color: Colors.white70, height: 1.5),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: AspectRatio(
            aspectRatio: 1.2,
            child: Image.file(
              captureFile,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) {
                return const _CapturePlaceholder();
              },
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '已预览设备侧最近抓拍。',
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: Colors.white70, height: 1.5),
        ),
      ],
    );
  }

  Widget _buildUploadedCapturePreview() {
    final uploadedCapture = _lastUploadedCapture;
    if (uploadedCapture == null) {
      return const SizedBox.shrink();
    }

    final previewSource = LocalImageResolver.resolveCaptureRecordSource(
      uploadedCapture,
    );
    if (previewSource == null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          '已写入抓拍记录，但当前无法直接预览：${uploadedCapture.fileUrl}',
          style: const TextStyle(color: Colors.white70, height: 1.5),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: AspectRatio(
            aspectRatio: 1.35,
            child: _buildResolvedCaptureImage(previewSource),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          previewSource.type == ResolvedImageSourceType.network
              ? '已显示本次抓拍的后端图片预览。'
              : '已显示本次抓拍缩略预览。',
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: Colors.white70, height: 1.5),
        ),
      ],
    );
  }

  Widget _buildResolvedCaptureImage(ResolvedImageSource source) {
    if (source.type == ResolvedImageSourceType.file) {
      return Image.file(
        source.file!,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          return const _CapturePlaceholder();
        },
      );
    }

    return Image.network(
      source.url!,
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) {
        return const _CapturePlaceholder();
      },
      loadingBuilder: (context, child, progress) {
        if (progress == null) {
          return child;
        }
        return const Center(child: CircularProgressIndicator(strokeWidth: 2));
      },
    );
  }
}

class _CompositionGuide extends StatelessWidget {
  const _CompositionGuide();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(painter: _CompositionGuidePainter()),
    );
  }
}

class _CompositionGuidePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final softPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.16)
      ..strokeWidth = 1;

    final thirdX1 = size.width / 3;
    final thirdX2 = size.width * 2 / 3;
    final thirdY1 = size.height / 3;
    final thirdY2 = size.height * 2 / 3;

    canvas.drawLine(
      Offset(thirdX1, 0),
      Offset(thirdX1, size.height),
      softPaint,
    );
    canvas.drawLine(
      Offset(thirdX2, 0),
      Offset(thirdX2, size.height),
      softPaint,
    );
    canvas.drawLine(Offset(0, thirdY1), Offset(size.width, thirdY1), softPaint);
    canvas.drawLine(Offset(0, thirdY2), Offset(size.width, thirdY2), softPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _OverlayToggleBar extends StatelessWidget {
  const _OverlayToggleBar({
    required this.settings,
    required this.onChanged,
    this.compact = false,
    this.showBodyToggle = true,
    this.showSkeletonToggle = true,
    this.showTemplateToggle = true,
  });

  final OverlaySettings settings;
  final ValueChanged<OverlaySettings> onChanged;
  final bool compact;
  final bool showBodyToggle;
  final bool showSkeletonToggle;
  final bool showTemplateToggle;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.48),
        borderRadius: BorderRadius.circular(compact ? 20 : 22),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 10 : 12,
          vertical: compact ? 8 : 10,
        ),
        child: Wrap(
          spacing: compact ? 8 : 10,
          runSpacing: compact ? 8 : 10,
          children: <Widget>[
            if (showBodyToggle)
              _OverlayChip(
                label: '\u4eba\u4f53\u6846',
                selected: settings.showBodyBox,
                color: const Color(0xFF00D084),
                compact: compact,
                onTap: () {
                  onChanged(
                    settings.copyWith(showBodyBox: !settings.showBodyBox),
                  );
                },
              ),
            if (showSkeletonToggle)
              _OverlayChip(
                label: '\u9aa8\u67b6\u7ebf',
                selected: settings.showSkeleton,
                color: const Color(0xFF42C6FF),
                compact: compact,
                onTap: () {
                  onChanged(
                    settings.copyWith(showSkeleton: !settings.showSkeleton),
                  );
                },
              ),
            if (showTemplateToggle)
              _OverlayChip(
                label: '\u6a21\u677f\u7ebf',
                selected: settings.showTemplate,
                color: const Color(0xFFD4A017),
                compact: compact,
                onTap: () {
                  onChanged(
                    settings.copyWith(showTemplate: !settings.showTemplate),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _OverlayChip extends StatelessWidget {
  const _OverlayChip({
    required this.label,
    required this.selected,
    required this.color,
    required this.onTap,
    this.compact = false,
  });

  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 12 : 14,
          vertical: compact ? 8 : 10,
        ),
        decoration: BoxDecoration(
          color: selected
              ? color.withValues(alpha: 0.30)
              : Colors.black.withValues(alpha: 0.24),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected
                ? color.withValues(alpha: 0.85)
                : Colors.white.withValues(alpha: 0.16),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: compact ? 7 : 8,
              height: compact ? 7 : 8,
              decoration: BoxDecoration(
                color: selected ? Colors.white : color,
                shape: BoxShape.circle,
              ),
            ),
            SizedBox(width: compact ? 6 : 8),
            Text(
              label,
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: compact ? 13 : 14,
              ),
            ),
          ],
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
    this.compact = false,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 14 : 16,
          vertical: compact ? 8 : 10,
        ),
        decoration: BoxDecoration(
          color: selected
              ? const Color(0x66E0A458)
              : Colors.black.withValues(alpha: 0.24),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected
                ? const Color(0xCCE0A458)
                : Colors.white.withValues(alpha: 0.12),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: Colors.white,
            fontSize: compact ? 13 : 14,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _ModeMenuButton extends StatelessWidget {
  const _ModeMenuButton({
    required this.label,
    required this.onTap,
    required this.size,
    this.compact = false,
    this.expanded = false,
  });

  final String label;
  final VoidCallback onTap;
  final double size;
  final bool compact;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(size > 56 ? 20 : 18),
        child: Ink(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: expanded
                ? const Color(0x4DE0A458)
                : Colors.black.withValues(alpha: 0.24),
            borderRadius: BorderRadius.circular(size > 56 ? 20 : 18),
            border: Border.all(
              color: expanded
                  ? const Color(0xCCE0A458)
                  : Colors.white.withValues(alpha: 0.12),
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(
                expanded
                    ? Icons.expand_less_rounded
                    : Icons.expand_more_rounded,
                size: compact ? 18 : 20,
                color: Colors.white,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: compact ? 10 : 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TemplateChip extends StatelessWidget {
  const _TemplateChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? const Color(0x4DE0A458)
              : Colors.black.withValues(alpha: 0.24),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected
                ? const Color(0xCCE0A458)
                : Colors.white.withValues(alpha: 0.12),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

class _CapturePlaceholder extends StatelessWidget {
  const _CapturePlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1A2328),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0x330D5C63)),
      ),
      alignment: Alignment.center,
      child: const Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Icon(Icons.photo_outlined, color: Colors.white70, size: 34),
          SizedBox(height: 8),
          Text('最近一张照片', style: TextStyle(color: Colors.white70)),
        ],
      ),
    );
  }
}

class _MessageBanner extends StatelessWidget {
  const _MessageBanner({required this.message, required this.backgroundColor});

  final String message;
  final Color backgroundColor;

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
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _GlassIconButton extends StatelessWidget {
  const _GlassIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.24),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
        ),
        child: IconButton(
          onPressed: onPressed,
          icon: Icon(icon, color: Colors.white, size: 20),
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 172),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.26),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                '$label ',
                style: const TextStyle(
                  color: Colors.white60,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Flexible(
                child: Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DockActionButton extends StatelessWidget {
  const _DockActionButton({
    required this.icon,
    required this.label,
    this.onTap,
    this.child,
    this.size = 56,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final Widget? child;
  final double size;

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(size > 56 ? 20 : 18);
    final innerRadius = BorderRadius.circular(size > 56 ? 16 : 14);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: borderRadius,
        child: Ink(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: onTap == null
                ? Colors.white.withValues(alpha: 0.06)
                : Colors.black.withValues(alpha: 0.24),
            borderRadius: borderRadius,
            border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
          ),
          child: child != null
              ? ClipRRect(
                  borderRadius: innerRadius,
                  child: Stack(
                    fit: StackFit.expand,
                    children: <Widget>[
                      child!,
                      Align(
                        alignment: Alignment.bottomCenter,
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 5),
                          color: Colors.black.withValues(alpha: 0.36),
                          child: Text(
                            label,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              : Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    Icon(
                      icon,
                      color: onTap == null ? Colors.white38 : Colors.white,
                      size: size > 56 ? 20 : 18,
                    ),
                    const SizedBox(height: 5),
                    Text(
                      label,
                      style: TextStyle(
                        color: onTap == null ? Colors.white38 : Colors.white70,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _ShutterButton extends StatelessWidget {
  const _ShutterButton({
    required this.size,
    required this.isBusy,
    required this.onTap,
  });

  final double size;
  final bool isBusy;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white.withValues(alpha: 0.16),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.68),
              width: 1.8,
            ),
          ),
          child: Center(
            child: isBusy
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Icon(
                    Icons.camera_alt_rounded,
                    color: Colors.white,
                    size: size * 0.38,
                  ),
          ),
        ),
      ),
    );
  }
}

class _BottomSheetShell extends StatelessWidget {
  const _BottomSheetShell({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.5,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) {
        return DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xD910181C),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Column(
            children: <Widget>[
              const SizedBox(height: 10),
              Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    _GlassIconButton(
                      icon: Icons.close,
                      tooltip: '关闭',
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                  child: child,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SheetStatCard extends StatelessWidget {
  const _SheetStatCard({
    required this.label,
    required this.value,
    this.wide = false,
  });

  final String label;
  final String value;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(minWidth: wide ? 240 : 148, maxWidth: 320),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            label,
            style: const TextStyle(
              color: Colors.white54,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              height: 1.4,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _SheetActionButton extends StatelessWidget {
  const _SheetActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            color: onTap == null
                ? Colors.white.withValues(alpha: 0.05)
                : Colors.black.withValues(alpha: 0.22),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                icon,
                color: onTap == null ? Colors.white38 : Colors.white,
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: onTap == null ? Colors.white38 : Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SheetHintBlock extends StatelessWidget {
  const _SheetHintBlock({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Text(
          message,
          style: const TextStyle(color: Colors.white70, height: 1.5),
        ),
      ),
    );
  }
}

class _ResultTag extends StatelessWidget {
  const _ResultTag({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        child: Text(
          '$label $value',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _SheetSection extends StatelessWidget {
  const _SheetSection({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 10),
            child,
          ],
        ),
      ),
    );
  }
}

class _SheetExpandableSection extends StatelessWidget {
  const _SheetExpandableSection({
    required this.title,
    required this.child,
    this.initiallyExpanded = false,
  });

  final String title;
  final Widget child;
  final bool initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: initiallyExpanded,
          tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
          collapsedIconColor: Colors.white70,
          iconColor: Colors.white,
          title: Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          children: <Widget>[child],
        ),
      ),
    );
  }
}

class _SheetInfoLine extends StatelessWidget {
  const _SheetInfoLine({
    required this.label,
    required this.value,
    this.multiline = false,
  });

  final String label;
  final String value;
  final bool multiline;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            label,
            style: const TextStyle(
              color: Colors.white54,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: multiline ? null : 1,
            overflow: multiline ? null : TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white70,
              height: 1.5,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
