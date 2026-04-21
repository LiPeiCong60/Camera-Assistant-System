import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mobile_client/services/api_client.dart';
import 'package:mobile_client/services/device_api_service.dart';
import 'package:mobile_client/services/mobile_api_service.dart';

void main() {
  test('network failures return human-readable messages', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});

    final mobile = MobileApiService(apiBaseUrl: 'http://127.0.0.1:65530/api');
    const device = DeviceApiService();

    await expectLater(
      () => mobile.login(phone: '13900000000', password: 'example-password'),
      throwsA(
        isA<ApiException>().having(
          (error) => error.message,
          'message',
          '无法连接服务，请确认服务已启动且地址可访问。',
        ),
      ),
    );

    await expectLater(
      () => mobile.getPlans(),
      throwsA(
        isA<ApiException>().having(
          (error) => error.message,
          'message',
          '无法连接服务，请确认服务已启动且地址可访问。',
        ),
      ),
    );

    await expectLater(
      () => mobile.analyzePhoto(
        accessToken: 'demo-token',
        sessionId: 1,
        captureId: 1,
      ),
      throwsA(
        isA<ApiException>().having(
          (error) => error.message,
          'message',
          '无法连接服务，请确认服务已启动且地址可访问。',
        ),
      ),
    );

    await expectLater(
      () => device.getHealth(baseUrl: 'http://127.0.0.1:65531'),
      throwsA(
        isA<ApiException>().having(
          (error) => error.message,
          'message',
          '无法连接设备，请确认本地运行时服务已启动且地址正确。',
        ),
      ),
    );
  });
}
