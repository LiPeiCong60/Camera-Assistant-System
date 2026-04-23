# mobile_client

Camera Assistant Flutter 手机端。

## 职责

- 用户登录、注册和登录态恢复。
- 首页展示用户、套餐和快捷入口。
- 拍摄页提供相机预览、模板叠加、普通拍摄、模板引导、背景分析和连拍选优。
- 历史页展示拍摄会话、抓拍记录和 AI 选优结果。
- 设备联动页直接连接 `device_runtime`，控制本地云台和套用 AI 建议。

## 目录

| 目录 | 说明 |
| --- | --- |
| `lib/app` | App 启动、主题和登录态路由。 |
| `lib/features` | 页面和功能模块。 |
| `lib/models` | 后端和设备端响应模型。 |
| `lib/services` | 业务后端、设备端 API、缓存和图片解析。 |
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

真机联调时，把地址改成电脑或树莓派的局域网 IP。

## 关键服务

- `MobileApiService`：访问业务后端 `/api/mobile/*`。
- `DeviceApiService`：访问设备端 `/api/device/*`。
- `ApiClient`：封装 JSON envelope、错误翻译和 multipart 上传。
- `MobileCacheService`：缓存模板和历史记录。

## 权限

当前已经声明基础摄像头权限：

- Android：`CAMERA`
- iOS：`NSCameraUsageDescription`

## 测试

```powershell
flutter test
```
