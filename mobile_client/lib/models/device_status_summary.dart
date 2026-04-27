class DeviceStatusSummary {
  const DeviceStatusSummary({
    required this.sessionOpened,
    required this.sessionCode,
    required this.streamUrl,
    required this.mode,
    required this.followMode,
    required this.deviceStatus,
    required this.currentPan,
    required this.currentTilt,
    required this.loopRunning,
    this.selectedTemplateId,
    this.templateStatus = const DeviceTemplateStatusSummary(),
    this.trackingStatus = const DeviceTrackingStatusSummary(),
    this.overlayStatus = const DeviceOverlayStatusSummary(),
    this.gestureStatus = const DeviceGestureStatusSummary(),
    this.latestCapture = const DeviceLatestCaptureSummary(),
    this.aiStatus = const DeviceAiStatusSummary(),
    this.runtimeConfig = const DeviceRuntimeConfigSummary(),
    this.aiLockEnabled = false,
    this.aiLockFitScore = 0,
    this.aiLockTargetBoxNorm,
  });

  final bool sessionOpened;
  final String? sessionCode;
  final String? streamUrl;
  final String mode;
  final String? followMode;
  final String deviceStatus;
  final double currentPan;
  final double currentTilt;
  final bool loopRunning;
  final String? selectedTemplateId;
  final DeviceTemplateStatusSummary templateStatus;
  final DeviceTrackingStatusSummary trackingStatus;
  final DeviceOverlayStatusSummary overlayStatus;
  final DeviceGestureStatusSummary gestureStatus;
  final DeviceLatestCaptureSummary latestCapture;
  final DeviceAiStatusSummary aiStatus;
  final DeviceRuntimeConfigSummary runtimeConfig;
  final bool aiLockEnabled;
  final double aiLockFitScore;
  final List<double>? aiLockTargetBoxNorm;

  factory DeviceStatusSummary.fromJson(Map<String, dynamic> json) {
    final aiLockStatus = json['ai_lock_status'] as Map<String, dynamic>?;
    final aiStatusRaw = json['ai_status'] as Map<String, dynamic>?;
    final targetBoxNormRaw = aiLockStatus?['target_box_norm'];
    final aiStatus = DeviceAiStatusSummary.fromJson(aiStatusRaw);
    final selectedTemplateId = json['selected_template_id'];

    return DeviceStatusSummary(
      sessionOpened: json['session_opened'] as bool? ?? false,
      sessionCode: json['session_code'] as String?,
      streamUrl: json['stream_url'] as String?,
      mode: json['mode'] as String? ?? 'MANUAL',
      followMode: json['follow_mode'] as String?,
      deviceStatus: json['device_status'] as String? ?? 'unknown',
      currentPan: (json['current_pan'] as num?)?.toDouble() ?? 0,
      currentTilt: (json['current_tilt'] as num?)?.toDouble() ?? 0,
      loopRunning: json['loop_running'] as bool? ?? false,
      selectedTemplateId: selectedTemplateId?.toString(),
      templateStatus: DeviceTemplateStatusSummary.fromJson(
        json['template_status'] as Map<String, dynamic>?,
      ),
      trackingStatus: DeviceTrackingStatusSummary.fromJson(
        json['tracking_status'] as Map<String, dynamic>?,
      ),
      overlayStatus: DeviceOverlayStatusSummary.fromJson(
        json['overlay_status'] as Map<String, dynamic>?,
      ),
      gestureStatus: DeviceGestureStatusSummary.fromJson(
        json['gesture_status'] as Map<String, dynamic>?,
      ),
      latestCapture: DeviceLatestCaptureSummary.fromJson(
        json['latest_capture'] as Map<String, dynamic>?,
      ),
      aiStatus: aiStatus,
      runtimeConfig: DeviceRuntimeConfigSummary.fromJson(
        json['runtime_config'] as Map<String, dynamic>?,
      ),
      aiLockEnabled: aiLockStatus?['enabled'] as bool? ?? aiStatus.lockEnabled,
      aiLockFitScore:
          (aiLockStatus?['fit_score'] as num?)?.toDouble() ??
          aiStatus.lockFitScore,
      aiLockTargetBoxNorm: targetBoxNormRaw is List
          ? targetBoxNormRaw
                .whereType<num>()
                .map((value) => value.toDouble())
                .toList(growable: false)
          : aiStatus.lockTargetBoxNorm,
    );
  }
}

