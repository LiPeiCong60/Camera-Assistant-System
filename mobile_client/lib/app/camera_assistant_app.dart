import 'package:flutter/material.dart';

import '../features/auth/auth_controller.dart';
import '../features/auth/login_page.dart';
import '../features/home/home_page.dart';
import '../features/settings/server_config_page.dart';
import '../services/app_config.dart';
import '../services/mobile_api_service.dart';

class CameraAssistantApp extends StatefulWidget {
  const CameraAssistantApp({super.key});

  @override
  State<CameraAssistantApp> createState() => _CameraAssistantAppState();
}

class _CameraAssistantAppState extends State<CameraAssistantApp> {
  AuthController? _authController;
  ServerConfig? _serverConfig;
  bool _isLoadingServerConfig = true;
  bool _hasSavedServerConfig = false;
  bool _isEditingServerConfig = false;

  @override
  void initState() {
    super.initState();
    _loadServerConfig();
  }

  AuthController _createAuthController(ServerConfig config) {
    return AuthController(
      apiService: MobileApiService(apiBaseUrl: config.apiBaseUrl),
      serverConfig: config,
    );
  }

  Future<void> _loadServerConfig() async {
    final config = await AppConfig.loadServerConfig();
    final hasSavedConfig = await AppConfig.hasSavedServerConfig();
    if (!mounted) {
      return;
    }
    final authController = _createAuthController(config);
    setState(() {
      _serverConfig = config;
      _authController = authController;
      _hasSavedServerConfig = hasSavedConfig;
      _isLoadingServerConfig = false;
    });
    if (hasSavedConfig) {
      await authController.restoreSession();
    }
  }

  Future<void> _saveServerConfig(ServerConfig config) async {
    final normalizedConfig = ServerConfig(
      apiBaseUrl: AppConfig.normalizeApiBaseUrl(config.apiBaseUrl),
      deviceApiBaseUrl: AppConfig.normalizeDeviceApiBaseUrl(
        config.deviceApiBaseUrl,
      ),
    );
    await AppConfig.saveServerConfig(normalizedConfig);
    final previousController = _authController;
    final authController = _createAuthController(normalizedConfig);
    if (!mounted) {
      previousController?.dispose();
      authController.dispose();
      return;
    }
    setState(() {
      _serverConfig = normalizedConfig;
      _authController = authController;
      _hasSavedServerConfig = true;
      _isEditingServerConfig = false;
    });
    previousController?.dispose();
  }

  @override
  void dispose() {
    _authController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF0D5C63);
    final colorScheme = ColorScheme.fromSeed(
      seedColor: seed,
      primary: seed,
      secondary: const Color(0xFFE0A458),
      surface: const Color(0xFFFFFBF4),
    );

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: '云影随行',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: colorScheme,
        scaffoldBackgroundColor: const Color(0xFFF5F1E8),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          foregroundColor: Color(0xFF1B2A2F),
          elevation: 0,
        ),
        cardTheme: CardThemeData(
          color: Colors.white.withValues(alpha: 0.86),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: const BorderSide(color: Color(0x1A0D5C63)),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white.withValues(alpha: 0.94),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: const BorderSide(color: seed, width: 1.4),
          ),
        ),
      ),
      home: _authController == null
          ? _buildHome()
          : AnimatedBuilder(
              animation: _authController!,
              builder: (context, _) => _buildHome(),
            ),
    );
  }

  Widget _buildHome() {
    final authController = _authController;
    final serverConfig = _serverConfig;
    if (_isLoadingServerConfig ||
        authController == null ||
        serverConfig == null) {
      return const _AuthBootstrapPage();
    }
    if (!_hasSavedServerConfig || _isEditingServerConfig) {
      return ServerConfigPage(
        initialConfig: serverConfig,
        onSaved: _saveServerConfig,
        onCancel: _hasSavedServerConfig
            ? () {
                setState(() {
                  _isEditingServerConfig = false;
                });
              }
            : null,
      );
    }
    if (authController.isRestoring) {
      return const _AuthBootstrapPage();
    }
    if (authController.session == null) {
      return LoginPage(
        controller: authController,
        onOpenServerSettings: () {
          setState(() {
            _isEditingServerConfig = true;
          });
        },
      );
    }
    return HomePage(controller: authController);
  }
}

class _AuthBootstrapPage extends StatelessWidget {
  const _AuthBootstrapPage();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            CircularProgressIndicator(),
            SizedBox(height: 18),
            Text('正在恢复登录状态...'),
          ],
        ),
      ),
    );
  }
}
