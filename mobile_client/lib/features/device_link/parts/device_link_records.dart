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
