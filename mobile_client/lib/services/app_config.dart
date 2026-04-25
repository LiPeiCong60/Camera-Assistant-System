import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ServerConfig {
  const ServerConfig({
    required this.apiBaseUrl,
    required this.deviceApiBaseUrl,
  });

  final String apiBaseUrl;
  final String deviceApiBaseUrl;

  ServerConfig copyWith({String? apiBaseUrl, String? deviceApiBaseUrl}) {
    return ServerConfig(
      apiBaseUrl: apiBaseUrl ?? this.apiBaseUrl,
      deviceApiBaseUrl: deviceApiBaseUrl ?? this.deviceApiBaseUrl,
    );
  }
}

class AppConfig {
  static const String prefsApiBaseUrlKey = 'server_config.api_base_url';
  static const String prefsDeviceApiBaseUrlKey =
      'server_config.device_api_base_url';

  static const String _apiBaseUrlFromEnv = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: '',
  );
  static const String _deviceApiBaseUrlFromEnv = String.fromEnvironment(
    'DEVICE_API_BASE_URL',
    defaultValue: '',
  );

  static String get apiBaseUrl {
    if (_apiBaseUrlFromEnv.isNotEmpty) {
      return _apiBaseUrlFromEnv;
    }
    return _defaultApiBaseUrl;
  }

  static String get deviceApiBaseUrl {
    if (_deviceApiBaseUrlFromEnv.isNotEmpty) {
      return _deviceApiBaseUrlFromEnv;
    }
    return _defaultDeviceApiBaseUrl;
  }

  static ServerConfig get defaultServerConfig {
    return ServerConfig(
      apiBaseUrl: apiBaseUrl,
      deviceApiBaseUrl: deviceApiBaseUrl,
    );
  }

  static Future<bool> hasSavedServerConfig() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getString(prefsApiBaseUrlKey)?.trim().isNotEmpty ?? false) &&
        (prefs.getString(prefsDeviceApiBaseUrlKey)?.trim().isNotEmpty ?? false);
  }

  static Future<ServerConfig> loadServerConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final savedApiBaseUrl = prefs.getString(prefsApiBaseUrlKey)?.trim();
    final savedDeviceApiBaseUrl = prefs
        .getString(prefsDeviceApiBaseUrlKey)
        ?.trim();
    return ServerConfig(
      apiBaseUrl: savedApiBaseUrl == null || savedApiBaseUrl.isEmpty
          ? apiBaseUrl
          : savedApiBaseUrl,
      deviceApiBaseUrl:
          savedDeviceApiBaseUrl == null || savedDeviceApiBaseUrl.isEmpty
          ? deviceApiBaseUrl
          : savedDeviceApiBaseUrl,
    );
  }

  static Future<void> saveServerConfig(ServerConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      prefsApiBaseUrlKey,
      normalizeApiBaseUrl(config.apiBaseUrl),
    );
    await prefs.setString(
      prefsDeviceApiBaseUrlKey,
      normalizeDeviceApiBaseUrl(config.deviceApiBaseUrl),
    );
  }

  static String normalizeApiBaseUrl(String rawBaseUrl) {
    var normalized = rawBaseUrl.trim();
    while (normalized.endsWith('/')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    if (!normalized.endsWith('/api')) {
      normalized = '$normalized/api';
    }
    return normalized;
  }

  static String normalizeDeviceApiBaseUrl(String rawBaseUrl) {
    var normalized = rawBaseUrl.trim();
    while (normalized.endsWith('/')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    if (normalized.endsWith('/api')) {
      normalized = normalized.substring(0, normalized.length - 4);
    }
    return normalized;
  }

  static String get _defaultApiBaseUrl {
    if (kIsWeb) {
      return 'http://127.0.0.1:8000/api';
    }
    if (Platform.isAndroid) {
      return 'http://10.0.2.2:8000/api';
    }
    return 'http://127.0.0.1:8000/api';
  }

  static String get _defaultDeviceApiBaseUrl {
    if (kIsWeb) {
      return 'http://127.0.0.1:8001';
    }
    if (Platform.isAndroid) {
      return 'http://10.0.2.2:8001';
    }
    return 'http://127.0.0.1:8001';
  }
}
