import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mobile_client/app/camera_assistant_app.dart';

void main() {
  testWidgets('login shell renders', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await tester.pumpWidget(const CameraAssistantApp());
    await tester.pumpAndSettle();

    expect(find.text('Camera\nAssistant'), findsOneWidget);
    expect(find.text('登录'), findsOneWidget);
  });
}
