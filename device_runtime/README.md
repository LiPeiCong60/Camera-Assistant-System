# device_runtime

`device_runtime` 是树莓派或本机调试运行时。它的核心职责是“让设备动起来”：接收手机推送帧、做轻量检测、计算跟踪目标、控制 TTL 总线舵机云台，并向手机返回设备状态。

生产 AI 能力不应依赖树莓派保存 API Key。当前产品主流程中，自动找角度和背景锁定由手机采集候选帧后交给 `backend` 分析；`device_runtime` 只负责按手机命令转动和返回状态。

## 职责边界

- 接收手机端推送的相机帧。
- OpenCV/MediaPipe 本地检测人体、手部、人脸信息。
- 根据手动控制、自动跟随、模板构图生成云台移动指令。
- 通过 TTL 总线串口控制 pan/tilt 两个舵机。
- 提供设备状态、检测状态、手势状态、云台状态。
- 保留本地抓拍、设备端 AI、WebRTC、预览流等兼容/调试接口。

不作为主预览画面来源，不保存手机最终照片/视频，不保存生产 AI Key。`/api/device/ai/*` 如需独立调试，可用 `SILICONFLOW_*` 环境变量启用兼容 AI，不属于当前生产主链路。

## 技术组成

| 技术 | 使用位置 | 作用 |
| --- | --- | --- |
| FastAPI | `api/app.py`, `api/routes` | 本地 HTTP/WebSocket 控制 API |
| Uvicorn | 启动命令 | ASGI 服务运行 |
| WebSocket | `stream.py`, `status.py` | 手机帧上行、调试预览下行 |
| OpenCV | 帧解码、缩放、绘制 | NV21/JPEG 转 BGR、图像处理 |
| MediaPipe | `vision/detector.py` | 人体姿态、手部、面部关键点 |
| pyserial | `control/gimbal_controller.py` | TTL 总线舵机串口控制 |
| aiortc | `api/routes/webrtc.py` | 保留 WebRTC 实验 signaling |
| Pillow | 上传模板/图片处理 | 图像读取和格式处理 |

## 当前主链路

```text
mobile_client 手机相机
-> /api/device/stream/mobile-ws
-> DeviceSessionContext 接收帧
-> AsyncDetector / FrameProcessor
-> TrackingController / TemplateComposeEngine
-> GimbalController
-> TTLBusSerialDriver
-> 舵机转动
-> /api/device/status 返回状态给手机
```

手机端主画面仍然是手机本地 `CameraPreview`。设备端 `preview-ws` / `preview.jpg` 保留为调试和兼容用途，不是当前主画面。

## 云台控制

真实硬件使用 TTL 总线舵机：

- pan 轴默认 servo id `0`
- tilt 轴默认 servo id `1`
- 默认串口 `/dev/ttyUSB0`
- Windows 本机默认可使用 `mock` 驱动

关键类：

- `TTLBusSerialDriver`：封装串口协议和角度到脉宽转换。
- `GimbalController`：维护角度、回中、手动移动、连续控制、跟踪缓动。
- `TrackingController`：根据目标偏移计算云台修正量，包含死区、刹车区、反向保护和灵敏度。
- `TemplateComposeEngine`：计算实时人物点与模板点的对齐误差。

## 跟随和模板构图

模式：

- `MANUAL` / `gimbal_manual`：手动控制。
- `AUTO_TRACK` / `gimbal_follow`：自动跟随实时人物。
- `SMART_COMPOSE` / `gimbal_template`：模板构图，对齐模板中心点。

跟随目标：

- `shoulders`：肩部中心点。
- `face`：面部中心点。
- `auto` / `upper_body`：根据可用检测结果自动选择。

模板构图时，手机会把后端模板数据一起传给设备端，设备端按归一化模板点计算偏移，云台只执行转动。

## 手势抓拍

手势抓拍依赖手部 landmarks。设备端会在启用手势抓拍时自动提高必要检测配置：

- 打开 `enable_hand_landmarks`。
- 降低/取消跳帧。
- 提高最小检测质量。

触发后会进入倒计时，倒计时期间不重复触发：

```text
检测到手势
-> 3 秒倒计时
-> 倒计时期间忽略新手势
-> 触发一次抓拍事件
-> 冷却后才能再次触发
```

当前产品最终照片应由手机保存到相册。设备端本地抓拍接口仍存在，主要用于兼容、调试和手机拉取后再保存。

## 环境变量

### 硬件

| 变量 | 说明 |
| --- | --- |
| `DEVICE_SERVO_DRIVER` | `mock` 或 `ttl_bus` |
| `DEVICE_TTL_SERIAL_PORT` | TTL 总线串口，例如 `/dev/ttyUSB0` |
| `DEVICE_TTL_BAUDRATE` | 串口波特率 |
| `DEVICE_TTL_MOVE_TIME_MS` | 单次舵机命令移动时间 |
| `DEVICE_TTL_TIMEOUT_S` | 串口超时 |
| `DEVICE_PAN_SERVO_ID` | 水平舵机 ID |
| `DEVICE_TILT_SERVO_ID` | 俯仰舵机 ID |
| `DEVICE_PAN_MIN_ANGLE` / `DEVICE_PAN_MAX_ANGLE` | 水平角度限制 |
| `DEVICE_PAN_HOME_ANGLE` / `DEVICE_PAN_MAX_STEP_DEG` | 水平回中角和单步限制 |
| `DEVICE_TILT_MIN_ANGLE` / `DEVICE_TILT_MAX_ANGLE` | 俯仰角度限制 |
| `DEVICE_TILT_HOME_ANGLE` / `DEVICE_TILT_MAX_STEP_DEG` | 俯仰回中角和单步限制 |

