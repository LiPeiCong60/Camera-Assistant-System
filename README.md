# 云影随行 Camera Assistant

云影随行是一个面向手机拍摄辅助、树莓派云台联动、云端 AI 构图分析和后台管理的多端项目。当前架构原则是：

```text
手机负责画面，树莓派负责转动，服务器负责智能，后台负责管理。
```

也就是说，设备联动时主画面仍然来自手机本地摄像头；树莓派接收手机推送的低延迟帧做检测、跟踪和云台控制，但不作为主预览画面的来源。AI Provider 和大模型 Key 统一配置在业务后端，手机端和树莓派端不保存生产 AI Key。

## 模块

| 模块 | 技术栈 | 当前职责 |
| --- | --- | --- |
| `mobile_client` | Flutter, Dart, camera, ML Kit, WebSocket, SharedPreferences | 手机 App：登录、首页、拍摄、录像、模板构图、历史、详细设置、设备联动主画面、相册保存、手机端视觉 overlay、AI 多角度扫描主控 |
| `device_runtime` | Python, FastAPI, OpenCV, MediaPipe, pyserial, WebSocket, aiortc | 树莓派/本机运行时：TTL 总线舵机云台、手动控制、自动跟随、模板跟随、手机帧接收、本地检测、手势抓拍兼容接口 |
| `backend` | Python, FastAPI, SQLAlchemy, PostgreSQL, httpx, Pydantic | 业务后端：用户、套餐、订阅、设备、模板、拍摄会话、媒体记录、AI 任务、AI Provider 调用 |
| `admin_web` | Vue 3, Vite, Element Plus, Pinia, Axios | 管理后台：用户、套餐、推荐模板、设备、媒体记录、AI 任务、AI Provider 配置 |
| `database` | PostgreSQL SQL | 数据表、约束、索引、触发器和兼容旧库的结构说明 |

## 当前主要能力

- 手机端普通拍照、录像、模板构图、背景分析、AI 连拍选优、历史记录。
- 手机端详细设置页集中管理高级参数，普通拍摄页和设备联动页只保留常用入口。
- 模板上传后由手机本地 ML Kit 识别人像关键点，生成模板框、骨架线、肩部中心点、面部中心点等归一化结构。
- 设备联动页主画面使用手机本地 `CameraPreview`，所有视觉叠加在手机端绘制。
- 设备联动页可手动控制云台、自动跟随、模板构图、选择跟随肩部/人脸中心点。
- 设备联动页拍照和录像由手机相机完成，照片/视频保存到手机相册；按设置可在拍照后上传后端并触发云端 AI 分析。
- AI 自动找角度和背景锁定由手机做主控：手机指挥云台扫描多个角度、缓存候选帧、统一上传后端 AI 分析，再让树莓派转到最佳角度。
- 后端统一管理 AI Provider，支持 OpenAI-compatible 视觉模型调用和失败降级记录。
- 管理后台可查看用户、套餐、媒体记录、AI 任务，并维护多个 AI Provider 配置。

## 推荐阅读

当前保留并维护的文档：

1. [技术栈详解](./docs/技术栈详解.md)
2. [接口契约](./docs/接口契约.md)
3. [部署说明](./docs/部署说明.md)
4. [统一采集存储与协同流程](./docs/统一采集存储与协同流程.md)
5. [演示流程](./docs/演示流程.md)
6. [mobile_client 说明](./mobile_client/README.md)
7. [device_runtime 说明](./device_runtime/README.md)
8. [backend 说明](./backend/README.md)
9. [admin_web 说明](./admin_web/README.md)
10. [database 说明](./database/README.md)

## 快速启动

### 1. backend

```powershell
cd <repo-root>
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r backend\requirements.txt

$env:DATABASE_URL="postgresql+psycopg://postgres:<db_password>@127.0.0.1:5432/camera_assistant"
$env:BACKEND_AUTH_SECRET="<random-secret>"

python backend\init_db.py
uvicorn backend.app.main:app --reload --host 0.0.0.0 --port 8000
```