class DeviceRuntimeConfigSummary {
  const DeviceRuntimeConfigSummary({
    this.detectorFps = 0,
    this.asyncSkipFrames = 0,
    this.maxInferenceSide = 0,
    this.previewFps = 0,
    this.previewScale = 1,
    this.enablePoseLandmarks = true,
    this.enableFaceLandmarks = true,
    this.enableHandLandmarks = true,
    this.trackingAnchorMode = 'auto',
    this.detectorBackend,
    this.lastFrameAt,
    this.lastDetectionAt,
  });

  final double detectorFps;
  final int asyncSkipFrames;
  final int maxInferenceSide;
  final double previewFps;
  final double previewScale;
  final bool enablePoseLandmarks;
  final bool enableFaceLandmarks;
  final bool enableHandLandmarks;
  final String trackingAnchorMode;
  final String? detectorBackend;
  final DateTime? lastFrameAt;
  final DateTime? lastDetectionAt;

  factory DeviceRuntimeConfigSummary.fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return const DeviceRuntimeConfigSummary();
    }
    return DeviceRuntimeConfigSummary(
      detectorFps: (json['detector_fps'] as num?)?.toDouble() ?? 0,
      asyncSkipFrames: (json['async_skip_frames'] as num?)?.toInt() ?? 0,
      maxInferenceSide: (json['max_inference_side'] as num?)?.toInt() ?? 0,
      previewFps: (json['preview_fps'] as num?)?.toDouble() ?? 0,
      previewScale: (json['preview_scale'] as num?)?.toDouble() ?? 1,
      enablePoseLandmarks: json['enable_pose_landmarks'] as bool? ?? true,
      enableFaceLandmarks: json['enable_face_landmarks'] as bool? ?? true,
      enableHandLandmarks: json['enable_hand_landmarks'] as bool? ?? true,
      trackingAnchorMode: json['tracking_anchor_mode'] as String? ?? 'auto',
      detectorBackend: json['detector_backend'] as String?,
      lastFrameAt: _readTimestamp(json['last_frame_at']),
      lastDetectionAt: _readTimestamp(json['last_detection_at']),
    );
  }
}

class DeviceOverlayStatusSummary {
  const DeviceOverlayStatusSummary({
    this.enabled = true,
    this.showLivePersonBbox = true,
    this.showLiveBodySkeleton = true,
    this.showLiveHands = true,
    this.showTemplateBbox = true,
    this.showTemplateSkeleton = true,
    this.showAiLockBox = true,
  });

  final bool enabled;
  final bool showLivePersonBbox;
  final bool showLiveBodySkeleton;
  final bool showLiveHands;
  final bool showTemplateBbox;
  final bool showTemplateSkeleton;
  final bool showAiLockBox;

  factory DeviceOverlayStatusSummary.fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return const DeviceOverlayStatusSummary();
    }
    return DeviceOverlayStatusSummary(
      enabled: json['enabled'] as bool? ?? true,
      showLivePersonBbox: json['show_live_person_bbox'] as bool? ?? true,
      showLiveBodySkeleton: json['show_live_body_skeleton'] as bool? ?? true,
      showLiveHands: json['show_live_hands'] as bool? ?? true,
      showTemplateBbox: json['show_template_bbox'] as bool? ?? true,
      showTemplateSkeleton: json['show_template_skeleton'] as bool? ?? true,
      showAiLockBox: json['show_ai_lock_box'] as bool? ?? true,
    );
  }
}

