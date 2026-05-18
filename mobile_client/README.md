# mobile_client

`mobile_client` 是 Flutter 手机端，是当前产品体验的主入口。它负责用户操作、手机相机画面、拍照录像、模板管理、视觉叠加、设备联动主控和与后端 AI 的交互。

## 职责边界

- 负责主画面：拍摄页和设备联动页都以手机本地相机作为主画面。
- 负责最终媒体：照片和视频由手机相机拍摄，并优先保存到手机相册。
- 负责视觉叠加：人体框、骨架线、模板框、模板骨架、中心点、AI 推荐框都在手机端绘制。
- 负责模板识别：模板上传后优先使用手机本地 ML Kit 识别人像关键点。
- 负责设备联动主控：手动控制、自动跟随、模板构图、AI 扫描流程由手机发起和协调。
- 负责后端交互：登录、模板、历史、上传、AI 任务统一走 `backend`。
- 不保存 AI Key，不直接调用生产 AI Provider。

## 技术组成

| 技术 | 使用位置 | 作用 |
| --- | --- | --- |
| Flutter / Dart | 全 App | 跨平台 UI、状态和页面组织 |
| `camera` | 拍摄页、设备联动页 | CameraPreview、拍照、录像、ImageStream 抽帧 |
| Google ML Kit Pose Detection | 模板识别、实时人体关键点 | 识别肩部、面部相关点，生成归一化模板数据和实时跟随点 |
| `http` | `MobileApiService`、`DeviceApiService` | 调用后端和设备端 HTTP API |
| WebSocket | 设备联动手机帧推送 | 向 `device_runtime` 推送 NV21/JPEG 调试帧 |
| `flutter_webrtc` | 保留实验链路 | WebRTC signaling 和未来实时传输实验 |
| `image_picker` | 模板上传、相册选择 | 从相册选择模板或照片 |
| `path_provider` | 临时文件、缓存帧 | AI 扫描候选帧、临时图片处理 |
| `shared_preferences` | 设置页和服务地址 | 保存后端地址、设备地址、详细设置参数 |
| `image` | 图片编码/格式辅助 | 部分本地图像处理 |

## 主要页面

| 页面 | 文件 | 功能 |
| --- | --- | --- |
| 登录/注册 | `lib/features/auth` | 账号登录、注册、登录态恢复 |
| 首页 | `lib/features/home/home_page.dart` | 当前订阅、开始拍摄、设备联动、相册、详细设置入口 |
| 拍摄页 | `lib/features/camera/camera_capture_page.dart` | 普通拍照、录像、模板构图、AI 连拍、背景分析、相册保存、历史上传 |
| 设备联动页 | `lib/features/device_link/device_link_page.dart` | 手机本地预览、云台控制、自动跟随、模板构图、AI 扫描、手势抓拍状态 |
| 详细设置 | `lib/features/settings/detailed_settings_page.dart` | 分类折叠、搜索、常用/高级设置集中管理 |
| 历史页 | `lib/features/history/history_page.dart` | 后端会话、媒体记录、AI 结果查看 |

## 设备联动主流程

```text
CameraController 初始化手机摄像头
-> 页面显示手机本地 CameraPreview
-> startImageStream 抽取手机帧
-> /api/device/stream/mobile-ws 推给树莓派
-> 树莓派做检测、跟踪、云台控制
-> 手机轮询 /api/device/status 获取状态
-> 手机端用归一化坐标绘制 overlay
```

注意：

- 主画面不使用树莓派摄像头。
- 树莓派回传预览只保留为调试/兼容能力。
- 所有跨端视觉坐标都使用 `0..1` 归一化坐标。
- 默认预览不镜像；前置镜头、保存方向和 overlay 镜像分别处理。

## 拍照和录像

### 普通拍摄页

- 拍照后按设置保存到相册、上传后端历史。
- 录像后保存到相册；当前不强制写入历史。
- 拍摄设置页只保留常用项，高级项进入“详细设置”。

### 设备联动页

- 点击拍照时使用手机相机抓拍，不保存到树莓派。
- 抓拍照片保存到手机相册。
- 如果开启“拍照后 AI 分析”，手机会把照片上传到后端并创建 AI 任务。
- 点击录像时使用手机相机持续录像，自动跟随和模板构图仍继续工作。
- 录像结束后保存到手机相册，不要求写入后端历史。

设备端 `/api/device/capture/*` 仍作为兼容/调试接口存在，手势抓拍也可能通过设备端状态通知手机保存；产品主链路以手机最终拍摄为准。

## 模板构图

模板数据保存在后端 `templates.template_data`，手机端使用同一结构：

- `bbox`：人物主体框，归一化坐标。
- `head_box`：头部/面部框，归一化坐标。
- `points`：关键点字典，包含肩部、面部等点。
- `segments`：骨架线段。
- `shoulder_center`：肩部中心点。
- `face_center`：面部中心点。
- `source_image_url` / `image_path`：模板图片来源。

设备联动模板构图会根据用户选择的跟随目标，把实时人物的肩部中心点或面部中心点对齐到模板对应中心点。

## AI 自动找角度和背景锁定

设备联动 AI 流程由手机主控：

1. 手机读取详细设置中的扫描范围、候选数量、步进、稳定等待和启动倒计时。
2. 手机发云台移动命令，让树莓派依次转到候选角度。
3. 每个角度稳定后，手机用本地相机缓存一张候选帧。
4. 手机调用 `POST /api/mobile/ai/analyze-scan`，把候选帧和角度元数据发给后端。
5. 后端 AI 选择最佳候选，返回分数、原因、推荐角度和可选 `target_box_norm`。
6. 手机让树莓派转回最佳角度。
7. 自动找角度会把最佳候选图保存到手机相册；背景锁定会在手机端显示 AI 推荐框。

## 运行

```powershell
cd mobile_client
flutter pub get
flutter run `
  --dart-define=API_BASE_URL=http://127.0.0.1:8000/api `
  --dart-define=DEVICE_API_BASE_URL=http://127.0.0.1:8001
```

真机联调用局域网 IP：

```powershell
flutter run `
  --dart-define=API_BASE_URL=http://192.168.1.20:8000/api `
  --dart-define=DEVICE_API_BASE_URL=http://192.168.1.30:8001
```

## 检查和构建

```powershell
flutter analyze
flutter test
flutter build apk --release
```

APK 输出：

```text
mobile_client/build/app/outputs/flutter-apk/app-release.apk
```