### 性能和检测

| 变量 | 说明 |
| --- | --- |
| `DEVICE_RPI_PROFILE` | `performance`、`balanced`、`quality` |
| `DEVICE_DETECTOR_FPS` | 检测帧率 |
| `DEVICE_MAX_INFERENCE_SIDE` | 检测输入最大边 |
| `DEVICE_ASYNC_SKIP_FRAMES` | 异步检测跳帧 |
| `DEVICE_ENABLE_POSE_LANDMARKS` | 是否计算人体骨架 |
| `DEVICE_ENABLE_FACE_LANDMARKS` | 是否计算人脸点 |
| `DEVICE_ENABLE_HAND_LANDMARKS` | 是否计算手部点 |
| `DEVICE_TRACKING_ANCHOR_MODE` | 默认跟踪锚点模式 |
| `DEVICE_ENABLE_YOLO` | 可选启用 YOLO 检测；默认依赖列表不安装 YOLO/torch，缺少时会回落 MediaPipe/OpenCV |

### 跟踪

| 变量 | 说明 |
| --- | --- |
| `DEVICE_TRACKING_MIN_CONFIDENCE` | 跟踪目标最小置信度 |
| `DEVICE_TRACKING_DEADZONE_PX` | 普通跟随死区 |
| `DEVICE_TRACKING_COMPOSE_DEADZONE_PX` | 模板构图死区 |
| `DEVICE_TRACKING_DEBOUNCE_FRAMES` | 跟踪目标防抖帧数 |
| `DEVICE_TRACKING_GAIN_X` / `DEVICE_TRACKING_GAIN_Y` | 水平/俯仰增益 |
| `DEVICE_TRACKING_MAX_DELTA_DEG` | 单次最大修正角 |
| `DEVICE_TRACKING_MIN_COMMAND_INTERVAL_S` | 最小命令间隔 |
| `DEVICE_TRACKING_COMMAND_SMOOTH_ALPHA` | 命令平滑系数 |
| `DEVICE_TRACKING_MIN_OUTPUT_DEG` | 小于该角度的输出会被抑制 |
| `DEVICE_TRACKING_MAX_ANCHOR_JUMP_PX` | 锚点跳变保护阈值 |
| `DEVICE_TRACKING_SETTLE_AFTER_MOVE_S` | 云台移动后的稳定等待 |
| `DEVICE_TRACKING_INVERT_PAN` / `DEVICE_TRACKING_INVERT_TILT` | 水平/俯仰方向反转 |
| `DEVICE_TRACKING_SENSITIVITY` | 运行时灵敏度 |

### 预览和 overlay

| 变量 | 说明 |
| --- | --- |
| `DEVICE_PREVIEW_FPS` | 调试预览帧率 |
| `DEVICE_PREVIEW_SCALE` | 调试预览缩放 |
| `DEVICE_PREVIEW_JPEG_QUALITY` | 调试预览 JPEG 质量 |
| `DEVICE_ENABLE_OVERLAY` | 设备端调试 overlay |
| `DEVICE_SHOW_BODY_SKELETON` | 显示人体骨架 |
| `DEVICE_SHOW_FACE_MESH` | 显示人脸网格 |
| `DEVICE_SHOW_HANDS` | 显示手部骨架 |
| `DEVICE_SHOW_TRACKING_ANCHOR` | 显示跟踪锚点 |

### 设备侧 AI 兼容

| 变量 | 说明 |
| --- | --- |
| `SILICONFLOW_API_KEY` | 只供设备侧 AI 兼容接口使用 |
| `SILICONFLOW_MODEL` | 设备侧兼容 AI 模型名 |
| `SILICONFLOW_ENDPOINT` | 设备侧兼容 AI endpoint |
| `SILICONFLOW_TIMEOUT_S` | 设备侧兼容 AI 请求超时 |

当前产品的自动找角度和背景锁定主流程由手机上传候选图到 `backend`，再由后端 AI Provider 分析；树莓派现场运行通常不需要配置这些变量。

## 启动

Windows mock：

```powershell
cd <repo-root>
.\.venv\Scripts\Activate.ps1
pip install -r device_runtime\requirements.txt

$env:DEVICE_SERVO_DRIVER="mock"
python -m uvicorn device_runtime.api.app:app --reload --host 0.0.0.0 --port 8001
```

树莓派：

```bash
cd ~/camera_assistant_pi
source .venv/bin/activate
pip install -r device_runtime/requirements.txt

export DEVICE_RPI_PROFILE=performance
export DEVICE_SERVO_DRIVER=ttl_bus
export DEVICE_TTL_SERIAL_PORT=/dev/ttyUSB0
export DEVICE_PAN_SERVO_ID=0
export DEVICE_TILT_SERVO_ID=1

python -m uvicorn device_runtime.api.app:app --host 0.0.0.0 --port 8001
```

## 检查

```powershell
python -m compileall -q device_runtime
python -m unittest device_runtime.tests.test_track_target_contract
```

如果完整 API 测试导入 `aiortc` 失败，说明当前虚拟环境缺 WebRTC 可选依赖；WebSocket 主链路不依赖它。
