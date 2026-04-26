# ????

???? 是一个面向手机拍摄辅助、设备联动、AI 图片分析和运营管理的多端项目。当前仓库由 `mobile_client`、`device_runtime`、`backend`、`admin_web`、`database` 五部分组成。

设备联动主视频链路已经改为 WebRTC：Flutter App 使用 `flutter_webrtc` 把手机摄像头 video track 推到 `device_runtime`，设备端使用 Python `aiortc` 接收并转成 OpenCV frame，继续进入检测、骨架、构图、云台控制和预览渲染流程，再通过 WebRTC 返回处理后的预览 video track。旧的 WebSocket NV21 推流、WebSocket JPEG 预览和 JPEG fallback 接口仍保留。

## 模块

| 模块 | 技术栈 | 作用 |
| --- | --- | --- |
| `backend` | FastAPI, SQLAlchemy, PostgreSQL | 业务 API、鉴权、上传文件、AI Provider 调用、数据落库 |
| `mobile_client` | Flutter, camera, flutter_webrtc | 登录、拍摄、模板管理、历史记录、设备联动、WebRTC 推流 |
| `device_runtime` | FastAPI, OpenCV, MediaPipe, aiortc, pyserial | 树莓派/本机运行端、检测跟踪、云台控制、WebRTC 预览、抓拍 |
| `admin_web` | Vue 3, Vite, Element Plus, Pinia | 用户、套餐、设备、推荐模板、AI 配置、抓拍和任务管理 |
| `database` | PostgreSQL SQL | 核心表结构、索引和触发器 |

## 推荐阅读顺序

1. [技术架构与运行机制详解](./docs/%E6%8A%80%E6%9C%AF%E6%9E%B6%E6%9E%84%E4%B8%8E%E8%BF%90%E8%A1%8C%E6%9C%BA%E5%88%B6%E8%AF%A6%E8%A7%A3.md)
2. [项目总览与架构说明](./docs/%E9%A1%B9%E7%9B%AE%E6%80%BB%E8%A7%88%E4%B8%8E%E6%9E%B6%E6%9E%84%E8%AF%B4%E6%98%8E.md)
3. [接口契约](./docs/%E6%8E%A5%E5%8F%A3%E5%A5%91%E7%BA%A6.md)
4. [部署说明](./docs/%E9%83%A8%E7%BD%B2%E8%AF%B4%E6%98%8E.md)
5. [统一采集存储与协同流程](./docs/%E7%BB%9F%E4%B8%80%E9%87%87%E9%9B%86%E5%AD%98%E5%82%A8%E4%B8%8E%E5%8D%8F%E5%90%8C%E6%B5%81%E7%A8%8B.md)
6. [AI 照片分析链路说明](./docs/AI%E7%85%A7%E7%89%87%E5%88%86%E6%9E%90%E9%93%BE%E8%B7%AF%E8%AF%B4%E6%98%8E.md)
7. [演示流程](./docs/%E6%BC%94%E7%A4%BA%E6%B5%81%E7%A8%8B.md)

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

### device_runtime

```powershell
cd device_runtime
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
$env:DEVICE_SERVO_DRIVER="mock"
uvicorn device_runtime.api.app:app --reload --host 0.0.0.0 --port 8001
```

`device_runtime/main.py` 是占位入口，真实本地控制 API 从 `device_runtime.api.app:app` 启动。

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

Android 模拟器访问宿主机时通常需要把 `127.0.0.1` 改为 `10.0.2.2`。真机联调必须改为电脑或树莓派的局域网 IP，例如：

```powershell
flutter run `
  --dart-define=API_BASE_URL=http://192.168.1.20:8000/api `
  --dart-define=DEVICE_API_BASE_URL=http://192.168.1.30:8001
```

## WebRTC 设备联动

设备联动页打开 `mobile_push` 会话后，主路径如下：

```text
手机摄像头 -> flutter_webrtc -> POST /api/device/webrtc/offer signaling
-> aiortc 接收 video track -> OpenCV frame -> 检测/构图/云台/预览
-> aiortc preview video track -> RTCVideoView
```

保留的 fallback：

- `WS /api/device/stream/mobile-ws`：手机发送 NV21 帧。
- `WS /api/device/preview-ws`：设备返回 JPEG 预览帧。
- `POST /api/device/stream/frame`：调试用单帧 JPEG 上传。
- `GET /api/device/preview.jpg`：调试用单张 JPEG 预览。

## 重启提示

改动依赖或视频链路后需要重启对应服务：

- `device_runtime` 新增或更新 `aiortc`、`websockets`、OpenCV 等依赖后，重新 `pip install -r requirements.txt` 并重启 `uvicorn`。
- Flutter 新增或更新 `flutter_webrtc`、Android 权限、Gradle 配置后，需要重新 `flutter pub get` 并重新安装 APK。
- backend/admin_web 改依赖或配置后，也分别重启对应服务。

## 不应提交的内容

- `.venv`、`node_modules`、Flutter/Android 构建产物。
- 本地缓存、日志、IDE 配置。
- 用户上传图片、抓拍样本、演示视频。
- 本地模型权重、MediaPipe 缓存和可重新下载的运行时资产。
- 真实数据库口令、测试账号、私有密钥和本地 `.env`。
