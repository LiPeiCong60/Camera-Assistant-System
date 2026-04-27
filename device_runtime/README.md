# device_runtime

`device_runtime` 是树莓派或本机联调用的设备运行时。它提供本地 FastAPI 控制接口，负责手机推流接收、OpenCV 帧处理、人体/手部/人脸检测、overlay 渲染、云台控制、模板构图、手势抓拍、设备端 AI 和本地抓拍文件管理。

## 启动入口

```powershell
cd device_runtime
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt

$env:DEVICE_SERVO_DRIVER="mock"
uvicorn device_runtime.api.app:app --reload --host 0.0.0.0 --port 8001
```

`main.py` 不是当前控制 API 的启动入口。真实 API 入口是 `device_runtime.api.app:app`。

## 当前视频链路

手机端默认使用 Android WebSocket 推流：

```text
mobile_client camera ImageStream
-> WS /api/device/stream/mobile-ws
-> mobile_push_frame_store
-> OpenCV BGR frame
-> detector / template compose / gimbal / overlay / capture
-> WS /api/device/preview-ws
-> mobile_client preview
```

运行时也保留 WebRTC signaling：

- `POST /api/device/webrtc/offer`
- 依赖 `aiortc`
- 用于后续切换或实验，不是当前手机端默认启动路径

调试 fallback：

- `POST /api/device/stream/frame`
- `GET /api/device/preview.jpg`

## 树莓派性能档

推荐现场使用：

```bash
cd device_runtime
python3 -m venv .venv
. .venv/bin/activate
pip install -r requirements.txt

export DEVICE_RPI_PROFILE=performance
export DEVICE_SERVO_DRIVER=ttl_bus
export DEVICE_TTL_SERIAL_PORT=/dev/ttyUSB0
export DEVICE_PAN_SERVO_ID=0
export DEVICE_TILT_SERVO_ID=1

uvicorn device_runtime.api.app:app --host 0.0.0.0 --port 8001
```

### profile 说明

| profile | 检测 | 预览 | 适用场景 |
| --- | --- | --- | --- |
| `performance` | 低检测频率、小输入尺寸，默认关闭完整 landmarks | 较低码率 | 树莓派长时间稳定运行 |
| `balanced` | 中等检测频率，默认关闭完整 landmarks | 中等预览 | 现场调试 |
| `quality` | 更高检测质量，打开更多 landmarks | 更清晰预览 | 短时间演示 |

如果开启人体骨骼或手部骨骼后变卡，优先降低：

- `DEVICE_DETECTOR_FPS`
- `DEVICE_MAX_INFERENCE_SIDE`
- `DEVICE_PREVIEW_SCALE`
- `DEVICE_PREVIEW_FPS`

## 检测和 overlay 开关

检测开关控制是否计算完整 landmarks：

- `DEVICE_ENABLE_POSE_LANDMARKS`
- `DEVICE_ENABLE_FACE_LANDMARKS`
- `DEVICE_ENABLE_HAND_LANDMARKS`
- `DEVICE_TRACKING_ANCHOR_MODE`

显示开关控制是否绘制到预览：

- `DEVICE_ENABLE_OVERLAY`
- `DEVICE_SHOW_BODY_SKELETON`
- `DEVICE_SHOW_FACE_MESH`
- `DEVICE_SHOW_HANDS`
- `DEVICE_SHOW_TRACKING_ANCHOR`

移动端通过 `PATCH /api/device/config` 切换这些开关。当前代码在切换 pose/hand/face 检测后会重建 detector 和 frame processor，避免运行中的帧循环继续使用旧 detector。

## 手势抓拍

手势抓拍依赖手部 landmarks。需要确保：

- `enable_hand_landmarks=true`
- `gesture.capture_enabled=true`
- 预览中能检测到手部

触发手势后不会立刻拍照，而是进入 3 秒倒计时：

- 设备端 overlay 会显示倒计时。
- `/api/device/status` 的 `gesture_status.capture_countdown` 会返回倒计时状态。
- 手机端设备联动 HUD 会显示倒计时提醒。
- 倒计时结束后调用设备端 `trigger_capture`。
- 抓拍文件保存在 `device_runtime/captures`，不会自动同步到后端历史。

如果启用 `gesture.auto_analyze_enabled`，抓拍后会触发设备端本地 AI 流程；它不等同于后端 `/api/mobile/ai/analyze-photo`。

## 关键接口

| 方法 | 路径 | 说明 |
| --- | --- | --- |
| `GET` | `/api/device/health` | 健康检查 |
| `GET` | `/api/device/status` | 会话、云台、检测、手势、AI、overlay 状态 |
| `PATCH` | `/api/device/config` | 更新 overlay、检测、手势配置 |
| `POST` | `/api/device/session/open` | 打开设备会话 |
| `POST` | `/api/device/session/close` | 关闭设备会话 |
| `POST` | `/api/device/stream/start` | 切换视频源 |
| `WS` | `/api/device/stream/mobile-ws` | 手机 NV21 帧上行 |
| `WS` | `/api/device/preview-ws` | JPEG 预览下行 |
| `POST` | `/api/device/capture/trigger` | 手动触发设备抓拍 |
| `GET` | `/api/device/capture/list` | 查看设备本地抓拍文件 |
| `GET` | `/api/device/capture/file` | 下载设备本地抓拍文件 |
| `POST` | `/api/device/control/manual-move` | 手动云台移动 |
| `POST` | `/api/device/control/mode` | 设置运行模式 |
| `POST` | `/api/device/control/home` | 云台回中 |
| `POST` | `/api/device/control/follow-mode` | 设置跟随模式 |

完整接口见 [接口契约](../docs/接口契约.md)。

## 硬件说明

- 推荐真实硬件方案是 TTL 总线舵机。
- 舵机必须使用独立外接电源，并与树莓派控制侧共地。
- Windows 本地联调默认使用 `mock` 驱动。
- PCA9685 方案已不作为当前主推路径。

## 重启规则

需要重启 `uvicorn` 的情况：

- 修改 `device_runtime` 代码。
- 修改依赖或重新安装 `requirements.txt`。
- 修改树莓派启动环境变量。
- 修改云台串口、舵机 ID、检测默认配置。

不一定需要重启的情况：

- 手机端切换 overlay、手势、检测开关。
- 手机端打开/关闭会话。
- 手机端手动触发抓拍。
