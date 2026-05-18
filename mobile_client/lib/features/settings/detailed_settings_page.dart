import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/auth_session.dart';
import '../../models/plan_summary.dart';
import '../../models/template_summary.dart';
import '../../services/api_client.dart';
import '../../services/app_config.dart';
import '../../services/gallery_save_service.dart';
import '../auth/auth_controller.dart';
import '../camera/camera_capture_page.dart';
import '../device_link/device_link_page.dart';
import '../history/history_page.dart';
import '../home/plan_detail_page.dart';
import '../template/template_photo_dialog.dart';
import 'server_config_page.dart';

class DetailedSettingsPage extends StatefulWidget {
  const DetailedSettingsPage({
    super.key,
    required this.controller,
    required this.session,
    required this.serviceStatus,
  });

  final AuthController controller;
  final AuthSession session;
  final String serviceStatus;

  @override
  State<DetailedSettingsPage> createState() => _DetailedSettingsPageState();
}

class _DetailedSettingsPageState extends State<DetailedSettingsPage> {
  final TextEditingController _searchController = TextEditingController();
  final GallerySaveService _galleryService = const GallerySaveService();

  List<TemplateSummary> _templates = const <TemplateSummary>[];
  bool _isLoadingTemplates = true;
  bool _isBusy = false;
  String _query = '';
  String? _message;
  String? _errorMessage;
  bool _showBodyBoxDefault = true;
  bool _showSkeletonDefault = true;
  bool _showTemplateBoxDefault = true;
  bool _showTemplateLineDefault = true;
  bool _showCenterPointDefault = true;
  bool _savePhotosToGallery = true;
  bool _saveVideosToGallery = true;
  bool _showRecordingTimer = true;
  bool _autoStartMobilePush = true;
  bool _landscapeControlsLeft = false;
  bool _gestureCaptureEnabled = true;
  bool _gestureOkCaptureEnabled = true;
  bool _gestureAnalyzeAfterCapture = false;
  bool _backgroundLockEnabled = false;
  bool _showAiRecommendationBox = true;
  bool _showTargetCenterPoint = true;
  bool _mirrorPreviewDefault = false;
  bool _enableLandscapeCapture = true;
  bool _autoSelectTemplate = true;
  bool _uploadPhotosToHistory = true;
  bool _uploadVideosToHistory = false;
  bool _showSaveResultBanner = true;
  bool _deviceAutoRefresh = true;
  bool _showDeviceJoystick = true;
  bool _preferWebRtcPush = false;
  bool _allowHttpPushFallback = true;
  bool _deviceOverlayEnabled = true;
  bool _deviceShowLivePersonBox = true;
  bool _deviceShowLiveSkeleton = true;
  bool _deviceShowLiveHands = true;
  bool _deviceShowTemplateBox = true;
  bool _deviceShowTemplateSkeleton = true;
  bool _deviceShowAiLockBox = true;
  bool _gestureRequireTemplateReady = true;
  bool _gestureAutoSaveToGallery = true;
  bool _runAiAfterPhotoCapture = false;
  bool _runAiAfterVideoCapture = false;
  double _sensitivity = 1.0;
  double _followDeadZone = 0.05;
  double _followSmoothing = 0.35;
  double _panScanRange = 18;
  double _tiltScanRange = 12;
  double _scanStepDegrees = 4;
  double _settleSeconds = 0.8;
  double _candidateCount = 6;
  double _aiStartDelaySeconds = 0;
  double _poseFrameIntervalMs = 90;
  double _poseMissesBeforeClear = 4;
  double _liveBoxSmoothing = 0.22;
  double _livePointSmoothing = 0.28;
  double _aiBurstMinPhotos = 2;
  double _devicePollSeconds = 3;
  double _countdownPollSeconds = 1;
  double _manualMoveRepeatMs = 110;
  double _mobilePushFrameMs = 66;
  double _mobilePushHttpFrameMs = 220;
  double _mobileTrackTargetMs = 140;
  double _mobilePushSocketTimeoutSeconds = 8;
  double _mobilePoseMissesBeforeClear = 6;
  double _recordingPreviewFrameMs = 120;
  double _gestureCountdownSeconds = 3;
  String _followTargetMode = 'shoulders';
  String _defaultShootMode = 'normal';
  String _preferredCameraLens = 'back';
  String _templateRecognitionMode = 'backend';
  String _deviceStartMode = 'MANUAL';
  String _mobilePushTransport = 'websocket';
  String _mobilePushCameraLens = 'back';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_handleSearchChanged);
    unawaited(_loadDetailedPreferences());
    _loadTemplates();
  }

  @override
  void dispose() {
    _searchController.removeListener(_handleSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _handleSearchChanged() {
    setState(() {
      _query = _searchController.text.trim();
    });
  }

  static String _prefKey(String name) => 'detailed_settings.$name';

  Future<void> _loadDetailedPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) {
      return;
    }
    setState(() {
      _showBodyBoxDefault =
          prefs.getBool(_prefKey('overlay.show_body_box')) ??
          _showBodyBoxDefault;
      _showSkeletonDefault =
          prefs.getBool(_prefKey('overlay.show_skeleton')) ??
          _showSkeletonDefault;
      _showTemplateBoxDefault =
          prefs.getBool(_prefKey('overlay.show_template_box')) ??
          _showTemplateBoxDefault;
      _showTemplateLineDefault =
          prefs.getBool(_prefKey('overlay.show_template_line')) ??
          _showTemplateLineDefault;
      _showCenterPointDefault =
          prefs.getBool(_prefKey('overlay.show_center_point')) ??
          _showCenterPointDefault;
      _savePhotosToGallery =
          prefs.getBool(_prefKey('recording.save_photos_to_gallery')) ??
          _savePhotosToGallery;
      _saveVideosToGallery =
          prefs.getBool(_prefKey('recording.save_videos_to_gallery')) ??
          _saveVideosToGallery;
      _showRecordingTimer =
          prefs.getBool(_prefKey('recording.show_timer')) ??
          _showRecordingTimer;
      _autoStartMobilePush =
          prefs.getBool(_prefKey('device.auto_start_mobile_push')) ??
          _autoStartMobilePush;
      _landscapeControlsLeft =
          prefs.getBool(_prefKey('device.landscape_left')) ??
          _landscapeControlsLeft;
      _gestureCaptureEnabled =
          prefs.getBool(_prefKey('gesture.capture_enabled')) ??
          _gestureCaptureEnabled;
      _gestureOkCaptureEnabled =
          prefs.getBool(_prefKey('gesture.ok_capture_enabled')) ??
          _gestureOkCaptureEnabled;
      _gestureAnalyzeAfterCapture =
          prefs.getBool(_prefKey('gesture.analyze_after_capture')) ??
          _gestureAnalyzeAfterCapture;
      _backgroundLockEnabled =
          prefs.getBool(_prefKey('device_overlay.ai_lock_box')) ??
          _backgroundLockEnabled;
      _showAiRecommendationBox =
          prefs.getBool(_prefKey('ai.show_recommendation_box')) ??
          _showAiRecommendationBox;
      _showTargetCenterPoint =
          prefs.getBool(_prefKey('ai.show_target_center')) ??
          _showTargetCenterPoint;
      _mirrorPreviewDefault =
          prefs.getBool(_prefKey('camera.mirror_preview')) ??
          _mirrorPreviewDefault;
      _enableLandscapeCapture =
          prefs.getBool(_prefKey('camera.enable_landscape')) ??
          _enableLandscapeCapture;
      _autoSelectTemplate =
          prefs.getBool(_prefKey('template.auto_select')) ??
          _autoSelectTemplate;
      _uploadPhotosToHistory =
          prefs.getBool(_prefKey('recording.upload_photos_to_history')) ??
          _uploadPhotosToHistory;
      _uploadVideosToHistory =
          prefs.getBool(_prefKey('recording.upload_videos_to_history')) ??
          _uploadVideosToHistory;
      _showSaveResultBanner =
          prefs.getBool(_prefKey('recording.show_save_banner')) ??
          _showSaveResultBanner;
      _deviceAutoRefresh =
          prefs.getBool(_prefKey('device.auto_refresh')) ?? _deviceAutoRefresh;
      _showDeviceJoystick =
          prefs.getBool(_prefKey('device.show_joystick')) ??
          _showDeviceJoystick;
      _preferWebRtcPush =
          prefs.getBool(_prefKey('push.prefer_webrtc')) ?? _preferWebRtcPush;
      _allowHttpPushFallback =
          prefs.getBool(_prefKey('push.allow_http_fallback')) ??
          _allowHttpPushFallback;
      _deviceOverlayEnabled =
          prefs.getBool(_prefKey('device_overlay.enabled')) ??
          _deviceOverlayEnabled;
      _deviceShowLivePersonBox =
          prefs.getBool(_prefKey('device_overlay.live_person_box')) ??
          _deviceShowLivePersonBox;
      _deviceShowLiveSkeleton =
          prefs.getBool(_prefKey('device_overlay.live_skeleton')) ??
          _deviceShowLiveSkeleton;
      _deviceShowLiveHands =
          prefs.getBool(_prefKey('device_overlay.live_hands')) ??
          _deviceShowLiveHands;
      _deviceShowTemplateBox =
          prefs.getBool(_prefKey('device_overlay.template_box')) ??
          _deviceShowTemplateBox;
      _deviceShowTemplateSkeleton =
          prefs.getBool(_prefKey('device_overlay.template_skeleton')) ??
          _deviceShowTemplateSkeleton;
      _deviceShowAiLockBox =
          prefs.getBool(_prefKey('device_overlay.ai_lock_box')) ??
          _deviceShowAiLockBox;
      _gestureRequireTemplateReady =
          prefs.getBool(_prefKey('gesture.require_template_ready')) ??
          _gestureRequireTemplateReady;
      _gestureAutoSaveToGallery =
          prefs.getBool(_prefKey('gesture.auto_save_to_gallery')) ??
          _gestureAutoSaveToGallery;
      _runAiAfterPhotoCapture =
          prefs.getBool(_prefKey('ai.run_after_photo_capture')) ??
          _runAiAfterPhotoCapture;
      _runAiAfterVideoCapture =
          prefs.getBool(_prefKey('ai.run_after_video_capture')) ??
          _runAiAfterVideoCapture;
      _sensitivity =
          prefs.getDouble(_prefKey('device.sensitivity')) ??
          _sensitivity;
      _followDeadZone =
          prefs.getDouble(_prefKey('device.follow_dead_zone')) ??
          _followDeadZone;
      _followSmoothing =
          prefs.getDouble(_prefKey('device.follow_smoothing')) ??
          _followSmoothing;
      _panScanRange =
          prefs.getDouble(_prefKey('ai.pan_scan_range')) ?? _panScanRange;
      _tiltScanRange =
          prefs.getDouble(_prefKey('ai.tilt_scan_range')) ?? _tiltScanRange;
      _scanStepDegrees =
          prefs.getDouble(_prefKey('ai.scan_step_degrees')) ?? _scanStepDegrees;
      _settleSeconds =
          prefs.getDouble(_prefKey('ai.settle_seconds')) ?? _settleSeconds;
      _candidateCount =
          prefs.getDouble(_prefKey('ai.candidate_count')) ?? _candidateCount;
      _aiStartDelaySeconds =
          prefs.getDouble(_prefKey('ai.start_delay_seconds')) ??
          _aiStartDelaySeconds;
      _poseFrameIntervalMs =
          prefs.getDouble(_prefKey('camera.pose_frame_interval_ms')) ??
          _poseFrameIntervalMs;
      _poseMissesBeforeClear =
          prefs.getDouble(_prefKey('camera.pose_misses_before_clear')) ??
          _poseMissesBeforeClear;
      _liveBoxSmoothing =
          prefs.getDouble(_prefKey('camera.live_box_smoothing')) ??
          _liveBoxSmoothing;
      _livePointSmoothing =
          prefs.getDouble(_prefKey('camera.live_point_smoothing')) ??
          _livePointSmoothing;
      _aiBurstMinPhotos =
          prefs.getDouble(_prefKey('camera.ai_burst_min_photos')) ??
          _aiBurstMinPhotos;
      _devicePollSeconds =
          prefs.getDouble(_prefKey('device.poll_seconds')) ??
          _devicePollSeconds;
      _countdownPollSeconds =
          prefs.getDouble(_prefKey('device.countdown_poll_seconds')) ??
          _countdownPollSeconds;
      _manualMoveRepeatMs =
          prefs.getDouble(_prefKey('device.manual_move_repeat_ms')) ??
          _manualMoveRepeatMs;
      _mobilePushFrameMs =
          prefs.getDouble(_prefKey('push.frame_ms')) ?? _mobilePushFrameMs;
      _mobilePushHttpFrameMs =
          prefs.getDouble(_prefKey('push.http_frame_ms')) ??
          _mobilePushHttpFrameMs;
      _mobileTrackTargetMs =
          prefs.getDouble(_prefKey('push.track_target_ms')) ??
          _mobileTrackTargetMs;
      _mobilePushSocketTimeoutSeconds =
          prefs.getDouble(_prefKey('push.socket_timeout_seconds')) ??
          _mobilePushSocketTimeoutSeconds;
      _mobilePoseMissesBeforeClear =
          prefs.getDouble(_prefKey('push.pose_misses_before_clear')) ??
          _mobilePoseMissesBeforeClear;
      _recordingPreviewFrameMs =
          prefs.getDouble(_prefKey('recording.preview_frame_ms')) ??
          _recordingPreviewFrameMs;
      _gestureCountdownSeconds =
          prefs.getDouble(_prefKey('gesture.countdown_seconds')) ??
          _gestureCountdownSeconds;
      _followTargetMode =
          prefs.getString(_prefKey('device.follow_target_mode')) ??
          _followTargetMode;
      _defaultShootMode =
          prefs.getString(_prefKey('camera.default_shoot_mode')) ??
          _defaultShootMode;
      _preferredCameraLens =
          prefs.getString(_prefKey('camera.preferred_lens')) ??
          _preferredCameraLens;
      _templateRecognitionMode =
          prefs.getString(_prefKey('template.recognition_mode')) ??
          _templateRecognitionMode;
      _deviceStartMode =
          prefs.getString(_prefKey('device.start_mode')) ?? _deviceStartMode;
      _mobilePushTransport =
          prefs.getString(_prefKey('push.transport')) ?? _mobilePushTransport;
      _mobilePushCameraLens =
          prefs.getString(_prefKey('push.camera_lens')) ??
          _mobilePushCameraLens;
    });
  }

  Future<void> _setBoolPreference(
    String key,
    bool value,
    ValueChanged<bool> apply,
  ) async {
    setState(() {
      apply(value);
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKey(key), value);
  }

  Future<void> _setDoublePreference(
    String key,
    double value,
    ValueChanged<double> apply,
  ) async {
    setState(() {
      apply(value);
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_prefKey(key), value);
  }

  Future<void> _setStringPreference(
    String key,
    String value,
    ValueChanged<String> apply,
  ) async {
    setState(() {
      apply(value);
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKey(key), value);
  }

  Future<void> _loadTemplates() async {
    setState(() {
      _isLoadingTemplates = true;
      _errorMessage = null;
    });

    try {
      final templates = await widget.controller.apiService.listTemplates(
        accessToken: widget.session.accessToken,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _templates = templates;
      });
    } on ApiException catch (error) {
      final cached = await widget.controller.apiService.getCachedTemplates();
      if (!mounted) {
        return;
      }
      setState(() {
        _templates = cached;
        _errorMessage = cached.isEmpty ? error.message : '模板列表刷新失败，已显示本地缓存。';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingTemplates = false;
        });
      }
    }
  }

  Future<void> _createTemplate() async {
    if (_isBusy) {
      return;
    }
    final draft = await showTemplatePhotoDialog(
      context,
      title: '新增模板',
      enabledRecognitionModes: const <TemplateRecognitionMode>{
        TemplateRecognitionMode.backend,
      },
    );
    if (!mounted || draft == null) {
      return;
    }

    setState(() {
      _isBusy = true;
      _message = null;
      _errorMessage = null;
    });

    try {
      final template = await widget.controller.apiService
          .createTemplateFromPhoto(
            accessToken: widget.session.accessToken,
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
        _message = '已创建模板：${template.name}';
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
        _errorMessage = '模板创建失败，请稍后重试。';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isBusy = false;
        });
      }
    }
  }

  Future<void> _deleteTemplate(TemplateSummary template) async {
    if (_isBusy) {
      return;
    }
    if (template.isRecommendedDefault) {
      setState(() {
        _message = null;
        _errorMessage = '后台推荐模板不能在手机端删除。';
      });
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除模板'),
        content: Text('确认删除模板“${template.name}”吗？删除后无法继续选中它。'),
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
    if (!mounted || confirmed != true) {
      return;
    }

    setState(() {
      _isBusy = true;
      _message = null;
      _errorMessage = null;
    });

    try {
      await widget.controller.apiService.deleteTemplate(
        accessToken: widget.session.accessToken,
        templateId: template.id,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _templates = _templates
            .where((item) => item.id != template.id)
            .toList(growable: false);
        _message = '已删除模板：${template.name}';
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
        _errorMessage = '模板删除失败，请稍后重试。';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isBusy = false;
        });
      }
    }
  }

  Future<void> _openPlanDetails({int? initialPlanId}) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => PlanDetailPage(
          controller: widget.controller,
          accessToken: widget.session.accessToken,
          initialPlanId: initialPlanId,
        ),
      ),
    );
  }

  Future<void> _openCameraPage() {
    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => CameraCapturePage(
          apiService: widget.controller.apiService,
          accessToken: widget.session.accessToken,
          detailedSettingsBuilder: (_) => DetailedSettingsPage(
            controller: widget.controller,
            session: widget.session,
            serviceStatus: widget.serviceStatus,
          ),
        ),
      ),
    );
  }

  Future<void> _openDeviceLinkPage() {
    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => DeviceLinkPage(
          mobileApiService: widget.controller.apiService,
          accessToken: widget.session.accessToken,
          initialDeviceApiBaseUrl:
              widget.controller.serverConfig.deviceApiBaseUrl,
          detailedSettingsBuilder: (_) => DetailedSettingsPage(
            controller: widget.controller,
            session: widget.session,
            serviceStatus: widget.serviceStatus,
          ),
        ),
      ),
    );
  }

  Future<void> _openHistoryPage() {
    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => HistoryPage(
          apiService: widget.controller.apiService,
          accessToken: widget.session.accessToken,
        ),
      ),
    );
  }

  Future<void> _openGallery() async {
    final opened = await _galleryService.openGallery();
    if (!mounted) {
      return;
    }
    setState(() {
      _message = opened ? '已打开本机相册。' : null;
      _errorMessage = opened ? null : '无法打开本机相册，请从系统图库进入。';
    });
  }

  Future<void> _openServerConfigPage() {
    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => ServerConfigPage(
          initialConfig: widget.controller.serverConfig,
          onSaved: (config) async {
            await AppConfig.saveServerConfig(config);
            if (!mounted) {
              return;
            }
            Navigator.of(context).pop();
            setState(() {
              _message = '连接地址已保存，重新打开应用后生效。';
              _errorMessage = null;
            });
          },
          onCancel: () => Navigator.of(context).pop(),
        ),
      ),
    );
  }

  Future<void> _refreshDashboard() async {
    await widget.controller.refreshDashboard();
    if (!mounted) {
      return;
    }
    setState(() {
      _message = '基础数据已刷新。';
      _errorMessage = widget.controller.errorMessage;
    });
  }

  PlanSummary? _currentPlan() {
    final subscription = widget.controller.subscription;
    if (subscription == null) {
      return null;
    }
    for (final plan in widget.controller.plans) {
      if (plan.id == subscription.planId) {
        return plan;
      }
    }
    return null;
  }

  String _subscriptionStatusLabel() {
    final subscription = widget.controller.subscription;
    if (subscription == null) {
      return '未开通';
    }
    if (subscription.status == 'active') {
      return '生效中';
    }
    return subscription.status;
  }

  String _dateLabel(DateTime? value) {
    if (value == null) {
      return '-';
    }
    return '${value.year.toString().padLeft(4, '0')}-'
        '${value.month.toString().padLeft(2, '0')}-'
        '${value.day.toString().padLeft(2, '0')}';
  }

  Widget _buildCameraAssistSettings(BuildContext context) {
    return Column(
      children: <Widget>[
        _SettingsSwitchTile(
          icon: Icons.accessibility_new_outlined,
          title: '默认显示人体框',
          subtitle: '进入拍摄页后实时人物框默认打开。',
          value: _showBodyBoxDefault,
          onChanged: (value) => _setBoolPreference(
            'overlay.show_body_box',
            value,
            (next) => _showBodyBoxDefault = next,
          ),
        ),
        _SettingsSwitchTile(
          icon: Icons.account_tree_outlined,
          title: '默认显示骨架线',
          subtitle: '实时人体关键点和骨架线默认打开。',
          value: _showSkeletonDefault,
          onChanged: (value) => _setBoolPreference(
            'overlay.show_skeleton',
            value,
            (next) => _showSkeletonDefault = next,
          ),
        ),
        _SettingsSwitchTile(
          icon: Icons.crop_free_outlined,
          title: '默认显示模板框',
          subtitle: '选中模板后显示模板人物外框。',
          value: _showTemplateBoxDefault,
          onChanged: (value) => _setBoolPreference(
            'overlay.show_template_box',
            value,
            (next) => _showTemplateBoxDefault = next,
          ),
        ),
        _SettingsSwitchTile(
          icon: Icons.schema_outlined,
          title: '默认显示模板线',
          subtitle: '选中模板后显示模板骨架线和构图参考线。',
          value: _showTemplateLineDefault,
          onChanged: (value) => _setBoolPreference(
            'overlay.show_template_line',
            value,
            (next) => _showTemplateLineDefault = next,
          ),
        ),
        _SettingsSwitchTile(
          icon: Icons.center_focus_weak_outlined,
          title: '显示中心点',
          subtitle: '显示肩部或人脸中心点，便于自动跟随对齐。',
          value: _showCenterPointDefault,
          onChanged: (value) => _setBoolPreference(
            'overlay.show_center_point',
            value,
            (next) => _showCenterPointDefault = next,
          ),
        ),
      ],
    );
  }

  Widget _buildCameraDefaultSettings(BuildContext context) {
    return Column(
      children: <Widget>[
        _SettingsChoiceGroup(
          title: '默认拍摄模式',
          options: const <_SettingsChoiceOption>[
            _SettingsChoiceOption(value: 'normal', label: '正常拍摄'),
            _SettingsChoiceOption(value: 'template_guided', label: '模板构图'),
            _SettingsChoiceOption(value: 'ai_burst', label: 'AI 连拍'),
            _SettingsChoiceOption(value: 'background', label: '背景锁定'),
          ],
          value: _defaultShootMode,
          onChanged: (value) => _setStringPreference(
            'camera.default_shoot_mode',
            value,
            (next) => _defaultShootMode = next,
          ),
        ),
        _SettingsChoiceGroup(
          title: '默认镜头',
          options: const <_SettingsChoiceOption>[
            _SettingsChoiceOption(value: 'back', label: '后置'),
            _SettingsChoiceOption(value: 'front', label: '前置'),
            _SettingsChoiceOption(value: 'last', label: '沿用上次'),
          ],
          value: _preferredCameraLens,
          onChanged: (value) => _setStringPreference(
            'camera.preferred_lens',
            value,
            (next) => _preferredCameraLens = next,
          ),
        ),
        _SettingsSwitchTile(
          icon: Icons.screen_rotation_alt_outlined,
          title: '允许横屏拍摄',
          subtitle: '拍摄页允许横屏预览和横屏操作。',
          value: _enableLandscapeCapture,
          onChanged: (value) => _setBoolPreference(
            'camera.enable_landscape',
            value,
            (next) => _enableLandscapeCapture = next,
          ),
        ),
        _SettingsSwitchTile(
          icon: Icons.flip_camera_android_outlined,
          title: '默认镜像预览',
          subtitle: '只影响预览习惯，不改变保存照片方向。',
          value: _mirrorPreviewDefault,
          onChanged: (value) => _setBoolPreference(
            'camera.mirror_preview',
            value,
            (next) => _mirrorPreviewDefault = next,
          ),
        ),
        _SettingsSwitchTile(
          icon: Icons.auto_fix_high_outlined,
          title: '自动选择可用模板',
          subtitle: '进入拍摄页时自动选择第一个可用人物模板。',
          value: _autoSelectTemplate,
          onChanged: (value) => _setBoolPreference(
            'template.auto_select',
            value,
            (next) => _autoSelectTemplate = next,
          ),
        ),
      ],
    );
  }

  Widget _buildRecognitionSettings(BuildContext context) {
    return Column(
      children: <Widget>[
        _SettingsSliderTile(
          title: '实时识别间隔',
          subtitle: '手机端人体识别帧间隔，越低越实时但越耗电。',
          value: _poseFrameIntervalMs,
          min: 50,
          max: 300,
          divisions: 25,
          valueLabel: '${_poseFrameIntervalMs.round()} ms',
          onChanged: (value) => _setDoublePreference(
            'camera.pose_frame_interval_ms',
            value,
            (next) => _poseFrameIntervalMs = next,
          ),
        ),
        _SettingsSliderTile(
          title: '丢失清空阈值',
          subtitle: '连续多少帧没识别到人体后清空实时框线。',
          value: _poseMissesBeforeClear,
          min: 1,
          max: 12,
          divisions: 11,
          valueLabel: '${_poseMissesBeforeClear.round()} 帧',
          onChanged: (value) => _setDoublePreference(
            'camera.pose_misses_before_clear',
            value,
            (next) => _poseMissesBeforeClear = next,
          ),
        ),
        _SettingsSliderTile(
          title: '人体框平滑',
          subtitle: '实时人体框的平滑系数，越高越跟手，越低越稳。',
          value: _liveBoxSmoothing,
          min: 0.05,
          max: 0.8,
          divisions: 15,
          valueLabel: _liveBoxSmoothing.toStringAsFixed(2),
          onChanged: (value) => _setDoublePreference(
            'camera.live_box_smoothing',
            value,
            (next) => _liveBoxSmoothing = next,
          ),
        ),
        _SettingsSliderTile(
          title: '关键点平滑',
          subtitle: '实时骨架关键点的平滑系数。',
          value: _livePointSmoothing,
          min: 0.05,
          max: 0.8,
          divisions: 15,
          valueLabel: _livePointSmoothing.toStringAsFixed(2),
          onChanged: (value) => _setDoublePreference(
            'camera.live_point_smoothing',
            value,
            (next) => _livePointSmoothing = next,
          ),
        ),
        _SettingsSliderTile(
          title: 'AI 连拍最少张数',
          subtitle: 'AI 连拍模式至少积累多少张照片后允许分析。',
          value: _aiBurstMinPhotos,
          min: 2,
          max: 8,
          divisions: 6,
          valueLabel: '${_aiBurstMinPhotos.round()} 张',
          onChanged: (value) => _setDoublePreference(
            'camera.ai_burst_min_photos',
            value,
            (next) => _aiBurstMinPhotos = next,
          ),
        ),
      ],
    );
  }

  Widget _buildRecordingSettings(BuildContext context) {
    return Column(
      children: <Widget>[
        _SettingsSwitchTile(
          icon: Icons.photo_library_outlined,
          title: '照片保存到手机相册',
          subtitle: '拍摄和设备联动抓拍后优先写入系统相册。',
          value: _savePhotosToGallery,
          onChanged: (value) => _setBoolPreference(
            'recording.save_photos_to_gallery',
            value,
            (next) => _savePhotosToGallery = next,
          ),
        ),
        _SettingsSwitchTile(
          icon: Icons.video_library_outlined,
          title: '视频保存到手机相册',
          subtitle: '停止录像后保存到本机相册，不强制写入历史会话。',
          value: _saveVideosToGallery,
          onChanged: (value) => _setBoolPreference(
            'recording.save_videos_to_gallery',
            value,
            (next) => _saveVideosToGallery = next,
          ),
        ),
        _SettingsSwitchTile(
          icon: Icons.fiber_manual_record_outlined,
          title: '显示录像红点和时长',
          subtitle: '录像按钮显示红点，按钮文字显示当前录像时长。',
          value: _showRecordingTimer,
          onChanged: (value) => _setBoolPreference(
            'recording.show_timer',
            value,
            (next) => _showRecordingTimer = next,
          ),
        ),
        _SettingsSwitchTile(
          icon: Icons.cloud_upload_outlined,
          title: '照片写入历史记录',
          subtitle: '拍照后上传服务器并写入历史会话。',
          value: _uploadPhotosToHistory,
          onChanged: (value) => _setBoolPreference(
            'recording.upload_photos_to_history',
            value,
            (next) => _uploadPhotosToHistory = next,
          ),
        ),
        _SettingsSwitchTile(
          icon: Icons.video_settings_outlined,
          title: '视频写入历史记录',
          subtitle: '默认关闭；当前视频主要保存到手机相册。',
          value: _uploadVideosToHistory,
          onChanged: (value) => _setBoolPreference(
            'recording.upload_videos_to_history',
            value,
            (next) => _uploadVideosToHistory = next,
          ),
        ),
        _SettingsSwitchTile(
          icon: Icons.notifications_active_outlined,
          title: '显示保存结果提示',
          subtitle: '拍照、录像、相册保存完成后显示顶部提示。',
          value: _showSaveResultBanner,
          onChanged: (value) => _setBoolPreference(
            'recording.show_save_banner',
            value,
            (next) => _showSaveResultBanner = next,
          ),
        ),
        _SettingsSliderTile(
          title: '录像预览刷新间隔',
          subtitle: '设备联动录像中用于保持画面运动的预览刷新频率。',
          value: _recordingPreviewFrameMs,
          min: 60,
          max: 500,
          divisions: 22,
          valueLabel: '${_recordingPreviewFrameMs.round()} ms',
          onChanged: (value) => _setDoublePreference(
            'recording.preview_frame_ms',
            value,
            (next) => _recordingPreviewFrameMs = next,
          ),
        ),
      ],
    );
  }

  Widget _buildTemplateRecognitionSettings(BuildContext context) {
    return Column(
      children: <Widget>[
        _SettingsChoiceGroup(
          title: '模板识别来源',
          options: const <_SettingsChoiceOption>[
            _SettingsChoiceOption(value: 'backend', label: '服务器识别'),
            _SettingsChoiceOption(value: 'local', label: '手机本地识别'),
            _SettingsChoiceOption(value: 'ask', label: '每次询问'),
          ],
          value: _templateRecognitionMode,
          onChanged: (value) => _setStringPreference(
            'template.recognition_mode',
            value,
            (next) => _templateRecognitionMode = next,
          ),
        ),
        _SettingsSwitchTile(
          icon: Icons.view_in_ar_outlined,
          title: '上传后自动选中模板',
          subtitle: '新建模板后在拍摄和设备联动里优先使用它。',
          value: _autoSelectTemplate,
          onChanged: (value) => _setBoolPreference(
            'template.auto_select',
            value,
            (next) => _autoSelectTemplate = next,
          ),
        ),
      ],
    );
  }

  Widget _buildDevicePreferenceSettings(BuildContext context) {
    return Column(
      children: <Widget>[
        _SettingsSwitchTile(
          icon: Icons.mobile_screen_share_outlined,
          title: '打开会话时自动启动手机推流',
          subtitle: '设备联动使用手机摄像头画面，并把关键点目标送给树莓派。',
          value: _autoStartMobilePush,
          onChanged: (value) => _setBoolPreference(
            'device.auto_start_mobile_push',
            value,
            (next) => _autoStartMobilePush = next,
          ),
        ),
        _SettingsSwitchTile(
          icon: Icons.refresh_outlined,
          title: '自动刷新设备状态',
          subtitle: '设备联动页定时同步云台、AI、手势和推流状态。',
          value: _deviceAutoRefresh,
          onChanged: (value) => _setBoolPreference(
            'device.auto_refresh',
            value,
            (next) => _deviceAutoRefresh = next,
          ),
        ),
        _SettingsSwitchTile(
          icon: Icons.gamepad_outlined,
          title: '显示悬浮摇杆',
          subtitle: '进入设备联动时显示可拖动的手动控制摇杆。',
          value: _showDeviceJoystick,
          onChanged: (value) => _setBoolPreference(
            'device.show_joystick',
            value,
            (next) => _showDeviceJoystick = next,
          ),
        ),
        _SettingsSwitchTile(
          icon: Icons.swap_horiz_outlined,
          title: '横屏控制放左侧',
          subtitle: '横屏时把摇杆和主要控制放到左手侧。',
          value: _landscapeControlsLeft,
          onChanged: (value) => _setBoolPreference(
            'device.landscape_left',
            value,
            (next) => _landscapeControlsLeft = next,
          ),
        ),
        _SettingsChoiceGroup(
          title: '自动跟随目标',
          options: const <_SettingsChoiceOption>[
            _SettingsChoiceOption(value: 'shoulders', label: '肩部中心'),
            _SettingsChoiceOption(value: 'face', label: '人脸中心'),
          ],
          value: _followTargetMode,
          onChanged: (value) => _setStringPreference(
            'device.follow_target_mode',
            value,
            (next) => _followTargetMode = next,
          ),
        ),
        _SettingsChoiceGroup(
          title: '会话启动模式',
          options: const <_SettingsChoiceOption>[
            _SettingsChoiceOption(value: 'MANUAL', label: '手动控制'),
            _SettingsChoiceOption(value: 'AUTO_TRACK', label: '自动跟随'),
            _SettingsChoiceOption(value: 'SMART_COMPOSE', label: '模板构图'),
          ],
          value: _deviceStartMode,
          onChanged: (value) => _setStringPreference(
            'device.start_mode',
            value,
            (next) => _deviceStartMode = next,
          ),
        ),
        _SettingsSliderTile(
          title: '舵机灵敏度',
          subtitle: '同时影响手动控制、自动跟随和模板构图模式的响应速度。',
          value: _sensitivity,
          min: 0.3,
          max: 2.0,
          divisions: 17,
          valueLabel: _sensitivity.toStringAsFixed(1),
          onChanged: (value) => _setDoublePreference(
            'device.sensitivity',
            value,
            (next) => _sensitivity = next,
          ),
        ),
        _SettingsSliderTile(
          title: '手动移动重复间隔',
          subtitle: '长按方向键时发送云台移动指令的间隔。',
          value: _manualMoveRepeatMs,
          min: 60,
          max: 300,
          divisions: 24,
          valueLabel: '${_manualMoveRepeatMs.round()} ms',
          onChanged: (value) => _setDoublePreference(
            'device.manual_move_repeat_ms',
            value,
            (next) => _manualMoveRepeatMs = next,
          ),
        ),
        _SettingsSliderTile(
          title: '状态轮询间隔',
          subtitle: '设备联动页普通状态刷新频率。',
          value: _devicePollSeconds,
          min: 1,
          max: 10,
          divisions: 9,
          valueLabel: '${_devicePollSeconds.round()} 秒',
          onChanged: (value) => _setDoublePreference(
            'device.poll_seconds',
            value,
            (next) => _devicePollSeconds = next,
          ),
        ),
        _SettingsSliderTile(
          title: '倒计时轮询间隔',
          subtitle: '手势倒计时和 AI 倒计时时的刷新间隔。',
          value: _countdownPollSeconds,
          min: 0.5,
          max: 3,
          divisions: 5,
          valueLabel: '${_countdownPollSeconds.toStringAsFixed(1)} 秒',
          onChanged: (value) => _setDoublePreference(
            'device.countdown_poll_seconds',
            value,
            (next) => _countdownPollSeconds = next,
          ),
        ),
      ],
    );
  }

  Widget _buildMobilePushSettings(BuildContext context) {
    return Column(
      children: <Widget>[
        _SettingsChoiceGroup(
          title: '手机推流方式',
          options: const <_SettingsChoiceOption>[
            _SettingsChoiceOption(value: 'websocket', label: 'WebSocket/NV21'),
            _SettingsChoiceOption(value: 'webrtc', label: 'WebRTC'),
            _SettingsChoiceOption(value: 'auto', label: '自动选择'),
          ],
          value: _mobilePushTransport,
          onChanged: (value) => _setStringPreference(
            'push.transport',
            value,
            (next) => _mobilePushTransport = next,
          ),
        ),
        _SettingsChoiceGroup(
          title: '推流默认镜头',
          options: const <_SettingsChoiceOption>[
            _SettingsChoiceOption(value: 'back', label: '后置'),
            _SettingsChoiceOption(value: 'front', label: '前置'),
            _SettingsChoiceOption(value: 'last', label: '沿用上次'),
          ],
          value: _mobilePushCameraLens,
          onChanged: (value) => _setStringPreference(
            'push.camera_lens',
            value,
            (next) => _mobilePushCameraLens = next,
          ),
        ),
        _SettingsSwitchTile(
          icon: Icons.video_call_outlined,
          title: '优先尝试 WebRTC',
          subtitle: '开启后设备联动优先尝试低延迟 WebRTC 推流。',
          value: _preferWebRtcPush,
          onChanged: (value) => _setBoolPreference(
            'push.prefer_webrtc',
            value,
            (next) => _preferWebRtcPush = next,
          ),
        ),
        _SettingsSwitchTile(
          icon: Icons.sync_problem_outlined,
          title: '允许 HTTP JPEG 兜底',
          subtitle: 'WebSocket 不可用时切换兼容推流。',
          value: _allowHttpPushFallback,
          onChanged: (value) => _setBoolPreference(
            'push.allow_http_fallback',
            value,
            (next) => _allowHttpPushFallback = next,
          ),
        ),
        _SettingsSliderTile(
          title: '推流帧间隔',
          subtitle: '手机向树莓派发送画面帧的最小间隔。',
          value: _mobilePushFrameMs,
          min: 33,
          max: 250,
          divisions: 31,
          valueLabel: '${_mobilePushFrameMs.round()} ms',
          onChanged: (value) => _setDoublePreference(
            'push.frame_ms',
            value,
            (next) => _mobilePushFrameMs = next,
          ),
        ),
        _SettingsSliderTile(
          title: 'HTTP 兜底帧间隔',
          subtitle: '兼容推流时 JPEG 帧的发送间隔。',
          value: _mobilePushHttpFrameMs,
          min: 100,
          max: 800,
          divisions: 28,
          valueLabel: '${_mobilePushHttpFrameMs.round()} ms',
          onChanged: (value) => _setDoublePreference(
            'push.http_frame_ms',
            value,
            (next) => _mobilePushHttpFrameMs = next,
          ),
        ),
        _SettingsSliderTile(
          title: '目标跟随发送间隔',
          subtitle: '手机端向树莓派发送肩部/人脸中心点的间隔。',
          value: _mobileTrackTargetMs,
          min: 60,
          max: 500,
          divisions: 22,
          valueLabel: '${_mobileTrackTargetMs.round()} ms',
          onChanged: (value) => _setDoublePreference(
            'push.track_target_ms',
            value,
            (next) => _mobileTrackTargetMs = next,
          ),
        ),
        _SettingsSliderTile(
          title: '推流连接超时',
          subtitle: 'WebSocket 推流连接等待超时时间。',
          value: _mobilePushSocketTimeoutSeconds,
          min: 3,
          max: 20,
          divisions: 17,
          valueLabel: '${_mobilePushSocketTimeoutSeconds.round()} 秒',
          onChanged: (value) => _setDoublePreference(
            'push.socket_timeout_seconds',
            value,
            (next) => _mobilePushSocketTimeoutSeconds = next,
          ),
        ),
        _SettingsSliderTile(
          title: '推流识别丢失阈值',
          subtitle: '连续多少帧没有人体后清空设备联动实时框线。',
          value: _mobilePoseMissesBeforeClear,
          min: 1,
          max: 16,
          divisions: 15,
          valueLabel: '${_mobilePoseMissesBeforeClear.round()} 帧',
          onChanged: (value) => _setDoublePreference(
            'push.pose_misses_before_clear',
            value,
            (next) => _mobilePoseMissesBeforeClear = next,
          ),
        ),
      ],
    );
  }

  Widget _buildDeviceOverlaySettings(BuildContext context) {
    return Column(
      children: <Widget>[
        _SettingsSwitchTile(
          icon: Icons.layers_outlined,
          title: '设备联动画面辅助总开关',
          subtitle: '关闭后设备联动页不显示实时和模板叠加。',
          value: _deviceOverlayEnabled,
          onChanged: (value) => _setBoolPreference(
            'device_overlay.enabled',
            value,
            (next) => _deviceOverlayEnabled = next,
          ),
        ),
        _SettingsSwitchTile(
          icon: Icons.accessibility_new_outlined,
          title: '实时人体框',
          subtitle: '设备联动主画面显示手机识别到的人体框。',
          value: _deviceShowLivePersonBox,
          onChanged: (value) => _setBoolPreference(
            'device_overlay.live_person_box',
            value,
            (next) => _deviceShowLivePersonBox = next,
          ),
        ),
        _SettingsSwitchTile(
          icon: Icons.account_tree_outlined,
          title: '实时骨架线',
          subtitle: '显示手机端实时人体骨架线。',
          value: _deviceShowLiveSkeleton,
          onChanged: (value) => _setBoolPreference(
            'device_overlay.live_skeleton',
            value,
            (next) => _deviceShowLiveSkeleton = next,
          ),
        ),
        _SettingsSwitchTile(
          icon: Icons.back_hand_outlined,
          title: '手部骨架',
          subtitle: '显示设备侧返回的手部关键点和手势辅助。',
          value: _deviceShowLiveHands,
          onChanged: (value) => _setBoolPreference(
            'device_overlay.live_hands',
            value,
            (next) => _deviceShowLiveHands = next,
          ),
        ),
        _SettingsSwitchTile(
          icon: Icons.crop_free_outlined,
          title: '模板框',
          subtitle: '显示当前模板的人体外框。',
          value: _deviceShowTemplateBox,
          onChanged: (value) => _setBoolPreference(
            'device_overlay.template_box',
            value,
            (next) => _deviceShowTemplateBox = next,
          ),
        ),
        _SettingsSwitchTile(
          icon: Icons.schema_outlined,
          title: '模板骨架线',
          subtitle: '显示模板人物骨架和构图参考线。',
          value: _deviceShowTemplateSkeleton,
          onChanged: (value) => _setBoolPreference(
            'device_overlay.template_skeleton',
            value,
            (next) => _deviceShowTemplateSkeleton = next,
          ),
        ),
        _SettingsSwitchTile(
          icon: Icons.center_focus_weak_outlined,
          title: '锁定位框/中心点',
          subtitle: '显示 AI 推荐框、肩部中心或人脸中心。',
          value: _deviceShowAiLockBox,
          onChanged: (value) =>
              _setBoolPreference('device_overlay.ai_lock_box', value, (next) {
                _deviceShowAiLockBox = next;
                _backgroundLockEnabled = next;
              }),
        ),
      ],
    );
  }

  Widget _buildGestureSettings(BuildContext context) {
    return Column(
      children: <Widget>[
        _SettingsSwitchTile(
          icon: Icons.pan_tool_alt_outlined,
          title: '张手握拳抓拍',
          subtitle: '检测到张手再握拳后触发倒计时抓拍。',
          value: _gestureCaptureEnabled,
          onChanged: (value) => _setBoolPreference(
            'gesture.capture_enabled',
            value,
            (next) => _gestureCaptureEnabled = next,
          ),
        ),
        _SettingsSwitchTile(
          icon: Icons.check_circle_outline,
          title: 'OK 手势强制抓拍',
          subtitle: '无需模板构图 ready，识别到 OK 手势也可抓拍。',
          value: _gestureOkCaptureEnabled,
          onChanged: (value) => _setBoolPreference(
            'gesture.ok_capture_enabled',
            value,
            (next) => _gestureOkCaptureEnabled = next,
          ),
        ),
        _SettingsSwitchTile(
          icon: Icons.auto_awesome_outlined,
          title: '抓拍后设备本地 AI 分析',
          subtitle: '手势抓拍完成后自动发起设备侧分析。',
          value: _gestureAnalyzeAfterCapture,
          onChanged: (value) => _setBoolPreference(
            'gesture.analyze_after_capture',
            value,
            (next) => _gestureAnalyzeAfterCapture = next,
          ),
        ),
        _SettingsSwitchTile(
          icon: Icons.rule_folder_outlined,
          title: '张手握拳需要模板 ready',
          subtitle: '开启后只有构图接近模板时才响应张手握拳抓拍。',
          value: _gestureRequireTemplateReady,
          onChanged: (value) => _setBoolPreference(
            'gesture.require_template_ready',
            value,
            (next) => _gestureRequireTemplateReady = next,
          ),
        ),
        _SettingsSwitchTile(
          icon: Icons.photo_library_outlined,
          title: '手势抓拍自动保存相册',
          subtitle: '设备侧手势抓拍完成后自动写入手机相册。',
          value: _gestureAutoSaveToGallery,
          onChanged: (value) => _setBoolPreference(
            'gesture.auto_save_to_gallery',
            value,
            (next) => _gestureAutoSaveToGallery = next,
          ),
        ),
        _SettingsSliderTile(
          title: '手势抓拍倒计时',
          subtitle: '识别到有效手势后等待几秒再抓拍。',
          value: _gestureCountdownSeconds,
          min: 0,
          max: 8,
          divisions: 8,
          valueLabel: '${_gestureCountdownSeconds.round()} 秒',
          onChanged: (value) => _setDoublePreference(
            'gesture.countdown_seconds',
            value,
            (next) => _gestureCountdownSeconds = next,
          ),
        ),
      ],
    );
  }

  Widget _buildAiCompositionSettings(BuildContext context) {
    return Column(
      children: <Widget>[
        _SettingsSwitchTile(
          icon: Icons.photo_camera_back_outlined,
          title: '拍照后自动分析',
          subtitle: '普通拍照后自动发起服务器 AI 分析。',
          value: _runAiAfterPhotoCapture,
          onChanged: (value) => _setBoolPreference(
            'ai.run_after_photo_capture',
            value,
            (next) => _runAiAfterPhotoCapture = next,
          ),
        ),
        _SettingsSwitchTile(
          icon: Icons.video_camera_back_outlined,
          title: '录像后自动分析',
          subtitle: '录像结束后自动发起服务器 AI 分析。',
          value: _runAiAfterVideoCapture,
          onChanged: (value) => _setBoolPreference(
            'ai.run_after_video_capture',
            value,
            (next) => _runAiAfterVideoCapture = next,
          ),
        ),
        _SettingsSwitchTile(
          icon: Icons.lock_outline,
          title: '显示背景锁定框',
          subtitle: '背景锁定分析返回锁定框后，决定是否显示在画面上。',
          value: _backgroundLockEnabled,
          onChanged: (value) =>
              _setBoolPreference('device_overlay.ai_lock_box', value, (next) {
                _backgroundLockEnabled = next;
                _deviceShowAiLockBox = next;
              }),
        ),
        _SettingsSliderTile(
          title: '水平扫描范围',
          subtitle: '自动找角度时左右扫描的最大角度。',
          value: _panScanRange,
          min: 4,
          max: 45,
          divisions: 41,
          valueLabel: '${_panScanRange.round()}°',
          onChanged: (value) => _setDoublePreference(
            'ai.pan_scan_range',
            value,
            (next) => _panScanRange = next,
          ),
        ),
        _SettingsSliderTile(
          title: '俯仰扫描范围',
          subtitle: '自动找角度时上下扫描的最大角度。',
          value: _tiltScanRange,
          min: 4,
          max: 30,
          divisions: 26,
          valueLabel: '${_tiltScanRange.round()}°',
          onChanged: (value) => _setDoublePreference(
            'ai.tilt_scan_range',
            value,
            (next) => _tiltScanRange = next,
          ),
        ),
        _SettingsSliderTile(
          title: '扫描步进',
          subtitle: '候选角度之间的间隔，越小越细但更慢。',
          value: _scanStepDegrees,
          min: 1,
          max: 10,
          divisions: 9,
          valueLabel: '${_scanStepDegrees.round()}°',
          onChanged: (value) => _setDoublePreference(
            'ai.scan_step_degrees',
            value,
            (next) => _scanStepDegrees = next,
          ),
        ),
        _SettingsSliderTile(
          title: 'AI 启动倒计时',
          subtitle: '点击自动找角度或背景锁定后，先倒计时几秒再正式开始扫描。',
          value: _aiStartDelaySeconds,
          min: 0,
          max: 30,
          divisions: 30,
          valueLabel: '${_aiStartDelaySeconds.round()} 秒',
          onChanged: (value) => _setDoublePreference(
            'ai.start_delay_seconds',
            value,
            (next) => _aiStartDelaySeconds = next,
          ),
        ),
        _SettingsSliderTile(
          title: '稳定等待',
          subtitle: '每个候选角度拍摄前等待云台稳定的时间。',
          value: _settleSeconds,
          min: 0.2,
          max: 2.5,
          divisions: 23,
          valueLabel: '${_settleSeconds.toStringAsFixed(1)} 秒',
          onChanged: (value) => _setDoublePreference(
            'ai.settle_seconds',
            value,
            (next) => _settleSeconds = next,
          ),
        ),
        _SettingsSliderTile(
          title: '候选数量',
          subtitle: '自动构图最多比较多少个角度。',
          value: _candidateCount,
          min: 3,
          max: 12,
          divisions: 9,
          valueLabel: '${_candidateCount.round()} 个',
          onChanged: (value) => _setDoublePreference(
            'ai.candidate_count',
            value,
            (next) => _candidateCount = next,
          ),
        ),
      ],
    );
  }

  Widget _buildTargetPointSettings(BuildContext context) {
    return Column(
      children: <Widget>[
        _SettingsChoiceGroup(
          title: '默认推荐跟随点',
          options: const <_SettingsChoiceOption>[
            _SettingsChoiceOption(value: 'shoulders', label: '肩部中心'),
            _SettingsChoiceOption(value: 'face', label: '人脸中心'),
          ],
          value: _followTargetMode,
          onChanged: (value) => _setStringPreference(
            'device.follow_target_mode',
            value,
            (next) => _followTargetMode = next,
          ),
        ),
        _SettingsSwitchTile(
          icon: Icons.center_focus_weak_outlined,
          title: '显示目标中心点',
          subtitle: '在实时画面和模板上显示当前跟随目标点。',
          value: _showTargetCenterPoint,
          onChanged: (value) => _setBoolPreference(
            'ai.show_target_center',
            value,
            (next) => _showTargetCenterPoint = next,
          ),
        ),
        _SettingsSwitchTile(
          icon: Icons.crop_square_outlined,
          title: '显示 AI 推荐框',
          subtitle: '服务器或设备返回推荐构图框时显示在画面上。',
          value: _showAiRecommendationBox,
          onChanged: (value) => _setBoolPreference(
            'ai.show_recommendation_box',
            value,
            (next) => _showAiRecommendationBox = next,
          ),
        ),
      ],
    );
  }

  Widget _buildArchitectureSettings(BuildContext context) {
    return const _SettingsInfoGrid(
      items: <({String label, String value})>[
        (label: '主画面', value: '手机摄像头'),
        (label: '云台控制', value: '树莓派'),
        (label: '视觉叠加', value: '手机端绘制'),
        (label: 'AI 与数据', value: '服务器统一管理'),
      ],
    );
  }

  List<_SettingsCategoryConfig> _categories() {
    final currentPlan = _currentPlan();
    final subscription = widget.controller.subscription;
    final plans = widget.controller.plans;
    return <_SettingsCategoryConfig>[
      _SettingsCategoryConfig(
        icon: Icons.workspace_premium_outlined,
        title: '账号与订阅',
        subtitle: currentPlan == null ? '查看套餐、额度和账号状态。' : currentPlan.name,
        keywords: '账号 用户 当前订阅 套餐 额度 续费 购买 plan subscription quota',
        sections: <_SettingsSectionConfig>[
          _SettingsSectionConfig(
            title: '当前订阅',
            subtitle: _subscriptionStatusLabel(),
            keywords: '当前订阅 套餐 额度 续费 购买 自动续费',
            builder: (context) => Column(
              children: <Widget>[
                _SettingsInfoGrid(
                  items: <({String label, String value})>[
                    (label: '状态', value: _subscriptionStatusLabel()),
                    (label: '套餐', value: currentPlan?.name ?? '未开通'),
                    (
                      label: '拍摄额度',
                      value:
                          '${subscription?.captureQuota ?? currentPlan?.captureQuota ?? '-'}',
                    ),
                    (
                      label: 'AI 额度',
                      value:
                          '${subscription?.aiTaskQuota ?? currentPlan?.aiTaskQuota ?? '-'}',
                    ),
                    (label: '开始时间', value: _dateLabel(subscription?.startedAt)),
                    (label: '到期时间', value: _dateLabel(subscription?.expiresAt)),
                  ],
                ),
                const SizedBox(height: 10),
                _SettingsActionButton(
                  icon: Icons.receipt_long_outlined,
                  label: '查看订阅与套餐详情',
                  onTap: () => _openPlanDetails(
                    initialPlanId: widget.controller.subscription?.planId,
                  ),
                ),
              ],
            ),
          ),
          _SettingsSectionConfig(
            title: '可选套餐',
            subtitle: plans.isEmpty
                ? '暂无套餐数据'
                : '共 ${plans.length} 个套餐，已从首页收起。',
            keywords: '可选套餐 购买 切换 套餐列表 price billing',
            builder: (context) => Column(
              children: plans.isEmpty
                  ? const <Widget>[
                      _SettingsHintBlock(message: '暂无套餐数据，确认后端计划数据或点击刷新基础数据。'),
                    ]
                  : plans
                        .map(
                          (plan) => _PlanSettingsRow(
                            plan: plan,
                            selected: subscription?.planId == plan.id,
                            onTap: () =>
                                _openPlanDetails(initialPlanId: plan.id),
                          ),
                        )
                        .toList(growable: false),
            ),
          ),
        ],
      ),
      _SettingsCategoryConfig(
        icon: Icons.view_in_ar_outlined,
        title: '模板管理',
        subtitle: '上传、刷新、删除人物模板。',
        keywords: '模板 模板管理 上传 删除 刷新 人物 姿势 构图 template',
        sections: <_SettingsSectionConfig>[
          _SettingsSectionConfig(
            title: '模板操作',
            subtitle: '创建人物模板或同步模板列表。',
            keywords: '创建模板 新增模板 上传图片 刷新模板',
            builder: (context) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: <Widget>[
                    _SettingsActionButton(
                      icon: Icons.add_photo_alternate_outlined,
                      label: _isBusy ? '创建中' : '创建模板',
                      onTap: _isBusy ? null : _createTemplate,
                    ),
                    _SettingsActionButton(
                      icon: Icons.refresh_outlined,
                      label: _isLoadingTemplates ? '刷新中' : '刷新模板',
                      onTap: _isBusy || _isLoadingTemplates
                          ? null
                          : _loadTemplates,
                    ),
                  ],
                ),
                if (_isLoadingTemplates) ...<Widget>[
                  const SizedBox(height: 12),
                  const LinearProgressIndicator(minHeight: 3),
                ],
              ],
            ),
          ),
          _SettingsSectionConfig(
            title: '模板列表',
            subtitle: _templates.isEmpty ? '暂无模板' : '${_templates.length} 个模板',
            keywords: '模板列表 删除 推荐 默认 后台模板',
            builder: (context) {
              if (!_isLoadingTemplates && _templates.isEmpty) {
                return const _SettingsHintBlock(
                  message: '暂无模板。上传一张人物照片后，会在拍摄和设备联动里用于构图辅助。',
                );
              }
              return Column(
                children: _templates
                    .map(
                      (template) => _TemplateSettingsRow(
                        template: template,
                        onDelete: _isBusy || template.isRecommendedDefault
                            ? null
                            : () => _deleteTemplate(template),
                      ),
                    )
                    .toList(growable: false),
              );
            },
          ),
          _SettingsSectionConfig(
            title: '模板识别策略',
            subtitle: '上传模板时的识别来源和自动选中策略。',
            keywords:
                '模板识别 服务器 本地 每次询问 自动选中 template recognition local backend',
            builder: _buildTemplateRecognitionSettings,
          ),
        ],
      ),
      _SettingsCategoryConfig(
        icon: Icons.camera_alt_outlined,
        title: '拍摄设置',
        subtitle: '把低频拍摄参数收在这里，拍摄页只保留常用开关。',
        keywords: '拍摄 相机 录像 镜像 模板线 人体框 骨架线 相册 camera video',
        sections: <_SettingsSectionConfig>[
          _SettingsSectionConfig(
            title: '拍摄入口',
            subtitle: '进入拍摄页或打开本机相册。',
            keywords: '开始拍摄 拍照 录像 相册 图库',
            builder: (context) => Wrap(
              spacing: 10,
              runSpacing: 10,
              children: <Widget>[
                _SettingsActionButton(
                  icon: Icons.camera_alt_outlined,
                  label: '开始拍摄',
                  onTap: _openCameraPage,
                ),
                _SettingsActionButton(
                  icon: Icons.photo_library_outlined,
                  label: '打开本机相册',
                  onTap: _openGallery,
                ),
              ],
            ),
          ),
          _SettingsSectionConfig(
            title: '拍摄默认值',
            subtitle: '默认模式、默认镜头、横屏和镜像预览。',
            keywords: '默认拍摄 默认镜头 后置 前置 横屏 镜像 普通拍摄 模板构图 AI连拍 背景锁定',
            builder: _buildCameraDefaultSettings,
          ),
          _SettingsSectionConfig(
            title: '取景辅助',
            subtitle: '模板线、人体框、骨架线等显示项。',
            keywords: '模板线 模板框 人体框 骨架线 中心点 取景辅助 overlay',
            builder: _buildCameraAssistSettings,
          ),
          _SettingsSectionConfig(
            title: '实时识别',
            subtitle: '人体识别频率、清空阈值和平滑参数。',
            keywords: '实时识别 人体识别 关键点 清空阈值 平滑 AI连拍 帧间隔 pose smoothing miss',
            builder: _buildRecognitionSettings,
          ),
          _SettingsSectionConfig(
            title: '录像与保存',
            subtitle: '照片、视频默认保存到手机相册。',
            keywords: '录像 保存 相册 视频 照片 红点 时长',
            builder: _buildRecordingSettings,
          ),
        ],
      ),
      _SettingsCategoryConfig(
        icon: Icons.router_outlined,
        title: '设备联动',
        subtitle: '设备地址、会话、推流和控制习惯。',
        keywords: '设备联动 树莓派 推流 会话 地址 横屏 摇杆 gimbal device',
        sections: <_SettingsSectionConfig>[
          _SettingsSectionConfig(
            title: '设备入口',
            subtitle: '连接树莓派并进入控制页。',
            keywords: '进入设备联动 树莓派 控制 自动跟随',
            builder: (context) => Wrap(
              spacing: 10,
              runSpacing: 10,
              children: <Widget>[
                _SettingsActionButton(
                  icon: Icons.router_outlined,
                  label: '进入设备联动',
                  onTap: _openDeviceLinkPage,
                ),
                _SettingsActionButton(
                  icon: Icons.history_outlined,
                  label: '查看历史记录',
                  onTap: _openHistoryPage,
                ),
              ],
            ),
          ),
          _SettingsSectionConfig(
            title: '连接参数',
            subtitle: widget.controller.serverConfig.deviceApiBaseUrl,
            keywords: '设备地址 API 会话码 视频流 手机推流 WebSocket HTTP',
            builder: (context) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _SettingsInfoGrid(
                  items: <({String label, String value})>[
                    (
                      label: '业务服务器',
                      value: widget.controller.serverConfig.apiBaseUrl,
                    ),
                    (
                      label: '设备地址',
                      value: widget.controller.serverConfig.deviceApiBaseUrl,
                    ),
                    (label: '主画面', value: '手机摄像头'),
                    (label: '视觉叠加', value: '手机端绘制'),
                  ],
                ),
                const SizedBox(height: 10),
                _SettingsActionButton(
                  icon: Icons.settings_ethernet_outlined,
                  label: '修改连接地址',
                  onTap: _openServerConfigPage,
                ),
              ],
            ),
          ),
          _SettingsSectionConfig(
            title: '手机推流',
            subtitle: '推流方式、帧率、兜底方式和目标点发送频率。',
            keywords: '手机推流 WebSocket WebRTC HTTP JPEG NV21 帧率 超时 目标点 自动跟随',
            builder: _buildMobilePushSettings,
          ),
          _SettingsSectionConfig(
            title: '设备画面叠加',
            subtitle: '设备联动页实时框线、模板线和中心点。',
            keywords: '设备叠加 实时人体框 实时骨架线 手部 模板框 模板线 AI锁定框 中心点',
            builder: _buildDeviceOverlaySettings,
          ),
          _SettingsSectionConfig(
            title: '控制偏好',
            subtitle: '摇杆、横屏左右手、跟随灵敏度等参数。',
            keywords: '摇杆 横屏 左手 右手 灵敏度 自动跟随 死区 平滑',
            builder: _buildDevicePreferenceSettings,
          ),
          _SettingsSectionConfig(
            title: '手势抓拍',
            subtitle: '张手握拳、OK 手势和抓拍后分析。',
            keywords: '手势 张手 握拳 OK 抓拍 倒计时 本地AI分析',
            builder: _buildGestureSettings,
          ),
        ],
      ),
      _SettingsCategoryConfig(
        icon: Icons.auto_awesome_outlined,
        title: 'AI 与构图',
        subtitle: '自动找角度、背景锁定和构图推荐。',
        keywords: 'AI 构图 自动找角度 背景锁定 推荐框 中心点',
        sections: <_SettingsSectionConfig>[
          _SettingsSectionConfig(
            title: '自动构图',
            subtitle: '扫描范围、候选数量、等待时间。',
            keywords: '自动找角度 扫描 范围 步进 候选 等待',
            builder: _buildAiCompositionSettings,
          ),
          _SettingsSectionConfig(
            title: '推荐框与中心点',
            subtitle: '肩部中心、人脸中心、AI 推荐框。',
            keywords: '推荐框 肩部中心 人脸中心 中心点 target_box',
            builder: _buildTargetPointSettings,
          ),
        ],
      ),
      _SettingsCategoryConfig(
        icon: Icons.construction_outlined,
        title: '高级与诊断',
        subtitle: '服务状态、缓存、同步和调试信息。',
        keywords: '高级 诊断 服务 缓存 同步 刷新 后端 backend',
        sections: <_SettingsSectionConfig>[
          _SettingsSectionConfig(
            title: '服务状态',
            subtitle: widget.serviceStatus,
            keywords: '服务连接 后端 状态 健康 刷新',
            builder: (context) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _SettingsInfoGrid(
                  items: <({String label, String value})>[
                    (label: '服务连接', value: widget.serviceStatus),
                    (
                      label: '基础数据',
                      value: widget.controller.isRefreshing ? '同步中' : '已加载',
                    ),
                    (
                      label: '错误状态',
                      value: widget.controller.errorMessage ?? '无',
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                _SettingsActionButton(
                  icon: Icons.sync_outlined,
                  label: '刷新基础数据',
                  onTap: widget.controller.isRefreshing
                      ? null
                      : _refreshDashboard,
                ),
              ],
            ),
          ),
          _SettingsSectionConfig(
            title: '设计原则',
            subtitle: '手机负责画面，树莓派负责转动，服务器负责智能。',
            keywords: '架构 原则 手机画面 树莓派转动 服务器智能',
            builder: _buildArchitectureSettings,
          ),
        ],
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final categories = _filteredCategories();
    return Scaffold(
      appBar: AppBar(
        title: const Text('详细设置'),
        actions: <Widget>[
          IconButton(
            tooltip: '刷新',
            onPressed: widget.controller.isRefreshing
                ? null
                : _refreshDashboard,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
          children: <Widget>[
            _SearchField(controller: _searchController),
            if (_message != null) ...<Widget>[
              const SizedBox(height: 12),
              _SettingsMessage(text: _message!, isError: false),
            ],
            if (_errorMessage != null) ...<Widget>[
              const SizedBox(height: 12),
              _SettingsMessage(text: _errorMessage!, isError: true),
            ],
            const SizedBox(height: 14),
            if (categories.isEmpty)
              const _SettingsHintBlock(message: '没有匹配的设置项，换个关键词试试。')
            else
              ...categories,
          ],
        ),
      ),
    );
  }

  List<Widget> _filteredCategories() {
    final query = _normalize(_query);
    return _categories()
        .map((category) => category.toWidget(context, query: query))
        .whereType<Widget>()
        .toList(growable: false);
  }
}

String _normalize(String value) {
  return value.toLowerCase().replaceAll(RegExp(r'\s+'), '');
}

class _SettingsCategoryConfig {
  const _SettingsCategoryConfig({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.keywords,
    required this.sections,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String keywords;
  final List<_SettingsSectionConfig> sections;

  Widget? toWidget(BuildContext context, {required String query}) {
    final categoryText = _normalize('$title $subtitle $keywords');
    final categoryMatches = query.isEmpty || categoryText.contains(query);
    final visibleSections = categoryMatches
        ? sections
        : sections
              .where((section) => section.matches(query))
              .toList(growable: false);
    if (visibleSections.isEmpty) {
      return null;
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: const Color(0xFFDCE5E7)),
        ),
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            initiallyExpanded: query.isNotEmpty,
            tilePadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 6,
            ),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            leading: Icon(icon, color: const Color(0xFF0D5C63)),
            title: Text(
              title,
              style: const TextStyle(
                color: Color(0xFF17313A),
                fontWeight: FontWeight.w800,
              ),
            ),
            subtitle: Text(
              subtitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Color(0xFF5A6B70)),
            ),
            children: visibleSections
                .map((section) => section.toWidget(context, query: query))
                .toList(growable: false),
          ),
        ),
      ),
    );
  }
}

