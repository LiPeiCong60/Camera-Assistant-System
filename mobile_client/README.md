# mobile_client

Camera Assistant Flutter 手机端，负责登录、拍摄、模板、历史和设备联动。设备联动主视频链路已改为 WebRTC：手机通过 `flutter_webrtc` 把摄像头 video track 推给 `device_runtime`，并显示设备端返回的处理后预览 video track。

## 职责

- 用户登录、注册和登录态恢复。
- 首页展示用户、套餐和快捷入口。
- 拍摄页提供相机预览、模板叠加、普通拍摄、模板引导、背景分析和连拍选优。
- 历史页展示拍摄会话、抓拍记录和 AI 选优结果。
- 设置页维护“业务后台地址”和“设备运行时地址”。
- 设备联动页连接 `device_runtime`，打开设备会话、控制云台、套用 AI 建议、WebRTC 推流和预览。

## 目录

| 目录 | 说明 |
| --- | --- |
| `lib/app` | App 启动、主题和登录态路由。 |
| `lib/features` | 页面和功能模块。 |
| `lib/models` | 后端和设备端响应模型。 |
| `lib/services` | 业务后端、设备端 API、WebRTC、缓存和图片解析。 |
| `test` | Flutter 测试。 |

## 启动

```powershell
cd mobile_client
flutter pub get
flutter run `
  --dart-define=API_BASE_URL=http://127.0.0.1:8000/api `
  --dart-define=DEVICE_API_BASE_URL=http://127.0.0.1:8001
```

Android 模拟器访问宿主机时通常使用：

```powershell
flutter run `
  --dart-define=API_BASE_URL=http://10.0.2.2:8000/api `
  --dart-define=DEVICE_API_BASE_URL=http://10.0.2.2:8001
```

真机联调时必须改成电脑或树莓派的局域网 IP：

```powershell
flutter run `
  --dart-define=API_BASE_URL=http://192.168.1.20:8000/api `
  --dart-define=DEVICE_API_BASE_URL=http://192.168.1.30:8001
```

不要在真机上使用 `127.0.0.1` 或 `10.0.2.2`。

## 关键服务

- `MobileApiService`：访问业务后端 `/api/mobile/*`。
- `DeviceApiService`：访问设备端 `/api/device/*`。
- `DeviceWebRtcService`：创建 WebRTC offer、调用 `/api/device/webrtc/offer`、推送本机摄像头 video track、接收设备预览 video track。
- `ApiClient`：封装 JSON envelope、错误翻译和 multipart 上传。
- `MobileCacheService`：缓存模板和历史记录。

## 设备联动视频链路

主链路：

```text
getUserMedia(camera)
-> flutter_webrtc local video track
-> POST /api/device/webrtc/offer
-> device_runtime aiortc
-> OpenCV frame / detector / overlay
-> WebRTC preview video track
-> RTCVideoView
```

fallback：

- 上行 `WS /api/device/stream/mobile-ws`，发送 Android NV21 帧。
- 下行 `WS /api/device/preview-ws`，接收 JPEG 预览。
- 调试接口 `POST /api/device/stream/frame` 和 `GET /api/device/preview.jpg`。

## Android 权限和 cleartext

`android/app/src/main/AndroidManifest.xml` 当前包含：

- `INTERNET`
- `CAMERA`
- `RECORD_AUDIO`
- `ACCESS_NETWORK_STATE`
- `CHANGE_NETWORK_STATE`
- `MODIFY_AUDIO_SETTINGS`
- `android:usesCleartextTraffic="true"`

WebRTC 只推视频，但部分 Android WebRTC 实现仍需要音频相关权限或音频设置权限才能稳定初始化。局域网 HTTP 调试依赖 cleartext 配置。

## 构建和测试

```powershell
flutter analyze
flutter test
flutter build apk --debug
```

debug APK 输出位置：

```text
mobile_client/build/app/outputs/flutter-apk/app-debug.apk
```