健康检查：

```powershell
curl http://127.0.0.1:8000/api/health
```

### 2. device_runtime

Windows 本机无硬件调试：

```powershell
cd <repo-root>
.\.venv\Scripts\Activate.ps1
pip install -r device_runtime\requirements.txt

$env:DEVICE_SERVO_DRIVER="mock"
uvicorn device_runtime.api.app:app --reload --host 0.0.0.0 --port 8001
```

树莓派现场运行：

```bash
cd ~/camera_assistant_pi
source .venv/bin/activate

export DEVICE_RPI_PROFILE=performance
export DEVICE_SERVO_DRIVER=ttl_bus
export DEVICE_TTL_SERIAL_PORT=/dev/ttyUSB0
export DEVICE_PAN_SERVO_ID=0
export DEVICE_TILT_SERVO_ID=1

python -m uvicorn device_runtime.api.app:app --host 0.0.0.0 --port 8001
```

### 3. admin_web

```powershell
cd <repo-root>\admin_web
npm install
$env:VITE_API_BASE_URL="http://127.0.0.1:8000/api"
npm run dev
```

默认访问 `http://127.0.0.1:5173`。

### 4. mobile_client

```powershell
cd <repo-root>\mobile_client
flutter pub get
flutter run `
  --dart-define=API_BASE_URL=http://127.0.0.1:8000/api `
  --dart-define=DEVICE_API_BASE_URL=http://127.0.0.1:8001
```

Android 真机联调必须把地址换成电脑或树莓派的局域网 IP：

```powershell
flutter run `
  --dart-define=API_BASE_URL=http://192.168.1.20:8000/api `
  --dart-define=DEVICE_API_BASE_URL=http://192.168.1.30:8001
```

构建 APK：

```powershell
cd <repo-root>\mobile_client
flutter build apk --release
```

输出路径：

```text
mobile_client/build/app/outputs/flutter-apk/app-release.apk
```

## 设备联动主链路

```text
手机 CameraPreview 作为主画面
手机 ImageStream 抽帧
-> WebSocket /api/device/stream/mobile-ws
-> device_runtime OpenCV/MediaPipe 检测
-> device_runtime 计算跟踪目标和云台命令
-> TTL 总线舵机执行转动
-> device_runtime 状态接口返回检测/跟踪/手势/AI 锁定状态
-> mobile_client 以 0-1 归一化坐标绘制 overlay
```

`device_runtime` 仍保留 `preview-ws`、`preview.jpg` 和 WebRTC signaling，主要用于调试、兼容或后续实验；产品主流程不依赖树莓派回传画面作为主预览。

## AI 主链路

```text
mobile_client 拍摄/缓存图片
-> backend /api/mobile/ai/*
-> backend 读取 AI Provider 配置
-> OpenAI-compatible 视觉模型
-> backend 写 ai_tasks
-> mobile_client 展示结果、推荐框、最佳候选和原因
```

设备联动中的“自动找角度”和“背景锁定”也是手机主控：手机控制树莓派扫描候选角度，缓存多张候选图，统一发给后端 AI 分析，然后转回评分最高的角度。背景锁定会使用后端返回的 `target_box_norm` 在手机端绘制推荐框。

## 安全和隐私

不要提交以下内容：

- `.env`、真实数据库密码、认证密钥、AI Provider API Key。
- `uploads/`、`captures/`、用户照片、演示照片、视频、日志、本地数据库。
- `.venv/`、`node_modules/`、Flutter/Android/iOS 构建产物。
- `.claude/`、`.deepseek/`、`refactor_workspace/` 等本地工具上下文。
- 本地模型权重、MediaPipe 下载缓存和可重新生成的运行时资源。

提交前建议执行：

```powershell
git status --ignored --short
git diff --check
```