class _SettingsSectionConfig {
  const _SettingsSectionConfig({
    required this.title,
    required this.subtitle,
    required this.keywords,
    required this.builder,
  });

  final String title;
  final String subtitle;
  final String keywords;
  final WidgetBuilder builder;

  bool matches(String query) {
    if (query.isEmpty) {
      return true;
    }
    return _normalize('$title $subtitle $keywords').contains(query);
  }

  Widget toWidget(BuildContext context, {required String query}) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAF8),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            initiallyExpanded: query.isNotEmpty,
            tilePadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 2,
            ),
            childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
            title: Text(
              title,
              style: const TextStyle(
                color: Color(0xFF17313A),
                fontWeight: FontWeight.w800,
              ),
            ),
            subtitle: Text(
              subtitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Color(0xFF5A6B70)),
            ),
            children: <Widget>[builder(context)],
          ),
        ),
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        prefixIcon: const Icon(Icons.search),
        suffixIcon: controller.text.isEmpty
            ? null
            : IconButton(
                tooltip: '清空搜索',
                onPressed: controller.clear,
                icon: const Icon(Icons.close),
              ),
        hintText: '搜索设置，例如：模板、录像、跟随、相册、设备地址',
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: Color(0xFFDCE5E7)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: Color(0xFFDCE5E7)),
        ),
      ),
    );
  }
}