class DeviceGestureStatusSummary {
  const DeviceGestureStatusSummary({
    this.captureEnabled = false,
    this.forceOkEnabled = false,
    this.autoAnalyzeEnabled = false,
    this.openFistRequiresComposeReady = true,
    this.handsDetected = false,
    this.handCount = 0,
    this.lastEvent,
    this.lastCaptureError,
    this.captureCountdownActive = false,
    this.captureCountdownRemainingSeconds,
    this.captureCountdownEvent,
    this.captureCountdownReason,
  });

  final bool captureEnabled;
  final bool forceOkEnabled;
  final bool autoAnalyzeEnabled;
  final bool openFistRequiresComposeReady;
  final bool handsDetected;
  final int handCount;
  final String? lastEvent;
  final String? lastCaptureError;
  final bool captureCountdownActive;
  final double? captureCountdownRemainingSeconds;
  final String? captureCountdownEvent;
  final String? captureCountdownReason;

  factory DeviceGestureStatusSummary.fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return const DeviceGestureStatusSummary();
    }
    final countdown = json['capture_countdown'] as Map<String, dynamic>?;
    return DeviceGestureStatusSummary(
      captureEnabled: json['capture_enabled'] as bool? ?? false,
      forceOkEnabled: json['force_ok_enabled'] as bool? ?? false,
      autoAnalyzeEnabled: json['auto_analyze_enabled'] as bool? ?? false,
      openFistRequiresComposeReady:
          json['open_fist_requires_compose_ready'] as bool? ?? true,
      handsDetected: json['hands_detected'] as bool? ?? false,
      handCount: (json['hand_count'] as num?)?.toInt() ?? 0,
      lastEvent: json['last_event'] as String?,
      lastCaptureError: json['last_capture_error'] as String?,
      captureCountdownActive: countdown?['active'] as bool? ?? false,
      captureCountdownRemainingSeconds:
          (countdown?['remaining_s'] as num?)?.toDouble(),
      captureCountdownEvent: countdown?['event'] as String?,
      captureCountdownReason: countdown?['reason'] as String?,
    );
  }
}

class DeviceLatestCaptureSummary {
  const DeviceLatestCaptureSummary({
    this.path,
    this.analysis,
    this.analysisError,
  });

  final String? path;
  final DeviceCaptureAnalysisSummary? analysis;
  final String? analysisError;

  factory DeviceLatestCaptureSummary.fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return const DeviceLatestCaptureSummary();
    }
    final analysisRaw = json['analysis'];
    return DeviceLatestCaptureSummary(
      path: json['path'] as String?,
      analysis: analysisRaw is Map
          ? DeviceCaptureAnalysisSummary.fromJson(
              Map<String, dynamic>.from(analysisRaw),
            )
          : null,
      analysisError: json['analysis_error'] as String?,
    );
  }
}

class DeviceCaptureAnalysisSummary {
  const DeviceCaptureAnalysisSummary({
    this.score,
    this.summary,
    this.suggestions = const <String>[],
  });

  final double? score;
  final String? summary;
  final List<String> suggestions;

  factory DeviceCaptureAnalysisSummary.fromJson(Map<String, dynamic> json) {
    return DeviceCaptureAnalysisSummary(
      score: (json['score'] as num?)?.toDouble(),
      summary: json['summary'] as String?,
      suggestions: (json['suggestions'] as List<dynamic>? ?? const <dynamic>[])
          .map((item) => item.toString())
          .toList(growable: false),
    );
  }
}

class DeviceTemplateStatusSummary {
  const DeviceTemplateStatusSummary({
    this.selected = false,
    this.templateName,
    this.lastUpdatedAt,
    this.composeScore,
    this.ready = false,
    this.messages = const <String>[],
  });

  final bool selected;
  final String? templateName;
  final double? composeScore;
  final bool ready;
  final List<String> messages;
  final DateTime? lastUpdatedAt;

