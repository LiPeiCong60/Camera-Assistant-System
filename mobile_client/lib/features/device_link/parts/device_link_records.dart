part of '../device_link_page.dart';

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

class _AiResultText {
  const _AiResultText({required this.title, required this.body});

  final String title;
  final String body;
}

class _DeviceCaptureRecord {
  const _DeviceCaptureRecord({
    required this.path,
    required this.createdAt,
    required this.source,
    this.localPath,
    this.savedAt,
    this.backendCaptureId,
  });

  final String path;
  final DateTime createdAt;
  final String source;
  final String? localPath;
  final DateTime? savedAt;
  final int? backendCaptureId;

  _DeviceCaptureRecord copyWith({
    String? path,
    DateTime? createdAt,
    String? source,
    String? localPath,
    DateTime? savedAt,
    int? backendCaptureId,
  }) {
    return _DeviceCaptureRecord(
      path: path ?? this.path,
      createdAt: createdAt ?? this.createdAt,
      source: source ?? this.source,
      localPath: localPath ?? this.localPath,
      savedAt: savedAt ?? this.savedAt,
      backendCaptureId: backendCaptureId ?? this.backendCaptureId,
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

class _DeviceLinkDraftConfig {
  const _DeviceLinkDraftConfig({
    required this.baseUrl,
    required this.streamUrl,
    required this.autoRefreshEnabled,
    required this.landscapeControlsOnLeft,
    required this.joystickVisible,
    required this.joystickSensitivity,
    required this.recentConnections,
  });

  final String baseUrl;
  final String streamUrl;
  final bool autoRefreshEnabled;
  final bool landscapeControlsOnLeft;
  final bool joystickVisible;
  final double joystickSensitivity;
  final List<_DeviceConnectionPreset> recentConnections;
}

class _DeviceLinkPreferenceStore {
  const _DeviceLinkPreferenceStore();

  static const String _baseUrlKey = 'device_link.base_url';
  static const String _streamUrlKey = 'device_link.stream_url';
  static const String _autoRefreshKey = 'device_link.auto_refresh';
  static const String _landscapeControlsLeftKey =
      'device_link.landscape_controls_left';
  static const String _joystickSensitivityKey =
      'device_link.joystick_sensitivity';
  static const String _joystickVisibleKey = 'device_link.joystick_visible';
  static const String _recentConnectionsKey = 'device_link.recent_connections';

  Future<_DeviceLinkDraftConfig> loadDraft({
    required String fallbackBaseUrl,
    required String fallbackStreamUrl,
    required bool fallbackAutoRefreshEnabled,
    required bool fallbackLandscapeControlsOnLeft,
    required bool fallbackJoystickVisible,
    required double fallbackJoystickSensitivity,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final recentRaw = prefs.getStringList(_recentConnectionsKey) ?? <String>[];
    final recentConnections = recentRaw
        .map(_DeviceConnectionPreset.tryParse)
        .whereType<_DeviceConnectionPreset>()
        .toList(growable: false);

    return _DeviceLinkDraftConfig(
      baseUrl: prefs.getString(_baseUrlKey) ?? fallbackBaseUrl,
      streamUrl: prefs.getString(_streamUrlKey) ?? fallbackStreamUrl,
      autoRefreshEnabled:
          prefs.getBool(_autoRefreshKey) ?? fallbackAutoRefreshEnabled,
      landscapeControlsOnLeft:
          prefs.getBool(_landscapeControlsLeftKey) ??
          fallbackLandscapeControlsOnLeft,
      joystickVisible:
          prefs.getBool(_joystickVisibleKey) ?? fallbackJoystickVisible,
      joystickSensitivity:
          prefs.getDouble(_joystickSensitivityKey) ??
          fallbackJoystickSensitivity,
      recentConnections: recentConnections,
    );
  }

  Future<void> saveDraft(_DeviceLinkDraftConfig draft) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_baseUrlKey, draft.baseUrl);
    await prefs.setString(_streamUrlKey, draft.streamUrl);
    await prefs.setBool(_autoRefreshKey, draft.autoRefreshEnabled);
    await prefs.setBool(
      _landscapeControlsLeftKey,
      draft.landscapeControlsOnLeft,
    );
    await prefs.setBool(_joystickVisibleKey, draft.joystickVisible);
    await prefs.setDouble(_joystickSensitivityKey, draft.joystickSensitivity);
  }

  Future<List<_DeviceConnectionPreset>> rememberConnection(
    _DeviceConnectionPreset preset, {
    required List<_DeviceConnectionPreset> currentConnections,
  }) async {
    final merged = <_DeviceConnectionPreset>[
      preset,
      ...currentConnections.where(
        (item) =>
            item.baseUrl != preset.baseUrl ||
            item.streamUrl != preset.streamUrl,
      ),
    ];
    final limited = merged.take(5).toList(growable: false);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _recentConnectionsKey,
      limited.map((item) => item.toStorageString()).toList(growable: false),
    );
    return limited;
  }

  Future<void> clearRecentConnections() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_recentConnectionsKey);
  }
}
