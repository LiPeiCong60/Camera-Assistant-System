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
import '../template/template_preset_dialog.dart';

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
  OverlayScene _overlayScene = OverlayScene.previewSample();
  int _selectedCameraIndex = 0;
  OverlaySettings _overlaySettings = const OverlaySettings();

  @override
  void initState() {
    super.initState();
    _setupCamera();
    _loadTemplates();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
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
          _errorMessage =
              '没有发现可用摄像头。若你在安卓模拟器中调试，请把 Camera 设置为 Virtual Scene 或 Webcam0。';
          _isPreparing = false;
        });
        return;
      }

      _selectedCameraIndex = _preferredCameraIndex(_cameras);
      await _openCamera(_selectedCameraIndex);
    } on CameraException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = _mapCameraException(error);
        _isPreparing = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = '摄像头初始化失败，请稍后重试。';
        _isPreparing = false;
      });
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
        _isLoadingTemplates = false;
      });

      if (templates.isNotEmpty) {
        _selectTemplate(templates.first, autoPick: true);
      }
    } on ApiException catch (error) {
      final cachedTemplates = await widget.apiService.getCachedTemplates();
      if (!mounted) {
        return;
      }

      if (cachedTemplates.isNotEmpty) {
        setState(() {
          _templates = cachedTemplates;
          _isLoadingTemplates = false;
          _syncMessage = '模板列表加载失败，已切换到本地缓存回显。';
        });
        _selectTemplate(cachedTemplates.first, autoPick: true);
        return;
      }

      setState(() {
        _isLoadingTemplates = false;
        _errorMessage = error.message;
      });
    } catch (_) {
      final cachedTemplates = await widget.apiService.getCachedTemplates();
      if (!mounted) {
        return;
      }

      if (cachedTemplates.isNotEmpty) {
        setState(() {
          _templates = cachedTemplates;
          _isLoadingTemplates = false;
          _syncMessage = '模板列表暂时不可用，已展示本地缓存模板。';
        });
        _selectTemplate(cachedTemplates.first, autoPick: true);
        return;
      }

      setState(() {
        _isLoadingTemplates = false;
        _errorMessage = '模板列表拉取失败，请稍后重试。';
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
        _syncMessage = '已创建示例模板并自动选中。';
      });
      _selectTemplate(template);
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
        _errorMessage = '示例模板创建失败，请稍后重试。';
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

    final draft = await showTemplatePresetDialog(context, title: '新增模板');
    if (!mounted || draft == null) {
      return;
    }

    setState(() {
      _isCreatingDemoTemplate = true;
      _errorMessage = null;
    });

    try {
      final template = await widget.apiService.createTemplate(
        accessToken: widget.accessToken,
        name: draft.name,
        templateType: draft.templateType,
        templateData: draft.templateData,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _templates = <TemplateSummary>[
          template,
          ..._templates.where((item) => item.id != template.id),
        ];
        _syncMessage = '已新增模板并自动选中：${template.name}';
      });
      _selectTemplate(template);
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
        _errorMessage = '模板创建失败，请稍后重试。';
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
      setState(() {
        _errorMessage = error.message;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = '模板删除失败，请稍后重试。';
      });
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
    if (templates.isEmpty) {
      return null;
    }
    if (preferredTemplateId != null) {
      for (final template in templates) {
        if (template.id == preferredTemplateId) {
          return template;
        }
      }
    }
    return templates.first;
  }

  void _clearSelectedTemplate({String? syncMessage}) {
    setState(() {
      _selectedTemplate = null;
      _templateOverlayScene = null;
      _captureSession = null;
      _overlayScene = OverlayScene.previewSample();
      _syncMessage = syncMessage;
    });
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
    } on CameraException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = _mapCameraException(error);
        _isPreparing = false;
      });
    }
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
        _lastUploadedCapture = null;
        _lastAiTask = null;
        _overlayScene = _composeOverlayScene();
        _syncMessage = '照片已保存到本地，下一步可以上传并发起 AI 单图分析。';
      });
    } on CameraException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = _mapCameraException(error);
      });
    } finally {
      if (mounted) {
        setState(() {
          _isCapturing = false;
        });
      }
    }
  }

  Future<void> _uploadAndAnalyze() async {
    final capture = _lastCapture;
    if (capture == null || _isSubmitting) {
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
            metadata: <String, dynamic>{
              'mobile_platform': Platform.operatingSystem,
              'entry': 'camera_capture_page',
              'selected_template_name': _selectedTemplate?.name,
            },
          );

      final uploadedFile = await widget.apiService.uploadCaptureFile(
        accessToken: widget.accessToken,
        filePath: capture.path,
      );

      final uploadedCapture = await widget.apiService.createCapture(
        accessToken: widget.accessToken,
        sessionId: captureSession.id,
        fileUrl: uploadedFile.fileUrl,
        width: _controller?.value.previewSize?.height.round(),
        height: _controller?.value.previewSize?.width.round(),
        storageProvider: uploadedFile.storageProvider,
        metadata: <String, dynamic>{
          'local_path': capture.path,
          'storage_path': uploadedFile.storagePath,
          'relative_path': uploadedFile.relativePath,
          'original_filename': uploadedFile.originalFilename,
          'content_type': uploadedFile.contentType,
          'overlay': <String, dynamic>{
            'show_body_box': _overlaySettings.showBodyBox,
            'show_skeleton': _overlaySettings.showSkeleton,
            'show_template': _overlaySettings.showTemplate,
          },
          'selected_template_id': _selectedTemplate?.id,
        },
      );

      final aiTask = await widget.apiService.analyzePhoto(
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
          _syncMessage =
              '已完成上传并发起 AI 分析。会话 ${captureSession.sessionCode}，任务 ${aiTask.taskCode}。';
        } else {
          _syncMessage = '图片已上传并写入记录，但 AI 任务失败：${aiTask.taskCode}。';
          _errorMessage = aiTask.errorMessage ?? 'AI 分析失败，请检查管理端 AI 配置后重试。';
        }
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
        _errorMessage = '上传或 AI 分析失败，请检查后端服务和网络后重试。';
      });
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
      _syncMessage = _buildDeviceLinkReturnMessage(result);
    });
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
      _syncMessage = '已清空本次设备联动回流信息。';
    });
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
      _syncMessage = autoPick
          ? '已自动载入模板：${template.name}'
          : '已切换模板：${template.name}';
    });
  }

  void _updateOverlaySettings(OverlaySettings nextSettings) {
    setState(() {
      _overlaySettings = nextSettings;
    });
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
    return OverlayScene.previewSample();
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
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black.withValues(alpha: 0.25),
        foregroundColor: Colors.white,
        title: const Text('基础拍照页'),
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final previewHeight = (constraints.maxHeight * 0.42).clamp(
              260.0,
              420.0,
            );
            return Column(
              children: <Widget>[
                SizedBox(
                  height: previewHeight,
                  child: Stack(
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
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        left: 16,
                        right: 16,
                        bottom: 16,
                        child: _OverlayToggleBar(
                          settings: _overlaySettings,
                          onChanged: _updateOverlaySettings,
                        ),
                      ),
                      if (_errorMessage != null)
                        Positioned(
                          left: 16,
                          right: 16,
                          top: 16,
                          child: _MessageBanner(
                            message: _errorMessage!,
                            backgroundColor: const Color(0xCC9E2A2B),
                          ),
                        ),
                      if (_isPreparing)
                        const Center(child: CircularProgressIndicator()),
                    ],
                  ),
                ),
                Expanded(child: _buildBottomPanel(context)),
              ],
            );
          },
        ),
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

    return ColoredBox(
      color: Colors.black,
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: controller.value.previewSize!.height,
          height: controller.value.previewSize!.width,
          child: CameraPreview(controller),
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

  Widget _buildBottomPanel(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
      decoration: BoxDecoration(
        color: const Color(0xFF10181C),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.28),
            blurRadius: 24,
            offset: const Offset(0, -10),
          ),
        ],
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    '模板联动拍照闭环',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (_cameras.length > 1)
                  IconButton(
                    onPressed: _isPreparing || _isSubmitting
                        ? null
                        : _toggleCamera,
                    icon: const Icon(Icons.cameraswitch_outlined),
                    color: Colors.white,
                    tooltip: '切换前后摄',
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '当前页面已经把模板列表、模板选择、拍摄会话模板绑定和叠加层联动接起来了。现在可以先用模板确定构图，再继续上传和发起 AI 单图分析。',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Colors.white70,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 14),
            _buildTemplateSelector(context),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: _isPreparing || _isSubmitting
                  ? null
                  : _openDeviceLinkPage,
              icon: const Icon(Icons.router_outlined),
              label: Text(_selectedTemplate == null ? '前往设备联动页' : '带着模板去设备联动'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: BorderSide(color: Colors.white.withValues(alpha: 0.35)),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
              ),
            ),
            if (_syncMessage != null) ...<Widget>[
              const SizedBox(height: 12),
              _MessageBanner(
                message: _syncMessage!,
                backgroundColor: const Color(0xCC2C6E49),
              ),
            ],
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  child: _lastCapture == null
                      ? const _CapturePlaceholder()
                      : ClipRRect(
                          borderRadius: BorderRadius.circular(18),
                          child: AspectRatio(
                            aspectRatio: 1,
                            child: Image.file(
                              File(_lastCapture!.path),
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) {
                                return const _CapturePlaceholder();
                              },
                            ),
                          ),
                        ),
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      _MetaItem(
                        label: '镜头方向',
                        value: _cameras.isEmpty
                            ? '-'
                            : _lensDirectionLabel(
                                _cameras[_selectedCameraIndex],
                              ),
                      ),
                      const SizedBox(height: 10),
                      _MetaItem(
                        label: '拍照状态',
                        value: _isCapturing ? '拍摄中' : '就绪',
                      ),
                      const SizedBox(height: 10),
                      _MetaItem(
                        label: '当前模板',
                        value: _selectedTemplate?.name ?? '未选择',
                      ),
                      const SizedBox(height: 10),
                      _MetaItem(
                        label: '叠加层状态',
                        value:
                            '${_overlaySettings.showBodyBox ? '人体框' : '-'} / ${_overlaySettings.showSkeleton ? '骨架' : '-'} / ${_overlaySettings.showTemplate ? '模板' : '-'}',
                      ),
                      const SizedBox(height: 10),
                      _MetaItem(
                        label: '上传状态',
                        value: _lastUploadedCapture == null
                            ? '未上传'
                            : 'capture #${_lastUploadedCapture!.id}',
                      ),
                      const SizedBox(height: 10),
                      _MetaItem(
                        label: 'AI 任务',
                        value: _lastAiTask == null
                            ? '未发起'
                            : '${_lastAiTask!.taskCode} / ${_lastAiTask!.status}',
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              children: <Widget>[
                Expanded(
                  child: FilledButton(
                    onPressed: _isPreparing || _isCapturing || _isSubmitting
                        ? null
                        : _capturePhoto,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFE0A458),
                      foregroundColor: const Color(0xFF17313A),
                      padding: const EdgeInsets.symmetric(vertical: 18),
                    ),
                    child: _isCapturing
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('拍一张'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.tonal(
                    onPressed:
                        _lastCapture == null ||
                            _isPreparing ||
                            _isCapturing ||
                            _isSubmitting
                        ? null
                        : _uploadAndAnalyze,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF21434A),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 18),
                    ),
                    child: _isSubmitting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('上传并分析'),
                  ),
                ),
              ],
            ),
            if (_captureSession != null || _lastAiTask != null) ...<Widget>[
              const SizedBox(height: 16),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        '后端链路回显',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      const SizedBox(height: 10),
                      _buildUploadedCapturePreview(),
                      if (_lastUploadedCapture != null)
                        const SizedBox(height: 12),
                      Text(
                        _captureSession == null
                            ? '会话未创建'
                            : 'session: ${_captureSession!.sessionCode} / ${_captureSession!.status}',
                        style: const TextStyle(
                          color: Colors.white70,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _selectedTemplate == null
                            ? 'template: 未绑定'
                            : 'template: ${_selectedTemplate!.name} (#${_selectedTemplate!.id})',
                        style: const TextStyle(
                          color: Colors.white70,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _lastAiTask == null
                            ? 'AI: 未发起 analyze-photo'
                            : 'AI: ${_lastAiTask!.taskCode} / ${_lastAiTask!.status} / ${_lastAiTask!.taskType}',
                        style: const TextStyle(
                          color: Colors.white70,
                          height: 1.5,
                        ),
                      ),
                      if (_lastAiTask?.resultSummary != null) ...<Widget>[
                        const SizedBox(height: 6),
                        Text(
                          '摘要：${_lastAiTask!.resultSummary}',
                          style: const TextStyle(
                            color: Colors.white70,
                            height: 1.5,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
            if (_lastDeviceLinkResult != null) ...<Widget>[
              const SizedBox(height: 16),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        '设备联动回流',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      const SizedBox(height: 10),
                      _buildDeviceLinkCapturePreview(),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: <Widget>[
                          FilledButton.tonalIcon(
                            onPressed: _isPreparing || _isSubmitting
                                ? null
                                : _openDeviceLinkPage,
                            icon: const Icon(Icons.router_outlined),
                            label: const Text('继续设备联动'),
                          ),
                          OutlinedButton.icon(
                            onPressed: _clearDeviceLinkResult,
                            icon: const Icon(Icons.layers_clear_outlined),
                            label: const Text('清空回流'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white,
                              side: BorderSide(
                                color: Colors.white.withValues(alpha: 0.24),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'source: ${_lastDeviceLinkResult!.source}',
                        style: const TextStyle(
                          color: Colors.white70,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'device_session: ${_lastDeviceLinkResult!.deviceSessionCode ?? '-'}',
                        style: const TextStyle(
                          color: Colors.white70,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'template: ${_lastDeviceLinkResult!.selectedTemplateName ?? '-'}',
                        style: const TextStyle(
                          color: Colors.white70,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'ai_lock_enabled: ${_lastDeviceLinkResult!.aiLockEnabled}',
                        style: const TextStyle(
                          color: Colors.white70,
                          height: 1.5,
                        ),
                      ),
                      if (_lastDeviceLinkResult!.lastCapturePath !=
                          null) ...<Widget>[
                        const SizedBox(height: 6),
                        Text(
                          'last_capture_path: ${_lastDeviceLinkResult!.lastCapturePath}',
                          style: const TextStyle(
                            color: Colors.white70,
                            height: 1.5,
                          ),
                        ),
                      ],
                      if (_lastDeviceLinkResult!.backendTaskCode !=
                          null) ...<Widget>[
                        const SizedBox(height: 6),
                        Text(
                          'backend_task_code: ${_lastDeviceLinkResult!.backendTaskCode}',
                          style: const TextStyle(
                            color: Colors.white70,
                            height: 1.5,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
            TextButton(
              onPressed:
                  _selectedTemplate == null || _isDeletingTemplate
                      ? null
                      : _deleteSelectedTemplate,
              child: _isDeletingTemplate
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('删除当前'),
            ),
          ],
        ),
      ),
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

  Widget _buildTemplateSelector(BuildContext context) {
    if (_isLoadingTemplates) {
      return const LinearProgressIndicator(minHeight: 3);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                '模板选择',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
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
        if (_selectedTemplate != null)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: _isDeletingTemplate ? null : _deleteSelectedTemplate,
              child: _isDeletingTemplate
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('删除当前模板'),
            ),
          ),
        const SizedBox(height: 10),
        if (_templates.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Text(
              '暂无模板，可先新增一个模板。',
              style: TextStyle(color: Colors.white70, height: 1.5),
            ),
          )
        else
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: _templates
                .map(
                  (template) => _TemplateChip(
                    label: template.name,
                    selected: _selectedTemplate?.id == template.id,
                    onTap: () => _selectTemplate(template),
                  ),
                )
                .toList(growable: false),
          ),
      ],
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
  const _OverlayToggleBar({required this.settings, required this.onChanged});

  final OverlaySettings settings;
  final ValueChanged<OverlaySettings> onChanged;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.48),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Wrap(
          spacing: 10,
          runSpacing: 10,
          children: <Widget>[
            _OverlayChip(
              label: '人体框',
              selected: settings.showBodyBox,
              color: const Color(0xFF00D084),
              onTap: () {
                onChanged(
                  settings.copyWith(showBodyBox: !settings.showBodyBox),
                );
              },
            ),
            _OverlayChip(
              label: '骨架线',
              selected: settings.showSkeleton,
              color: const Color(0xFF42C6FF),
              onTap: () {
                onChanged(
                  settings.copyWith(showSkeleton: !settings.showSkeleton),
                );
              },
            ),
            _OverlayChip(
              label: '模板线',
              selected: settings.showTemplate,
              color: const Color(0xFFD4A017),
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
  });

  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.92) : Colors.white10,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected
                ? Colors.white.withValues(alpha: 0.6)
                : Colors.white24,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: selected ? Colors.white : color,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: selected ? const Color(0xFF102024) : Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
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
          color: selected ? const Color(0xFFE0A458) : Colors.white10,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: selected ? Colors.white70 : Colors.white24),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? const Color(0xFF17313A) : Colors.white,
            fontWeight: FontWeight.w700,
          ),
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

class _MetaItem extends StatelessWidget {
  const _MetaItem({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              label,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: Colors.white54),
            ),
            const SizedBox(height: 6),
            Text(
              value,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
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
