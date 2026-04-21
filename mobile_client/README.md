# mobile_client

Flutter 手机端工程。

当前阶段已完成：
- Flutter 正常工程初始化
- `lib/app`、`lib/features`、`lib/services`、`lib/models` 骨架
- 手机端最小登录闭环
- `me / plans / subscription` 基础接口接入
- 摄像头预览与基础拍照页

本地运行示例：

```bash
flutter pub get
flutter run --dart-define=API_BASE_URL=http://127.0.0.1:8000/api
```

如果使用真机联调，请把 `API_BASE_URL` 改成后端所在机器的局域网地址。

当前移动端已声明基础摄像头权限：
- Android: `CAMERA`
- iOS: `NSCameraUsageDescription`

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
