# 云影随行

云影随行是一个面向手机拍摄辅助、树莓派设备联动、AI 图片分析和运营管理的多端项目。仓库由五个主要模块组成：

| 模块 | 技术栈 | 作用 |
| --- | --- | --- |
| `mobile_client` | Flutter, camera, flutter_webrtc | 手机 App：登录、拍摄、模板、历史、设备联动、设备本地抓拍控制 |
| `device_runtime` | FastAPI, OpenCV, MediaPipe, aiortc, pyserial | 树莓派/本机运行时：视频处理、骨骼/手部检测、云台控制、手势抓拍、设备端 AI |
| `backend` | FastAPI, SQLAlchemy, PostgreSQL | 业务后端：账号、套餐、模板、历史、上传文件、AI Provider 和管理接口 |
| `admin_web` | Vue 3, Vite, Element Plus, Pinia | 管理后台：用户、套餐、设备、模板、抓拍记录、AI 任务、Provider 配置 |
| `database` | PostgreSQL SQL | 核心表结构、约束、索引和触发器 |

当前设备联动的默认手机推流链路是 Android `camera` 图像流通过 WebSocket 发送 NV21 帧到 `device_runtime`，设备端处理后通过 JPEG 预览 WebSocket 回传。仓库中同时保留 WebRTC signaling 和 `flutter_webrtc`/`aiortc` 支持，用于后续切换或实验。

## 当前关键能力

- 手机端独立拍照、模板引导、历史记录、AI 图片分析、连拍选优。
- 手机端设备联动页可连接树莓派运行时，控制云台、跟随模式、模板构图、设备本地 AI 和抓拍。
- 设备端支持人体骨骼、手部骨骼、人脸网格、跟踪锚点和 overlay 开关。
- 手势抓拍支持 3 秒倒计时，设备端预览和手机端 HUD 都会显示提示。
- 设备端抓拍默认保存到 `device_runtime/captures`，不再自动同步到后端历史记录。
- 后端历史记录仍服务于手机端独立拍摄和后台 AI 任务。
- 管理后台可维护用户、套餐、推荐模板、设备、抓拍记录、AI 任务和 AI Provider。

## 推荐阅读

1. [项目总览与架构说明](./docs/项目总览与架构说明.md)
2. [技术架构与运行机制详解](./docs/技术架构与运行机制详解.md)
3. [接口契约](./docs/接口契约.md)
4. [部署说明](./docs/部署说明.md)
5. [统一采集存储与协同流程](./docs/统一采集存储与协同流程.md)
6. [AI 照片分析链路说明](./docs/AI照片分析链路说明.md)
7. [演示流程](./docs/演示流程.md)

## 快速启动

### backend

```powershell
cd backend
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt

$env:DATABASE_URL="postgresql+psycopg://postgres:postgres@127.0.0.1:5432/camera_assistant"
$env:BACKEND_AUTH_SECRET="change-this-in-real-env"

python init_db.py
uvicorn backend.app.main:app --reload --host 0.0.0.0 --port 8000
```

健康检查：

```powershell
curl http://127.0.0.1:8000/api/health
```

### device_runtime

```powershell
cd device_runtime
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt

$env:DEVICE_SERVO_DRIVER="mock"
uvicorn device_runtime.api.app:app --reload --host 0.0.0.0 --port 8001
```

树莓派现场建议使用性能档：

```bash
export DEVICE_RPI_PROFILE=performance
export DEVICE_SERVO_DRIVER=ttl_bus
export DEVICE_TTL_SERIAL_PORT=/dev/ttyUSB0
uvicorn device_runtime.api.app:app --host 0.0.0.0 --port 8001
```

### admin_web

```powershell
cd admin_web
npm install
$env:VITE_API_BASE_URL="http://127.0.0.1:8000/api"
npm run dev
```

默认访问 `http://127.0.0.1:5173`。

### mobile_client

```powershell
cd mobile_client
flutter pub get
flutter run `
  --dart-define=API_BASE_URL=http://127.0.0.1:8000/api `
  --dart-define=DEVICE_API_BASE_URL=http://127.0.0.1:8001
```

Android 模拟器访问电脑服务时通常使用 `10.0.2.2`。真机联调必须改为电脑或树莓派的局域网 IP：

```powershell
flutter run `
  --dart-define=API_BASE_URL=http://192.168.1.20:8000/api `
  --dart-define=DEVICE_API_BASE_URL=http://192.168.1.30:8001
```

构建 APK：

```powershell
cd mobile_client
flutter build apk --release
```

输出路径：

```text
mobile_client/build/app/outputs/flutter-apk/app-release.apk
```

## 设备联动链路

当前手机端默认链路：

```text
Android camera ImageStream
-> NV21 WebSocket /api/device/stream/mobile-ws
-> device_runtime OpenCV frame
-> MediaPipe / tracking / overlay / gimbal / capture
-> JPEG WebSocket /api/device/preview-ws
-> mobile_client preview
```

保留的备用/实验链路：

- `POST /api/device/webrtc/offer`：WebRTC signaling。
- `POST /api/device/stream/frame`：调试用单帧上传。
- `GET /api/device/preview.jpg`：调试用单张预览。

## 树莓派运行提示

修改 `device_runtime` 代码、依赖、检测配置默认值、手势抓拍或云台驱动后，需要重新启动树莓派上的 `uvicorn` 服务。只改手机端 UI 或后端管理功能时，不需要重启树莓派，但需要重新安装/运行手机 App 或重启对应服务。

如果现场很卡，优先降低设备端负载：

- 使用 `DEVICE_RPI_PROFILE=performance`。
- 降低 `DEVICE_MAX_INFERENCE_SIDE`、`DEVICE_DETECTOR_FPS`、`DEVICE_PREVIEW_SCALE`。
- 只在需要时打开人体骨骼、手部骨骼和人脸网格。
- 使用 5GHz Wi-Fi，或让树莓派开热点给手机直连。

## 安全和隐私

不要提交以下内容：

- `.env`、真实数据库口令、后台 JWT/认证密钥、AI Provider API key。
- `.venv`、`node_modules`、Flutter/Android 构建产物。
- `uploads`、`captures`、演示照片、用户照片、日志和本地数据库。
- 本地模型权重、MediaPipe 缓存和可重新下载的运行时资源。

`.gitignore` 已覆盖这些目录和文件。提交前仍建议执行一次：

```powershell
git status --ignored --short
git diff --check
```
