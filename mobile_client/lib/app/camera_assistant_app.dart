import 'package:flutter/material.dart';

import '../features/auth/auth_controller.dart';
import '../features/auth/login_page.dart';
import '../features/home/home_page.dart';
import '../services/app_config.dart';
import '../services/mobile_api_service.dart';

class CameraAssistantApp extends StatefulWidget {
  const CameraAssistantApp({super.key});

  @override
  State<CameraAssistantApp> createState() => _CameraAssistantAppState();
}

class _CameraAssistantAppState extends State<CameraAssistantApp> {
  late final AuthController _authController;

  @override
  void initState() {
    super.initState();
    _authController = AuthController(
      apiService: MobileApiService(apiBaseUrl: AppConfig.apiBaseUrl),
    );
    _bootstrapAuth();
  }

  Future<void> _bootstrapAuth() async {
    await _authController.restoreSession();
  }

  @override
  void dispose() {
    _authController.dispose();
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
      title: 'Camera Assistant',
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
      home: AnimatedBuilder(
        animation: _authController,
        builder: (context, _) {
          if (_authController.isRestoring) {
            return const _AuthBootstrapPage();
          }
          if (_authController.session == null) {
            return LoginPage(controller: _authController);
          }
          return HomePage(controller: _authController);
        },
      ),
    );
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
