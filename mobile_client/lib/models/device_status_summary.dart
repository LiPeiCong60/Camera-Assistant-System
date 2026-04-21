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
  final int? selectedTemplateId;
  final bool aiLockEnabled;
  final double aiLockFitScore;
  final List<double>? aiLockTargetBoxNorm;

  factory DeviceStatusSummary.fromJson(Map<String, dynamic> json) {
    final aiLockStatus = json['ai_lock_status'] as Map<String, dynamic>?;
    final targetBoxNormRaw = aiLockStatus?['target_box_norm'];

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
      selectedTemplateId: json['selected_template_id'] as int?,
      aiLockEnabled: aiLockStatus?['enabled'] as bool? ?? false,
      aiLockFitScore: (aiLockStatus?['fit_score'] as num?)?.toDouble() ?? 0,
      aiLockTargetBoxNorm: targetBoxNormRaw is List
          ? targetBoxNormRaw
                .whereType<num>()
                .map((value) => value.toDouble())
                .toList(growable: false)
          : null,
    );
  }
}
