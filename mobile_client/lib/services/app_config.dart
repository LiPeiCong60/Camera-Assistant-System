class AppConfig {
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://127.0.0.1:8000/api',
  );

  static const String deviceApiBaseUrl = String.fromEnvironment(
    'DEVICE_API_BASE_URL',
    defaultValue: 'http://127.0.0.1:8001',
  );
}
