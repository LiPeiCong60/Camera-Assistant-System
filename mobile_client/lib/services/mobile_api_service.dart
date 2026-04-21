import '../models/ai_task_summary.dart';
import '../models/auth_session.dart';
import '../models/batch_pick_result.dart';
import '../models/capture_record.dart';
import '../models/capture_session_summary.dart';
import '../models/capture_upload_result.dart';
import '../models/plan_summary.dart';
import '../models/subscription_info.dart';
import '../models/template_summary.dart';
import '../models/user_profile.dart';
import 'api_client.dart';
import 'mobile_cache_service.dart';

class MobileApiService {
  MobileApiService({required String apiBaseUrl})
    : _client = ApiClient(baseUrl: apiBaseUrl);

  final ApiClient _client;
  final MobileCacheService _cacheService = MobileCacheService();

  Future<AuthSession> login({
    required String phone,
    required String password,
  }) async {
    final data = await _client.postJson(
      '/mobile/auth/login',
      body: {'phone': phone, 'password': password},
    );
    return AuthSession.fromJson(data);
  }

  Future<AuthSession> register({
    required String phone,
    required String password,
    required String displayName,
  }) async {
    final data = await _client.postJson(
      '/mobile/auth/register',
      body: {
        'phone': phone,
        'password': password,
        'display_name': displayName,
      },
    );
    return AuthSession.fromJson(data);
  }

  Future<UserProfile> getMe({required String accessToken}) async {
    final data = await _client.getJson('/mobile/me', accessToken: accessToken);
    return UserProfile.fromJson(data);
  }

  Future<List<PlanSummary>> getPlans() async {
    final data = await _client.getJson('/mobile/plans');
    final items = (data['items'] as List<dynamic>? ?? <dynamic>[])
        .cast<Map<String, dynamic>>();
    return items.map(PlanSummary.fromJson).toList(growable: false);
  }

  Future<SubscriptionInfo?> getSubscription({
    required String accessToken,
  }) async {
    try {
      final data = await _client.getJson(
        '/mobile/subscription',
        accessToken: accessToken,
      );
      return SubscriptionInfo.fromJson(data);
    } on ApiException catch (error) {
      if (error.statusCode == 404) {
        return null;
      }
      rethrow;
    }
  }

  Future<CaptureSessionSummary> createCaptureSession({
    required String accessToken,
    int? deviceId,
    int? templateId,
    String mode = 'mobile_only',
    Map<String, dynamic> metadata = const <String, dynamic>{},
  }) async {
    final data = await _client.postJson(
      '/mobile/sessions',
      accessToken: accessToken,
      body: <String, dynamic>{
        'device_id': deviceId,
        'template_id': templateId,
        'mode': mode,
        'metadata': metadata,
      },
    );
    final session = CaptureSessionSummary.fromJson(data);
    await _cacheService.prependHistorySession(session);
    return session;
  }

  Future<CaptureRecord> createCapture({
    required String accessToken,
    required int sessionId,
    required String fileUrl,
    String captureType = 'single',
    String? thumbnailUrl,
    int? width,
    int? height,
    String storageProvider = 'local',
    bool isAiSelected = false,
    num? score,
    Map<String, dynamic> metadata = const <String, dynamic>{},
  }) async {
    final data = await _client.postJson(
      '/mobile/captures/upload',
      accessToken: accessToken,
      body: <String, dynamic>{
        'session_id': sessionId,
        'capture_type': captureType,
        'file_url': fileUrl,
        'thumbnail_url': thumbnailUrl,
        'width': width,
        'height': height,
        'storage_provider': storageProvider,
        'is_ai_selected': isAiSelected,
        'score': score,
        'metadata': metadata,
      },
    );
    final capture = CaptureRecord.fromJson(data);
    await _cacheService.prependHistoryCapture(capture);
    return capture;
  }

  Future<CaptureUploadResult> uploadCaptureFile({
    required String accessToken,
    required String filePath,
  }) async {
    final data = await _client.postMultipart(
      '/mobile/captures/file',
      accessToken: accessToken,
      fileField: 'file',
      filePath: filePath,
    );
    return CaptureUploadResult.fromJson(data);
  }

  Future<AiTaskSummary> analyzePhoto({
    required String accessToken,
    required int sessionId,
    required int captureId,
  }) async {
    final data = await _client.postJson(
      '/mobile/ai/analyze-photo',
      accessToken: accessToken,
      body: <String, dynamic>{'session_id': sessionId, 'capture_id': captureId},
    );
    return AiTaskSummary.fromJson(data);
  }

