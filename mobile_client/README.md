# mobile_client

`mobile_client` 是 Flutter 手机端，负责登录、拍摄、模板、历史、设置和设备联动。它同时访问两个服务：

- 业务后端：`backend`，默认 base URL 形如 `http://host:8000/api`。
- 设备运行时：`device_runtime`，默认 base URL 形如 `http://host:8001`。

## 职责

- 用户登录、注册和登录态恢复。
- 首页展示用户、套餐和快捷入口。
- 拍摄页提供相机预览、模板引导、普通拍摄、背景分析、连拍选优。
- 历史页展示后端拍摄会话、抓拍记录和 AI 结果。
- 设置页维护业务后端地址和设备运行时地址。
- 设备联动页连接树莓派运行时，控制云台、跟随、模板、overlay、手势抓拍和设备端 AI。

## 启动

```powershell
cd mobile_client
flutter pub get
flutter run `
  --dart-define=API_BASE_URL=http://127.0.0.1:8000/api `
  --dart-define=DEVICE_API_BASE_URL=http://127.0.0.1:8001
```

Android 模拟器访问宿主机服务时使用：

```powershell
flutter run `
  --dart-define=API_BASE_URL=http://10.0.2.2:8000/api `
  --dart-define=DEVICE_API_BASE_URL=http://10.0.2.2:8001
```

真机联调必须使用电脑或树莓派局域网 IP：

```powershell
flutter run `
  --dart-define=API_BASE_URL=http://192.168.1.20:8000/api `
  --dart-define=DEVICE_API_BASE_URL=http://192.168.1.30:8001
```

不要在真机上使用 `127.0.0.1` 或 `10.0.2.2`。

## 目录

| 目录 | 说明 |
| --- | --- |
| `lib/app` | App 启动、主题和登录态路由 |
| `lib/features` | 页面和业务功能 |
| `lib/models` | 后端和设备端响应模型 |
| `lib/services` | API、WebRTC、缓存、图片保存和配置 |
| `test` | Flutter 测试 |

## 关键服务

- `AppConfig`：读取 `API_BASE_URL`、`DEVICE_API_BASE_URL`，并保存用户在设置页填写的地址。
- `MobileApiService`：访问 `/api/mobile/*`。
- `DeviceApiService`：访问 `/api/device/*`。
- `DeviceWebRtcService`：封装 WebRTC offer 和远端 preview track。
- `MobileCacheService`：缓存模板和历史记录。
- `GallerySaveService`：保存图片到设备相册或本地文件。

## 设备联动现状

当前设备联动页默认启动 Android WebSocket 推流：

```text
CameraController.startImageStream
-> NV21 bytes
-> WS /api/device/stream/mobile-ws
-> device_runtime
-> WS /api/device/preview-ws
-> Flutter preview
```

WebRTC 服务代码仍在仓库中，但当前默认入口 `_startMobilePush()` 调用的是 WebSocket fallback。遇到卡顿时，优先从树莓派性能档、预览分辨率、检测开关和 Wi-Fi 环境排查。

## 设备抓拍和历史

设备联动页点击抓拍或触发手势抓拍时：

- 调用 `POST /api/device/capture/trigger`。
- 文件保存在设备端 `device_runtime/captures`。
- 手机端 HUD 显示最近抓拍路径和抓拍结果。
- 不再把设备抓拍同步到后端历史记录。
- “设备本地 AI 分析”只影响设备端本地 AI，不调用后端 `/api/mobile/ai/analyze-photo`。

后端历史页仍显示手机独立拍摄产生的 `captures` 和 `ai_tasks`。

## Android 权限和 cleartext

`android/app/src/main/AndroidManifest.xml` 当前包含：

- `INTERNET`
- `CAMERA`
- `RECORD_AUDIO`
- `ACCESS_NETWORK_STATE`
- `CHANGE_NETWORK_STATE`
- `MODIFY_AUDIO_SETTINGS`
- `android:usesCleartextTraffic="true"`

局域网 HTTP 调试依赖 cleartext 配置。部分 WebRTC 实现即使只推视频，也可能需要音频相关权限才能稳定初始化。

## 构建和测试

```powershell
cd mobile_client
flutter analyze
flutter test
flutter build apk --release
```

release APK 输出：

```text
mobile_client/build/app/outputs/flutter-apk/app-release.apk
```
