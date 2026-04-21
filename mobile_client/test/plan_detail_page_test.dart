import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile_client/features/auth/auth_controller.dart';
import 'package:mobile_client/features/home/home_page.dart';
import 'package:mobile_client/models/auth_session.dart';
import 'package:mobile_client/models/capture_record.dart';
import 'package:mobile_client/models/plan_summary.dart';
import 'package:mobile_client/models/subscription_info.dart';
import 'package:mobile_client/models/user_profile.dart';
import 'package:mobile_client/services/mobile_api_service.dart';

class _FakeMobileApiService extends MobileApiService {
  _FakeMobileApiService({required this.historyCaptures})
    : super(apiBaseUrl: 'http://127.0.0.1');

  final List<CaptureRecord> historyCaptures;

  @override
  Future<List<CaptureRecord>> getHistoryCaptures({
    required String accessToken,
  }) async {
    return historyCaptures;
  }
}

void main() {
  testWidgets(
    'plan details support current subscription and package selection',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(430, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final apiService = _FakeMobileApiService(
        historyCaptures: <CaptureRecord>[
          CaptureRecord(
            id: 1,
            sessionId: 11,
            userId: 1,
            captureType: 'single',
            fileUrl: 'https://example.com/1.jpg',
            storageProvider: 'local_static',
            isAiSelected: false,
            createdAt: DateTime(2026, 4, 20),
          ),
        ],
      );
      final controller = AuthController(apiService: apiService)
        ..session = const AuthSession(
          accessToken: 'token',
          tokenType: 'bearer',
          user: AuthUserSummary(
            id: 1,
            displayName: '测试用户',
            role: 'user',
            status: 'active',
          ),
        )
        ..profile = const UserProfile(
          id: 1,
          userCode: 'USR_0001',
          displayName: '测试用户',
          role: 'user',
          status: 'active',
        )
        ..plans = const <PlanSummary>[
          PlanSummary(
            id: 1,
            planCode: 'BASIC_MONTHLY',
            name: '入门版',
            description: '适合日常拍摄使用。',
            priceCents: 1000,
            currency: 'CNY',
            billingCycleDays: 30,
            captureQuota: 10,
            aiTaskQuota: 5,
            featureFlags: <String, dynamic>{'background_lock': true},
            status: 'active',
          ),
          PlanSummary(
            id: 2,
            planCode: 'PRO_MONTHLY',
            name: '专业版',
            description: '适合更高频率的拍摄场景。',
            priceCents: 2000,
            currency: 'CNY',
            billingCycleDays: 30,
            captureQuota: 30,
            aiTaskQuota: 15,
            featureFlags: <String, dynamic>{'batch_pick': true},
            status: 'active',
          ),
        ]
        ..subscription = SubscriptionInfo(
          id: 100,
          userId: 1,
          planId: 1,
          status: 'active',
          startedAt: DateTime(2026, 4, 19),
          expiresAt: DateTime(2026, 5, 19),
          autoRenew: false,
          quotaSnapshot: const <String, dynamic>{
            'capture_quota': 10,
            'ai_task_quota': 5,
          },
        );

      await tester.pumpWidget(
        MaterialApp(home: HomePage(controller: controller)),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('当前订阅'));
      await tester.pumpAndSettle();

      expect(find.text('套餐详情'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('续费套餐'),
        200,
        scrollable: find.byType(Scrollable).last,
      );
      expect(find.text('续费套餐'), findsOneWidget);
      expect(find.text('重置额度'), findsOneWidget);
      expect(find.text('剩余拍摄额度'), findsOneWidget);

      await tester.tap(find.text('专业版'));
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('购买套餐'),
        200,
        scrollable: find.byType(Scrollable).last,
      );
      expect(find.text('购买套餐'), findsOneWidget);
      expect(find.textContaining('已选中购买 专业版'), findsOneWidget);
    },
  );
}
