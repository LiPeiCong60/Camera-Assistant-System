# device_runtime

Camera Assistant 设备运行时，面向树莓派或本机联调。它提供本地 FastAPI 控制接口，负责视频流读取、人体检测、模板构图、云台控制、预览和本地抓拍。

## 当前真实入口

`main.py` 仍是占位提示，实际启动入口是：

```powershell
uvicorn device_runtime.api.app:app --reload --host 0.0.0.0 --port 8001
```

## 职责

- 打开本地设备会话。
- 使用 OpenCV 读取摄像头或视频流。
- 接收手机端推送的 WebSocket 视频帧作为 `mobile_push` 视频源。
- 使用 MediaPipe、可选 YOLO 或 OpenCV HOG 做人体/姿态检测。
- 在 `MANUAL`、`AUTO_TRACK`、`SMART_COMPOSE` 模式下管理跟踪和构图。
- 通过 TTL 总线舵机或 mock 驱动控制云台。
- 接收手机端下发的模板数据和 AI 背景锁结果。

## 目录

| 目录 | 说明 |
| --- | --- |
| `api` | 本地 HTTP API、单会话管理。 |
| `vision` | 视频源、检测器、异步检测封装。 |
| `control` | 跟踪控制和云台控制。 |
| `services` | 帧处理、控制、抓拍、模板、运行时状态。 |
| `templates` | 模板数据结构、构图评分、手势状态。 |
| `repositories` | 本地模板库读写。 |

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

## 硬件说明

- 当前唯一推荐真实硬件方案是 TTL 总线舵机。
- 舵机必须使用独立外接电源，并与树莓派控制侧共地。
- PCA9685 方案已废弃。
- Windows 本地联调默认可使用 `mock` 驱动。

## 依赖说明

`requirements.txt` 默认不安装 `ultralytics` 和 `torch`，避免树莓派拉取 CUDA 版 torch 和 `nvidia-*` 包。运行时会按环境退化：

1. 非 ARM 环境可尝试 MediaPipe + YOLO。
2. ARM / 树莓派默认跳过 YOLO。
3. YOLO 不可用时使用 MediaPipe。
4. MediaPipe 不可用时退到 OpenCV HOG。

`websockets` 是手机画面推送必需依赖，用于让 `uvicorn` 正常处理 `/api/device/stream/mobile-ws` 握手。

确实要启用 YOLO 时，先确认 CPU 版 torch 可导入，再手动安装 `ultralytics --no-deps` 并设置：

```bash
export DEVICE_ENABLE_YOLO=1
```

## 手机画面推送

手机端设备联动页开启“手机画面推送”后，会通过 WebSocket 推送 Android NV21 视频帧到：

```text
WS /api/device/stream/mobile-ws
```

App 预览窗口会同时连接实时预览下行：

```text
WS /api/device/preview-ws
```

设备会话需要使用：

```json
{"stream_url": "mobile_push"}
```

该能力会复用现有检测、预览和云台控制链路，适合树莓派联调和演示。`POST /api/device/stream/frame` 和 `GET /api/device/preview.jpg` 仍保留为回退调试接口，但移动端主路径已改为 WebSocket 连续帧。
Android 端会在推流配置中上报 `rotation_degrees`，设备端会统一校正画面方向。

如果日志出现 `Unsupported upgrade request` 或 `No supported WebSocket library detected`，说明树莓派虚拟环境没有装到 `websockets`。重新执行 `python -m pip install -r device_runtime/requirements.txt` 后重启服务。

## 主要 API

- `POST /api/device/session/open`
- `POST /api/device/session/close`
- `GET /api/device/status`
- `GET /api/device/preview.jpg`
- `WS /api/device/preview-ws`
- `WS /api/device/stream/mobile-ws`
- `POST /api/device/stream/frame`
- `POST /api/device/control/manual-move`
- `POST /api/device/control/mode`
- `POST /api/device/control/home`
- `POST /api/device/templates/select`
- `POST /api/device/ai/apply-lock`

完整说明见 `docs/接口契约.md`。
