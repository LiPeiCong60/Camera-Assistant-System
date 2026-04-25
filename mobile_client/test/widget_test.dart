import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mobile_client/app/camera_assistant_app.dart';

void main() {
  testWidgets('server config renders before login', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await tester.pumpWidget(const CameraAssistantApp());
    await tester.pumpAndSettle();

    expect(find.text('后台连接设置'), findsOneWidget);
    expect(find.text('保存并继续'), findsOneWidget);
  });

  testWidgets('login shell renders after server config is saved', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'server_config.api_base_url': 'http://127.0.0.1:8000/api',
      'server_config.device_api_base_url': 'http://127.0.0.1:8001',
    });
    await tester.pumpWidget(const CameraAssistantApp());
    await tester.pumpAndSettle();

    expect(find.text('Camera\nAssistant'), findsOneWidget);
    expect(find.text('登录'), findsOneWidget);
  });
}
