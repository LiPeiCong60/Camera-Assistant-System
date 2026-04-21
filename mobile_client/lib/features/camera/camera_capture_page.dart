import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../../models/ai_task_summary.dart';
import '../../models/capture_record.dart';
import '../../models/capture_session_summary.dart';
import '../../models/device_link_result.dart';
import '../../models/normalized_geometry.dart';
import '../../models/template_summary.dart';
import '../../services/api_client.dart';
import '../../services/local_image_resolver.dart';
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
  OverlayScene _overlayScene = OverlayScene.previewSample().copyWith(
    templateSegments: const <OverlaySegment>[],
  );
  _CameraShootMode _shootMode = _CameraShootMode.normal;
  int _selectedCameraIndex = 0;
  bool _mirrorPreview = true;
  bool _isBannerVisible = false;
  bool _isShootModePickerExpanded = false;
  Timer? _bannerTimer;
  final List<XFile> _pendingBurstCaptures = <XFile>[];
  OverlaySettings _overlaySettings = const OverlaySettings();

  @override
  void initState() {
    super.initState();
    _setupCamera();
    _loadTemplates();
  }

  @override
  void dispose() {
    _bannerTimer?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  bool get _isFrontCameraActive =>
      _cameras.isNotEmpty &&
      _cameras[_selectedCameraIndex].lensDirection == CameraLensDirection.front;

  bool get _shouldMirrorPreview => _mirrorPreview && _isFrontCameraActive;

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

  Future<void> _openCamera(int index) async {
    final previousController = _controller;
    final nextController = CameraController(
      _cameras[index],
      ResolutionPreset.high,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.jpeg,
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
  }

  Future<void> _toggleCamera() async {
    if (_cameras.length < 2 || _isPreparing) {
      return;
    }

    final nextIndex = (_selectedCameraIndex + 1) % _cameras.length;
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
    _showBanner(syncMessage: _mirrorPreview ? '前摄镜像已开启，模板线保持原方向。' : '前摄镜像已关闭。');
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
          _pendingBurstCaptures.clear();
          if (aiTask.status == 'succeeded') {
            _overlayScene = _composeOverlayScene(analysisScene: analysisScene);
          }
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
        if (aiTask.status == 'succeeded') {
          _overlayScene = _composeOverlayScene(analysisScene: analysisScene);
        }
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
        _overlayScene = _composeOverlayScene(
          analysisScene: _lastAiTask == null
              ? null
              : _overlaySceneFromTask(_lastAiTask!),
        );
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
      _overlayScene = _composeOverlayScene(
        analysisScene: _lastAiTask == null
            ? null
            : _overlaySceneFromTask(_lastAiTask!),
      );
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
    });
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
      case 'running':
        return '分析中';
      default:
        return task.status;
    }
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
    if (_isFrontCameraActive) {
      return '已开启';
    }
    return '前摄启用时自动镜像';
  }

  OverlayScene _composeOverlayScene({OverlayScene? analysisScene}) {
    if (analysisScene != null && _templateOverlayScene != null) {
      return analysisScene.copyWith(
        templateSegments: _templateOverlayScene!.templateSegments,
      );
    }
    if (analysisScene != null) {
      return analysisScene;
    }
    if (_templateOverlayScene != null) {
      return _templateOverlayScene!;
    }
    return OverlayScene.previewSample().copyWith(
      templateSegments: const <OverlaySegment>[],
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

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          Positioned.fill(child: _buildPreview()),
          const Positioned.fill(child: _CompositionGuide()),
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: CameraOverlayPainter(
                  scene: _overlayScene,
                  settings: _overlaySettings,
                  mirrorDynamicOverlays: _shouldMirrorPreview,
                ),
              ),
            ),
          ),
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
          SafeArea(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                isLandscape ? 20 : 16,
                10,
                isLandscape ? 20 : 16,
                isLandscape ? 8 : 14,
              ),
              child: Stack(
                children: <Widget>[
                  Column(
                    children: <Widget>[
                      _buildTopBar(context, isLandscape: isLandscape),
                      SizedBox(height: isLandscape ? 8 : 12),
                      _buildTopBanners(),
                      const Spacer(),
                      _buildBottomHud(context, isLandscape: isLandscape),
                    ],
                  ),
                  if (_isPreparing)
                    const Center(child: CircularProgressIndicator()),
                ],
              ),
            ),
          ),
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

    final preview = SizedBox(
      width: controller.value.previewSize!.height,
      height: controller.value.previewSize!.width,
      child: CameraPreview(controller),
    );

    return ColoredBox(
      color: Colors.black,
      child: FittedBox(
        fit: BoxFit.cover,
        child: Transform(
          alignment: Alignment.center,
          transform: _shouldMirrorPreview
              ? Matrix4.diagonal3Values(-1.0, 1.0, 1.0)
              : Matrix4.identity(),
          child: preview,
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
                showTemplateToggle: _selectedTemplate != null,
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
                            _cameras.length > 1 &&
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: <Widget>[
            _ResultTag(label: '模式', value: _shootModeLabel),
            _ResultTag(
              label: '镜头',
              value: _cameras.isEmpty
                  ? '未就绪'
                  : _lensDirectionLabel(_cameras[_selectedCameraIndex]),
            ),
            _ResultTag(label: '方向', value: _orientationLabel(orientation)),
            if (_selectedTemplate != null)
              _ResultTag(label: '模板', value: _selectedTemplate!.name),
            _ResultTag(label: '状态', value: _currentCaptureStatusLabel()),
            _ResultTag(label: '联动', value: _deviceFlowStatusLabel()),
          ],
        ),
        const SizedBox(height: 16),
        _SheetSection(
          title: '当前状态',
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            children: <Widget>[
              _SheetStatCard(label: '拍摄模式', value: _shootModeLabel),
              if (_selectedTemplate != null)
                _SheetStatCard(
                  label: '当前模板',
                  value: _selectedTemplate!.name,
                ),
              _SheetStatCard(
                label: '取景状态',
                value: _overlayStatusLabel(),
                wide: true,
              ),
              _SheetStatCard(
                label: '前摄镜像',
                value: _mirrorStatusLabel(),
                wide: true,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _SheetSection(
          title: '拍摄模式',
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
            ],
          ),
        ),
        const SizedBox(height: 16),
        _SheetSection(
          title: '取景设置',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: <Widget>[
                  _SheetActionButton(
                    icon: Icons.cameraswitch_outlined,
                    label: '切换镜头',
                    onTap:
                        _cameras.length > 1 && !_isPreparing && !_isSubmitting
                        ? _toggleCamera
                        : null,
                  ),
                  _SheetActionButton(
                    icon: _mirrorPreview
                        ? Icons.flip_camera_android_outlined
                        : Icons.flip_camera_android,
                    label: _mirrorPreview ? '关闭前摄镜像' : '开启前摄镜像',
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
                ],
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: <Widget>[
                  if (_selectedTemplate != null)
                    _SheetStatCard(
                      label: '当前模板',
                      value: _selectedTemplate!.name,
                    ),
                  _SheetStatCard(
                    label: '设备联动',
                    value: _deviceFlowStatusLabel(),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _SheetExpandableSection(
                title: _selectedTemplate == null
                    ? '模板（可选）'
                    : '模板（已选择：${_selectedTemplate!.name}）',
                initiallyExpanded: _selectedTemplate != null,
                child: _buildTemplateSelectionContent(sheetContext),
              ),
              if (_lastDeviceLinkResult != null) ...<Widget>[
                const SizedBox(height: 14),
                _SheetInfoLine(
                  label: '设备会话',
                  value: _lastDeviceLinkResult?.deviceSessionCode ?? '未返回',
                ),
                _SheetInfoLine(
                  label: '同步模板',
                  value:
                      _lastDeviceLinkResult?.selectedTemplateName ??
                      (_selectedTemplate?.name ?? '-'),
                ),
                _SheetInfoLine(label: '设备状态', value: _deviceFlowStatusLabel()),
                const SizedBox(height: 10),
                _SheetActionButton(
                  icon: Icons.layers_clear_outlined,
                  label: '清空联动结果',
                  onTap: () {
                    _clearDeviceLinkResult();
                  },
                ),
              ],
            ],
          ),
        ),
        if (!hasRecentCapture &&
            !hasUploadResult &&
            !hasDeviceResult) ...<Widget>[
          const SizedBox(height: 16),
          const _SheetHintBlock(message: '拍摄后可在这里查看最近照片、分析结果和设备联动回流。'),
        ],
        if (hasRecentCapture || hasUploadResult || hasDeviceResult) ...<Widget>[
          const SizedBox(height: 16),
          _SheetSection(
            title: '结果与回流',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                if (hasRecentCapture)
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
                if (hasRecentCapture && (hasUploadResult || hasDeviceResult))
                  const SizedBox(height: 14),
                if (hasUploadResult) ...<Widget>[
                  _buildUploadedCapturePreview(),
                  if (_lastUploadedCapture != null) const SizedBox(height: 12),
                  _SheetInfoLine(
                    label: '拍摄会话',
                    value: _captureSession == null
                        ? '未生成'
                        : '${_captureSession!.sessionCode} / ${_captureSession!.status}',
                  ),
                  _SheetInfoLine(label: '分析状态', value: _analysisStatusLabel()),
                  if (_lastUploadedCapture != null)
                    _SheetInfoLine(
                      label: '抓拍记录',
                      value:
                          '#${_lastUploadedCapture!.id} · ${_lastUploadedCapture!.captureType}',
                    ),
                  if (_lastAiTask != null)
                    _SheetInfoLine(label: '任务编号', value: _lastAiTask!.taskCode),
                  if (_lastAiTask?.resultSummary != null)
                    _SheetInfoLine(
                      label: '结果摘要',
                      value: _lastAiTask!.resultSummary!,
                      multiline: true,
                    ),
                ],
                if (hasUploadResult && hasDeviceResult)
                  const SizedBox(height: 14),
                if (hasDeviceResult) ...<Widget>[
                  _SheetInfoLine(
                    label: '设备回流',
                    value: _deviceFlowStatusLabel(),
                  ),
                  _buildDeviceLinkCapturePreview(),
                  const SizedBox(height: 12),
                  _SheetInfoLine(
                    label: '设备会话',
                    value: _lastDeviceLinkResult!.deviceSessionCode ?? '-',
                  ),
                  _SheetInfoLine(
                    label: '同步模板',
                    value: _lastDeviceLinkResult!.selectedTemplateName ?? '-',
                  ),
                  _SheetInfoLine(
                    label: 'AI 锁机位',
                    value: _lastDeviceLinkResult!.aiLockEnabled ? '已开启' : '未开启',
                  ),
                  if (_lastDeviceLinkResult!.backendTaskCode != null)
                    _SheetInfoLine(
                      label: '后端任务编号',
                      value: _lastDeviceLinkResult!.backendTaskCode!,
                    ),
                  if (_lastDeviceLinkResult!.lastCapturePath != null)
                    _SheetInfoLine(
                      label: '最近抓拍路径',
                      value: _lastDeviceLinkResult!.lastCapturePath!,
                      multiline: true,
                    ),
                ],
                if (_shootMode == _CameraShootMode.aiBurst &&
                    !_hasPendingBurstCaptures &&
                    _lastUploadedCapture != null)
                  _SheetInfoLine(
                    label: '连拍结果',
                    value: 'AI 已从本轮连拍中选出最佳照片。',
                    multiline: true,
                  ),
              ],
            ),
          ),
        ],
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
          const _SheetHintBlock(
            message: '暂无模板。当前仍可直接拍照，也可以稍后新增模板继续构图。',
          )
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
    this.showTemplateToggle = true,
  });

  final OverlaySettings settings;
  final ValueChanged<OverlaySettings> onChanged;
  final bool compact;
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