class _SettingsActionButton extends StatelessWidget {
  const _SettingsActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 18),
      label: Text(label),
    );
  }
}

class _SettingsSwitchTile extends StatelessWidget {
  const _SettingsSwitchTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE4ECEE)),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
          child: Row(
            children: <Widget>[
              Icon(icon, color: const Color(0xFF0D5C63)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      title,
                      style: const TextStyle(
                        color: Color(0xFF17313A),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: Color(0xFF5A6B70),
                        height: 1.35,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              Switch.adaptive(value: value, onChanged: onChanged),
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingsSliderTile extends StatelessWidget {
  const _SettingsSliderTile({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.valueLabel,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String valueLabel;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE4ECEE)),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        color: Color(0xFF17313A),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Text(
                    valueLabel,
                    style: const TextStyle(
                      color: Color(0xFF0D5C63),
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: const TextStyle(
                  color: Color(0xFF5A6B70),
                  height: 1.35,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Slider(
                value: value.clamp(min, max).toDouble(),
                min: min,
                max: max,
                divisions: divisions,
                label: valueLabel,
                onChanged: onChanged,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingsChoiceOption {
  const _SettingsChoiceOption({required this.value, required this.label});

  final String value;
  final String label;
}

class _SettingsChoiceGroup extends StatelessWidget {
  const _SettingsChoiceGroup({
    required this.title,
    required this.options,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final List<_SettingsChoiceOption> options;
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE4ECEE)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                title,
                style: const TextStyle(
                  color: Color(0xFF17313A),
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: options
                    .map(
                      (option) => ChoiceChip(
                        label: Text(option.label),
                        selected: option.value == value,
                        onSelected: (_) => onChanged(option.value),
                      ),
                    )
                    .toList(growable: false),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingsInfoGrid extends StatelessWidget {
  const _SettingsInfoGrid({required this.items});

  final List<({String label, String value})> items;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: items
          .map(
            (item) => SizedBox(
              width: 150,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFE4ECEE)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        item.label,
                        style: const TextStyle(
                          color: Color(0xFF5A6B70),
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        item.value,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF17313A),
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          )
          .toList(growable: false),
    );
  }
}

class _PlanSettingsRow extends StatelessWidget {
  const _PlanSettingsRow({
    required this.plan,
    required this.selected,
    required this.onTap,
  });

  final PlanSummary plan;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _SettingsListRow(
      icon: selected
          ? Icons.check_circle_outline
          : Icons.radio_button_unchecked_outlined,
      title: plan.name,
      subtitle:
          '${plan.priceLabel} · ${plan.billingCycleLabel} · ${selected ? '当前订阅' : '可查看'}',
      onTap: onTap,
      trailing: const Icon(Icons.chevron_right),
    );
  }
}

class _TemplateSettingsRow extends StatelessWidget {
  const _TemplateSettingsRow({required this.template, required this.onDelete});

  final TemplateSummary template;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    return _SettingsListRow(
      icon: template.isRecommendedDefault
          ? Icons.verified_outlined
          : Icons.view_in_ar_outlined,
      title: template.name,
      subtitle: template.isRecommendedDefault
          ? '后台推荐模板'
          : '${template.templateType} · ${template.status}',
      trailing: IconButton(
        tooltip: template.isRecommendedDefault ? '推荐模板不能删除' : '删除模板',
        onPressed: onDelete,
        icon: const Icon(Icons.delete_outline),
      ),
    );
  }
}

class _SettingsListRow extends StatelessWidget {
  const _SettingsListRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Ink(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFE4ECEE)),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: <Widget>[
                  Icon(icon, color: const Color(0xFF0D5C63)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFF17313A),
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          subtitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFF5A6B70),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  ?trailing,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SettingsHintBlock extends StatelessWidget {
  const _SettingsHintBlock({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE4ECEE)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Text(
          message,
          style: const TextStyle(
            color: Color(0xFF4B5563),
            height: 1.45,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _SettingsMessage extends StatelessWidget {
  const _SettingsMessage({required this.text, required this.isError});

  final String text;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: isError ? const Color(0xFFFFF0F0) : const Color(0xFFE9F6F1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isError ? const Color(0xFFF0B7B7) : const Color(0xFFB9DED1),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Text(
          text,
          style: TextStyle(
            color: isError ? const Color(0xFF9E2A2B) : const Color(0xFF0D5C63),
            fontWeight: FontWeight.w700,
            height: 1.4,
          ),
        ),
      ),
    );
  }
}
