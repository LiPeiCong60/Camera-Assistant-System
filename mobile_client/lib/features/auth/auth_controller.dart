import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/auth_session.dart';
import '../../models/plan_summary.dart';
import '../../models/subscription_info.dart';
import '../../models/user_profile.dart';
import '../../services/api_client.dart';
import '../../services/mobile_api_service.dart';

class AuthController extends ChangeNotifier {
  static const String _sessionPrefsKey = 'auth.session';

  AuthController({required MobileApiService apiService})
    : _apiService = apiService;

  final MobileApiService _apiService;

  MobileApiService get apiService => _apiService;

  AuthSession? session;
  UserProfile? profile;
  SubscriptionInfo? subscription;
  List<PlanSummary> plans = const <PlanSummary>[];
  bool isLoggingIn = false;
  bool isRegistering = false;
  bool isRefreshing = false;
  bool isRestoring = false;
  String? errorMessage;

  Future<void> restoreSession() async {
    isRestoring = true;
    errorMessage = null;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      final rawSession = prefs.getString(_sessionPrefsKey);
      if (rawSession == null || rawSession.isEmpty) {
        return;
      }

      final decoded = jsonDecode(rawSession);
      if (decoded is! Map<String, dynamic>) {
        await prefs.remove(_sessionPrefsKey);
        return;
      }

      session = AuthSession.fromJson(decoded);
      await refreshDashboard();
      if (profile == null) {
        await _clearPersistedSession();
        session = null;
      }
    } catch (_) {
      await _clearPersistedSession();
      session = null;
      profile = null;
      subscription = null;
      plans = const <PlanSummary>[];
      errorMessage = '自动恢复登录态失败，请重新登录。';
    } finally {
      isRestoring = false;
      notifyListeners();
    }
  }

  Future<bool> login({required String phone, required String password}) async {
    isLoggingIn = true;
    errorMessage = null;
    notifyListeners();

    try {
      session = await _apiService.login(phone: phone, password: password);
      await _persistSession();
      await refreshDashboard();
      return true;
    } on ApiException catch (error) {
      errorMessage = error.message;
      return false;
    } catch (_) {
      errorMessage = '无法连接后端服务，请检查 API 地址和网络。';
      return false;
    } finally {
      isLoggingIn = false;
      notifyListeners();
    }
  }

  Future<bool> register({
    required String phone,
    required String password,
    required String displayName,
  }) async {
    isRegistering = true;
    errorMessage = null;
    notifyListeners();

    try {
      session = await _apiService.register(
        phone: phone,
        password: password,
        displayName: displayName,
      );
      await _persistSession();
      await refreshDashboard();
      return true;
    } on ApiException catch (error) {
      errorMessage = error.message;
      return false;
    } catch (_) {
      errorMessage = '无法连接后端服务，请检查 API 地址和网络。';
      return false;
    } finally {
      isRegistering = false;
      notifyListeners();
    }
  }

  Future<void> refreshDashboard() async {
    final currentSession = session;
    if (currentSession == null) {
      return;
    }

    isRefreshing = true;
    errorMessage = null;
    notifyListeners();

    try {
      profile = await _apiService.getMe(
        accessToken: currentSession.accessToken,
      );
      plans = await _apiService.getPlans();
      subscription = await _apiService.getSubscription(
        accessToken: currentSession.accessToken,
      );
    } on ApiException catch (error) {
      errorMessage = error.message;
    } catch (_) {
      errorMessage = '基础数据拉取失败，请稍后重试。';
    } finally {
      isRefreshing = false;
      notifyListeners();
    }
  }

  void clearError() {
    errorMessage = null;
    notifyListeners();
  }

  Future<void> logout() async {
    await _clearPersistedSession();
    await _apiService.clearLocalContentCache();
    session = null;
    profile = null;
    subscription = null;
    plans = const <PlanSummary>[];
    errorMessage = null;
    notifyListeners();
  }

  Future<void> _persistSession() async {
    final currentSession = session;
    if (currentSession == null) {
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _sessionPrefsKey,
      jsonEncode(currentSession.toJson()),
    );
  }

  Future<void> _clearPersistedSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_sessionPrefsKey);
  }
}