  factory DeviceTemplateStatusSummary.fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return const DeviceTemplateStatusSummary();
    }
    return DeviceTemplateStatusSummary(
      selected: json['selected'] as bool? ?? false,
      templateName: json['template_name'] as String?,
      composeScore: (json['compose_score'] as num?)?.toDouble(),
      ready: json['ready'] as bool? ?? false,
      messages: (json['messages'] as List<dynamic>? ?? const <dynamic>[])
          .map((item) => item.toString())
          .toList(growable: false),
      lastUpdatedAt: _readTimestamp(json['last_updated_at']),
    );
  }
}

class DeviceTrackingStatusSummary {
  const DeviceTrackingStatusSummary({
    this.stableDetection = false,
    this.reliableDetectionStreak = 0,
    this.stableBbox,
  });

  final bool stableDetection;
  final int reliableDetectionStreak;
  final Map<String, dynamic>? stableBbox;

  factory DeviceTrackingStatusSummary.fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return const DeviceTrackingStatusSummary();
    }
    return DeviceTrackingStatusSummary(
      stableDetection: json['stable_detection'] as bool? ?? false,
      reliableDetectionStreak:
          (json['reliable_detection_streak'] as num?)?.toInt() ?? 0,
      stableBbox: json['stable_bbox'] as Map<String, dynamic>?,
    );
  }
}

class DeviceAiStatusSummary {
  const DeviceAiStatusSummary({
    this.angleSearchRunning = false,
    this.backgroundLockRunning = false,
    this.lockEnabled = false,
    this.lockFitScore = 0,
    this.lockTargetBoxNorm,
    this.lastAngleSearchResult,
    this.lastAngleSearchError,
    this.lastBackgroundLockResult,
    this.lastBackgroundLockError,
  });

  final bool angleSearchRunning;
  final bool backgroundLockRunning;
  final bool lockEnabled;
  final double lockFitScore;
  final List<double>? lockTargetBoxNorm;
  final Map<String, dynamic>? lastAngleSearchResult;
  final String? lastAngleSearchError;
  final Map<String, dynamic>? lastBackgroundLockResult;
  final String? lastBackgroundLockError;

  bool get hasRunningTask => angleSearchRunning || backgroundLockRunning;

  factory DeviceAiStatusSummary.fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return const DeviceAiStatusSummary();
    }
    return DeviceAiStatusSummary(
      angleSearchRunning:
          json['angle_search_running'] as bool? ??
          json['ai_angle_search_running'] as bool? ??
          false,
      backgroundLockRunning: json['background_lock_running'] as bool? ?? false,
      lockEnabled:
          json['lock_enabled'] as bool? ??
          (json['ai_lock_status'] as Map<String, dynamic>?)?['enabled']
              as bool? ??
          false,
      lockFitScore:
          (json['lock_fit_score'] as num?)?.toDouble() ??
          ((json['ai_lock_status'] as Map<String, dynamic>?)?['fit_score']
                  as num?)
              ?.toDouble() ??
          0,
      lockTargetBoxNorm: _readDoubleList(
        json['lock_target_box_norm'] ??
            (json['ai_lock_status']
                as Map<String, dynamic>?)?['target_box_norm'],
      ),
      lastAngleSearchResult:
          json['last_angle_search_result'] as Map<String, dynamic>?,
      lastAngleSearchError: json['last_angle_search_error'] as String?,
      lastBackgroundLockResult:
          json['last_background_lock_result'] as Map<String, dynamic>?,
      lastBackgroundLockError: json['last_background_lock_error'] as String?,
    );
  }
}

List<double>? _readDoubleList(dynamic raw) {
  if (raw is! List) {
    return null;
  }
  final values = raw
      .whereType<num>()
      .map((value) => value.toDouble())
      .toList(growable: false);
  return values.length == raw.length ? values : null;
}

DateTime? _readTimestamp(dynamic raw) {
  if (raw is num) {
    return DateTime.fromMillisecondsSinceEpoch((raw * 1000).round());
  }
  if (raw is String) {
    return DateTime.tryParse(raw);
  }
  return null;
}