  Future<AiTaskSummary> analyzeBackground({
    required String accessToken,
    required int sessionId,
    required int captureId,
    int? deviceId,
  }) async {
    final data = await _client.postJson(
      '/mobile/ai/analyze-background',
      accessToken: accessToken,
      body: <String, dynamic>{
        'session_id': sessionId,
        'capture_id': captureId,
        'device_id': deviceId,
      },
    );
    return AiTaskSummary.fromJson(data);
  }

  Future<BatchPickResult> batchPick({
    required String accessToken,
    required int sessionId,
    required List<int> captureIds,
  }) async {
    final data = await _client.postJson(
      '/mobile/ai/batch-pick',
      accessToken: accessToken,
      body: <String, dynamic>{
        'session_id': sessionId,
        'capture_ids': captureIds,
      },
    );
    return BatchPickResult.fromJson(data);
  }

  Future<List<TemplateSummary>> listTemplates({
    required String accessToken,
  }) async {
    final data = await _client.getJson(
      '/mobile/templates',
      accessToken: accessToken,
    );
    final items = (data['items'] as List<dynamic>? ?? <dynamic>[])
        .cast<Map<String, dynamic>>();
    final templates = items
        .map(TemplateSummary.fromJson)
        .toList(growable: false);
    await _cacheService.writeTemplates(templates);
    return templates;
  }

  Future<TemplateSummary> createTemplate({
    required String accessToken,
    required String name,
    String templateType = 'pose',
    String? sourceImageUrl,
    String? previewImageUrl,
    Map<String, dynamic> templateData = const <String, dynamic>{},
  }) async {
    final data = await _client.postJson(
      '/mobile/templates',
      accessToken: accessToken,
      body: <String, dynamic>{
        'name': name,
        'template_type': templateType,
        'source_image_url': sourceImageUrl,
        'preview_image_url': previewImageUrl,
        'template_data': templateData,
      },
    );
    final template = TemplateSummary.fromJson(data);
    await _cacheService.upsertTemplate(template);
    return template;
  }

  Future<TemplateSummary> createTemplateFromPhoto({
    required String accessToken,
    required String name,
    required String filePath,
  }) async {
    final uploadResult = await uploadCaptureFile(
      accessToken: accessToken,
      filePath: filePath,
    );
    return createTemplate(
      accessToken: accessToken,
      name: name,
      sourceImageUrl: uploadResult.fileUrl,
      previewImageUrl: uploadResult.fileUrl,
    );
  }

  Future<TemplateSummary> deleteTemplate({
    required String accessToken,
    required int templateId,
  }) async {
    final data = await _client.deleteJson(
      '/mobile/templates/$templateId',
      accessToken: accessToken,
    );
    final template = TemplateSummary.fromJson(data);
    await _cacheService.removeTemplate(templateId);
    return template;
  }

  Future<List<CaptureSessionSummary>> getHistorySessions({
    required String accessToken,
  }) async {
    final data = await _client.getJson(
      '/mobile/history/sessions',
      accessToken: accessToken,
    );
    final items = (data['items'] as List<dynamic>? ?? <dynamic>[])
        .cast<Map<String, dynamic>>();
    final sessions = items
        .map(CaptureSessionSummary.fromJson)
        .toList(growable: false);
    await _cacheService.writeHistorySessions(sessions);
    return sessions;
  }

  Future<List<CaptureRecord>> getHistoryCaptures({
    required String accessToken,
  }) async {
    final data = await _client.getJson(
      '/mobile/history/captures',
      accessToken: accessToken,
    );
    final items = (data['items'] as List<dynamic>? ?? <dynamic>[])
        .cast<Map<String, dynamic>>();
    final captures = items.map(CaptureRecord.fromJson).toList(growable: false);
    await _cacheService.writeHistoryCaptures(captures);
    return captures;
  }

  Future<List<TemplateSummary>> getCachedTemplates() {
    return _cacheService.readTemplates();
  }

  Future<List<CaptureSessionSummary>> getCachedHistorySessions() {
    return _cacheService.readHistorySessions();
  }

  Future<List<CaptureRecord>> getCachedHistoryCaptures() {
    return _cacheService.readHistoryCaptures();
  }

  Future<void> clearLocalContentCache() {
    return _cacheService.clearContentCache();
  }
}
