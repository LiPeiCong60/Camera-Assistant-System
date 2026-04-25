# device_runtime

Camera Assistant 设备运行时，面向树莓派或本机联调。它提供本地 FastAPI 控制接口，负责视频源读取、WebRTC 收发、人体检测、模板构图、云台控制、预览渲染、抓拍和设备端 AI 编排。

## 当前真实入口

```powershell
uvicorn device_runtime.api.app:app --reload --host 0.0.0.0 --port 8001
```

`main.py` 仍是占位提示，不是当前本地控制 API 的启动入口。

## 核心职责

- 打开和关闭本地设备会话。
- 使用 OpenCV 读取摄像头编号、RTSP、HTTP 视频流或本地文件。
- 在 `mobile_push` 会话中接收手机 WebRTC video track。
- 将 WebRTC `VideoFrame` 转为 OpenCV BGR frame，接入原有检测和预览流程。
- 保留 WebSocket NV21 推流、JPEG 预览和单帧上传作为 fallback。
- 使用 MediaPipe、可选 YOLO 或 OpenCV HOG 做人体/姿态检测。
- 在 `MANUAL`、`AUTO_TRACK`、`SMART_COMPOSE` 模式下管理跟踪和构图。
- 通过 TTL 总线舵机或 mock 驱动控制云台。
- 管理设备本地模板、抓拍、AI 背景锁和自动找角度。

## 目录

| 目录 | 说明 |
| --- | --- |
| `api` | FastAPI 路由、WebRTC signaling、单会话管理。 |
| `vision` | 视频源、检测器、异步检测封装。 |
| `control` | 跟踪控制和云台控制。 |
| `services` | 帧处理、控制、抓拍、模板、运行时状态、AI 编排。 |
| `templates` | 模板数据结构、构图评分、手势状态。 |
| `repositories` | 本地模板库读写。 |
| `utils` | overlay 渲染、通用类型、UI 文本。 |
| `tests` | 设备端测试。 |

## 本机 mock 启动

```powershell
cd device_runtime
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt

$env:DEVICE_SERVO_DRIVER="mock"
uvicorn device_runtime.api.app:app --reload --host 0.0.0.0 --port 8001
```

## 树莓派启动

```bash
cd device_runtime
python3 -m venv .venv
. .venv/bin/activate
pip install -r requirements.txt

export DEVICE_SERVO_DRIVER=ttl_bus
export DEVICE_TTL_SERIAL_PORT=/dev/ttyUSB0
export DEVICE_PAN_SERVO_ID=0
export DEVICE_TILT_SERVO_ID=1

uvicorn device_runtime.api.app:app --host 0.0.0.0 --port 8001
```

## WebRTC 视频链路

手机设备联动页会先打开设备会话：

```json
{
  "session_code": "mobile-session",
  "stream_url": "mobile_push",
  "mirror_view": true,
  "start_mode": "MANUAL"
}
```

然后通过 signaling 接口发送 offer：

```text
POST /api/device/webrtc/offer
```

请求：

```json
{
  "sdp": "...",
  "type": "offer"
}
```

响应：

```json
{
  "success": true,
  "message": "webrtc answer created",
  "data": {
    "sdp": "...",
    "type": "answer"
  }
}
```

设备端要求当前 session 的 `stream_url` 是 `mobile_push`。收到手机 video track 后，`aiortc` 将 frame 转成 BGR ndarray 并写入 `mobile_push_frame_store`；设备帧循环读取该 store，继续执行检测、构图、云台控制和 overlay 渲染；`DevicePreviewVideoTrack` 再把 `session.get_preview_frame()` 作为 WebRTC video track 返回手机。

## fallback 视频链路

以下旧接口继续保留：

- `WS /api/device/stream/mobile-ws`：手机发送 Android NV21 二进制帧。
- `WS /api/device/preview-ws`：设备返回 JPEG 预览帧。
- `POST /api/device/stream/frame`：调试用单帧 JPEG 上传。
- `GET /api/device/preview.jpg`：调试用单张 JPEG 预览。

如果 WebRTC 启动失败，Flutter 设备联动页会自动尝试 WebSocket/JPEG fallback。

## 硬件说明

- 当前推荐真实硬件方案是 TTL 总线舵机。
- 舵机必须使用独立外接电源，并与树莓派控制侧共地。
- PCA9685 方案已废弃。
- Windows 本地联调默认可使用 `mock` 驱动。

## 依赖说明

`requirements.txt` 默认包含 WebRTC 和 WebSocket 依赖：

- `aiortc`：WebRTC PeerConnection 和 video track。
- `websockets`：旧 WebSocket fallback。
- `opencv-python-headless`：视频帧处理。
- `mediapipe`：人体/姿态检测。

默认不安装 `ultralytics` 和 `torch`，避免树莓派拉取 CUDA 版 torch 和 `nvidia-*` 包。确实要启用 YOLO 时，先确认 CPU 版 torch 可导入，再手动安装 `ultralytics --no-deps` 并设置：

```bash
export DEVICE_ENABLE_YOLO=1
```

## 主要 API

- `GET /api/device/health`
- `POST /api/device/session/open`
- `POST /api/device/session/close`
- `GET /api/device/status`
- `PATCH /api/device/config`
- `POST /api/device/webrtc/offer`
- `WS /api/device/stream/mobile-ws`
- `WS /api/device/preview-ws`
- `GET /api/device/preview.jpg`
- `POST /api/device/stream/frame`
- `POST /api/device/control/manual-move`
- `POST /api/device/control/mode`
- `POST /api/device/control/home`
- `POST /api/device/control/follow-mode`
- `GET /api/device/templates`
- `POST /api/device/templates/select`
- `POST /api/device/templates/upload`
- `POST /api/device/capture/trigger`
- `GET /api/device/capture/list`
- `GET /api/device/ai/status`
- `POST /api/device/ai/angle-search/start`
- `POST /api/device/ai/background-lock/start`
- `POST /api/device/ai/background-lock/unlock`

完整说明见 `docs/接口契约.md` 和 `docs/技术架构与运行机制详解.md`。
