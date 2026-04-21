import 'dart:io';

import 'package:flutter/foundation.dart';

class AppConfig {
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
