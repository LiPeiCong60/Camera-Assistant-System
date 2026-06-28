# 云影随行 Camera Assistant

云影随行是一个面向手机拍摄、树莓派云台控制和多模态 AI 构图分析的智能拍摄辅助系统，包含 Flutter 手机端、FastAPI 业务后端、设备运行时和 Vue 管理后台。

## 项目简介

云影随行面向自拍、合影、固定机位短视频、校园活动记录和旅行打卡等场景，目标是让用户在没有摄影师协助的情况下，也能完成更稳定的取景、跟随和照片筛选。

项目的核心思路是把拍摄链路拆成四个职责清晰的部分：

```text
手机负责画面，设备负责转动，服务器负责智能，后台负责管理。
```

手机端使用本地摄像头作为主预览和最终照片/视频来源；设备端接收手机抽帧，做人体检测、跟踪目标计算和双轴云台控制；后端保存用户、套餐、模板、拍摄记录和 AI 任务，并统一调用 OpenAI-compatible 视觉模型；管理后台负责推荐模板、媒体记录、AI 任务和 AI Provider 配置。

一个典型流程是：用户在手机端打开拍摄或设备联动页面，手机显示本地 `CameraPreview`，同时把低延迟帧推送给 `device_runtime`；设备端根据肩部、面部或模板锚点控制云台；用户拍照后，照片优先保存到手机相册，再按设置上传后端；后端调用视觉大模型返回构图建议、最佳候选或推荐站位框，手机端再把结果绘制到画面上。

## 项目亮点

- **多端协同架构**：Flutter 手机端、FastAPI 后端、Python 设备运行时、Vue 管理后台和 PostgreSQL 数据库按职责拆分，避免把实时控制、业务数据和 AI Key 混在同一端。
- **多模态 AI 接入**：后端通过 `AiProviderService` 调用 OpenAI-compatible 视觉模型，支持图片分析、背景分析、连拍选优和多角度扫描分析，Prompt 要求模型返回可解析 JSON。
- **结构化输出与容错**：后端会抽取和归一化模型返回的 `score`、`target_box_norm`、`best_candidate_index`、云台建议角度等字段；Provider 缺失或调用失败时仍写入失败状态的 `ai_tasks`，方便前端和后台排查。
- **手机主画面 + 设备实时控制**：最终照片和视频由手机相机完成，设备端只负责接收手机帧、检测目标和驱动云台，保证用户看到的画面与最终保存媒体一致。
- **人体姿态与模板构图**：手机端使用 Google ML Kit，设备端使用 MediaPipe/OpenCV，模板数据统一为 0 到 1 的归一化坐标，支持人物框、骨架线、头部框、肩部/面部锚点和 AI 推荐框绘制。
- **工程化分层清晰**：后端按 `routes / services / repositories / models / schemas` 分层，设备端拆分 `session_manager`、`control_service`、`tracking_controller`、`detector`，并保留 Python、Flutter 和设备控制相关测试。

## 功能模块

| 模块 | 功能说明 |
| --- | --- |
| 手机 App `mobile_client` | 登录注册、服务地址配置、拍照录像、模板构图、AI 连拍选优、背景分析、历史记录、设备联动和相册保存。 |
| 设备运行时 `device_runtime` | 提供本地设备 API，接收手机帧，执行 MediaPipe/OpenCV 检测，控制 TTL 总线舵机云台，支持手动、自动跟随和模板构图模式。 |
| 业务后端 `backend` | 管理用户、套餐、订阅、模板、拍摄会话、媒体记录、AI 任务和 AI Provider，提供 `/api/mobile/*` 与 `/api/admin/*` 接口。 |
| 管理后台 `admin_web` | 管理员登录、工作台统计、用户管理、套餐管理、推荐模板、拍摄记录、AI 任务和多 Provider 配置。 |
| 数据库 `database` | PostgreSQL 表结构、约束、索引和触发器，覆盖用户、套餐、设备、模板、拍摄记录、AI 任务和 Provider 配置。 |
| AI 分析工作流 | 支持单张照片分析、背景分析、连拍选优、多候选角度分析，返回结构化结果供手机端展示和云台执行。 |
| 模板与 Overlay | 通过人物框、姿态点、肩部/面部锚点和推荐框完成模板投影、实时对齐和画面提示。 |

## 技术栈

| 类别 | 技术 |
| --- | --- |
| 前端 App | Flutter、Dart、camera、Google ML Kit Pose Detection、flutter_webrtc、shared_preferences、path_provider、image_picker |
| 管理后台 | Vue 3、Vite、Element Plus、Pinia、Vue Router、Axios |
| 后端服务 | FastAPI、Uvicorn、SQLAlchemy 2、Pydantic、python-multipart、httpx |
| AI / 多模态 | OpenAI-compatible Vision API、结构化 Prompt、JSON 结果解析、MediaPipe、OpenCV、Pillow |
| 数据库 | PostgreSQL、psycopg、JSONB、外键约束、检查约束、更新时间触发器 |
| 设备控制 | Python、FastAPI、WebSocket、OpenCV、MediaPipe、pyserial、TTL 总线舵机、aiortc 可选 WebRTC |
| 工程工具 | npm、Flutter SDK、PowerShell 脚本、Python 单元测试、Flutter 测试、Vite build |
| 运行环境 | 本机开发、Android/iOS 真机或模拟器、树莓派或本机 mock 设备运行时 |

## 项目结构

```text
Camera-Assistant-System/
├── README.md                         # 项目总览文档
├── backend/                          # FastAPI 业务后端
│   ├── app/
│   │   ├── api/routes/               # mobile、admin、health 路由
│   │   ├── core/                     # 配置、认证、数据库、字段契约
│   │   ├── models/                   # SQLAlchemy ORM 模型
│   │   ├── repositories/             # 数据访问层
│   │   ├── schemas/                  # Pydantic 请求/响应模型
│   │   └── services/                 # 业务服务、AI Provider、模板识别
│   ├── tests/                        # 后端测试
│   ├── requirements.txt              # 后端依赖
│   └── .env.example                  # 后端环境变量示例
├── admin_web/                        # Vue 管理后台
│   ├── src/api/                      # Axios 接口封装
│   ├── src/router/                   # 后台路由和登录守卫
│   ├── src/stores/                   # Pinia 登录态和配置
│   ├── src/views/                    # 工作台、用户、套餐、模板、AI 页面
│   └── package.json                  # 前端依赖和脚本
├── mobile_client/                    # Flutter 手机 App
│   ├── lib/app/                      # App 启动和登录态引导
│   ├── lib/features/                 # 登录、首页、拍摄、设备联动、历史、设置
│   ├── lib/models/                   # 响应模型
│   ├── lib/services/                 # 后端、设备端、相册、缓存、WebRTC 服务
│   ├── android/                      # Android 工程与平台通道
│   ├── ios/                          # iOS 工程
│   ├── test/                         # Flutter 测试
│   └── pubspec.yaml                  # Flutter 依赖
├── device_runtime/                   # 树莓派/本机设备运行时
│   ├── api/routes/                   # 设备状态、会话、控制、推流、模板、AI API
│   ├── control/                      # 云台控制和跟踪控制器
│   ├── services/                     # 帧处理、控制服务、模板服务、AI 编排
│   ├── templates/                    # 模板构图计算
│   ├── vision/                       # 视频源和 MediaPipe/OpenCV 检测
│   ├── tests/                        # 设备端测试
│   └── requirements.txt              # 设备端依赖
├── database/
│   └── schema.sql                    # PostgreSQL 建表、索引和触发器
├── docs/
│   └── 项目说明.md                   # 项目补充说明
└── scripts/                          # 检查、文档和交付材料生成脚本
```

## 快速开始

### 1. 克隆项目

```bash
git clone git@github.com:LiPeiCong60/Camera-Assistant-System.git
cd Camera-Assistant-System
```

如果没有配置 SSH，也可以使用 HTTPS：

```bash
git clone https://github.com/LiPeiCong60/Camera-Assistant-System.git
```

### 2. 启动 PostgreSQL

创建数据库，例如：

```sql
CREATE DATABASE camera_assistant;
```

项目提供了 `database/schema.sql`，但推荐优先用 `backend/init_db.py` 初始化，因为它会同时执行 ORM 建表和旧库兼容补丁。

### 3. 启动后端

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r backend/requirements.txt

export DATABASE_URL="postgresql+psycopg://postgres:your_password@127.0.0.1:5432/camera_assistant"
export BACKEND_AUTH_SECRET="replace-with-a-long-random-secret"

python backend/init_db.py
python -m uvicorn backend.app.main:app --reload --host 0.0.0.0 --port 8000
```

Windows PowerShell 可把 `export` 换成 `$env:NAME="value"`。

后端地址：

- 健康检查：`http://127.0.0.1:8000/api/health`
- API 文档：`http://127.0.0.1:8000/docs`
- 上传文件静态访问：`http://127.0.0.1:8000/uploads/...`

### 4. 启动设备运行时

本机无硬件调试可以使用 mock 舵机：

```bash
source .venv/bin/activate
pip install -r device_runtime/requirements.txt

export DEVICE_SERVO_DRIVER="mock"
python -m uvicorn device_runtime.api.app:app --reload --host 0.0.0.0 --port 8001
```

树莓派现场运行示例：

```bash
export DEVICE_RPI_PROFILE="performance"
export DEVICE_SERVO_DRIVER="ttl_bus"
export DEVICE_TTL_SERIAL_PORT="/dev/ttyUSB0"
export DEVICE_PAN_SERVO_ID="0"
export DEVICE_TILT_SERVO_ID="1"

python -m uvicorn device_runtime.api.app:app --host 0.0.0.0 --port 8001
```

设备端地址：

- 健康检查：`http://127.0.0.1:8001/api/device/health`
- API 文档：`http://127.0.0.1:8001/docs`

### 5. 启动管理后台

```bash
cd admin_web
npm install
export VITE_API_BASE_URL="http://127.0.0.1:8000/api"
npm run dev
```

默认访问：

```text
http://127.0.0.1:5173
```

生产构建：

```bash
npm run build
```

### 6. 启动手机端

```bash
cd mobile_client
flutter pub get
flutter run \
  --dart-define=API_BASE_URL=http://127.0.0.1:8000/api \
  --dart-define=DEVICE_API_BASE_URL=http://127.0.0.1:8001
```

Android 模拟器默认可使用 `10.0.2.2` 访问宿主机。真机联调时，请把两个地址换成电脑或树莓派的局域网 IP：

```bash
flutter run \
  --dart-define=API_BASE_URL=http://192.168.1.20:8000/api \
  --dart-define=DEVICE_API_BASE_URL=http://192.168.1.30:8001
```

构建 APK：

```bash
flutter build apk --release
```

输出路径：

```text
mobile_client/build/app/outputs/flutter-apk/app-release.apk
```

## 环境变量说明

仓库当前提供 `backend/.env.example`。`admin_web`、`device_runtime` 和 `mobile_client` 主要通过 shell 环境变量或 `--dart-define` 配置，建议后续补充各自的 `.env.example` 或启动脚本。

下面是可用于本地开发的示例，不包含任何真实密钥：

```env
# backend
BACKEND_ENV=development
BACKEND_HOST=0.0.0.0
BACKEND_PORT=8000
BACKEND_AUTH_SECRET=replace-with-a-long-random-secret
BACKEND_ACCESS_TOKEN_TTL_SECONDS=86400
BACKEND_CORS_ORIGINS=http://127.0.0.1:5173,http://localhost:5173
BACKEND_UPLOADS_DIR=./uploads
BACKEND_UPLOADS_URL_PATH=/uploads
DATABASE_URL=postgresql+psycopg://postgres:your_password@127.0.0.1:5432/camera_assistant

# admin_web
VITE_API_BASE_URL=http://127.0.0.1:8000/api

# mobile_client, use with flutter run --dart-define
API_BASE_URL=http://127.0.0.1:8000/api
DEVICE_API_BASE_URL=http://127.0.0.1:8001

# device_runtime
DEVICE_SERVO_DRIVER=mock
DEVICE_RPI_PROFILE=balanced
DEVICE_TTL_SERIAL_PORT=/dev/ttyUSB0
DEVICE_TTL_BAUDRATE=115200
DEVICE_PAN_SERVO_ID=0
DEVICE_TILT_SERVO_ID=1
DEVICE_DETECTOR_FPS=8
DEVICE_MAX_INFERENCE_SIDE=640
DEVICE_TRACKING_ANCHOR_MODE=auto
DEVICE_TRACKING_SENSITIVITY=1.0
DEVICE_PREVIEW_FPS=24

# optional, only for device-side AI debug compatibility
SILICONFLOW_API_KEY=replace-with-provider-key
SILICONFLOW_MODEL=replace-with-model-name
SILICONFLOW_ENDPOINT=https://api.example.com/v1/chat/completions
SILICONFLOW_TIMEOUT_S=60
```

生产 AI Provider 不建议写入移动端或设备端环境变量。项目当前的主链路是在管理后台维护 `ai_provider_configs`，包括 `provider_code`、`vendor_name`、`provider_format`、`api_base_url`、`api_key`、`model_name` 和 `extra_config`；接口返回时会使用 `masked_api_key` 做脱敏展示。

## API 接口说明

### 业务后端 `backend`

所有业务接口统一挂载在 `/api` 下。

| 方法 | 路径 | 功能说明 | 请求参数简述 |
| --- | --- | --- | --- |
| GET | `/api/health` | 后端健康检查和数据库连接状态 | 无 |
| POST | `/api/mobile/auth/login` | 手机端登录 | `phone`、`password` |
| POST | `/api/mobile/auth/register` | 手机端注册 | `phone`、`password`、`display_name` |
| GET | `/api/mobile/me` | 获取当前用户 | `Authorization: Bearer <token>` |
| GET | `/api/mobile/plans` | 获取可用套餐 | 无 |
| GET | `/api/mobile/subscription` | 获取当前订阅 | Bearer Token |
| GET | `/api/mobile/templates` | 获取用户可用模板 | Bearer Token |
| POST | `/api/mobile/templates` | 创建模板 | `name`、`template_type`、`source_image_url`、`template_data` |
| DELETE | `/api/mobile/templates/{template_id}` | 删除模板 | 路径参数 `template_id` |
| POST | `/api/mobile/sessions` | 创建拍摄会话 | `device_id`、`template_id`、`mode`、`metadata` |
| POST | `/api/mobile/captures/file` | 上传照片或视频文件 | multipart `file` |
| POST | `/api/mobile/captures/upload` | 创建媒体记录 | `session_id`、`capture_type`、`file_url`、`metadata` |
| POST | `/api/mobile/ai/analyze-photo` | 单张照片构图分析 | `session_id`、`capture_id` |
| POST | `/api/mobile/ai/analyze-background` | 背景/站位分析 | `session_id`、`capture_id`、可选 `device_id` |
| POST | `/api/mobile/ai/batch-pick` | 连拍照片选优 | `session_id`、`capture_ids`，2 到 9 张 |
| POST | `/api/mobile/ai/analyze-scan` | 多角度候选图分析 | multipart `files`、`task_type`、`candidates_json` |
| GET | `/api/mobile/ai/tasks/{task_id}` | 查询 AI 任务详情 | 路径参数 `task_id` |
| GET | `/api/mobile/history/sessions` | 查询历史会话 | Bearer Token |
| GET | `/api/mobile/history/captures` | 查询历史媒体记录 | Bearer Token |
| POST | `/api/admin/login` | 管理员登录 | `phone`、`password` |
| GET/POST/PUT/DELETE | `/api/admin/users` | 用户管理 | 用户编号、手机号、角色、状态、套餐等 |
| GET/POST/PUT/DELETE | `/api/admin/plans` | 套餐管理 | 价格、周期、拍摄额度、AI 额度、`feature_flags` |
| GET/POST/PUT/DELETE | `/api/admin/templates/recommended` | 推荐模板管理 | 模板名称、图片地址、模板数据、排序 |
| POST | `/api/admin/templates/recommended/upload-image` | 上传推荐模板图片并生成姿态数据 | multipart `file`、可选 `name` |
| GET/POST/PUT/DELETE | `/api/admin/devices` | 设备登记接口 | 设备编号、用户、IP、控制地址等，当前后台侧栏未启用入口 |
| GET/DELETE | `/api/admin/captures` | 媒体记录查看和清理 | 可删除单条或全部 |
| GET/DELETE | `/api/admin/ai/tasks` | AI 任务查看和清理 | 可删除单条或全部 |
| GET | `/api/admin/statistics/overview` | 管理后台概览统计 | 无 |
| GET/POST/PUT/DELETE | `/api/admin/ai/provider-configs` | 多 AI Provider 配置 | Provider code、base URL、模型名、API Key、extra config |

### 设备运行时 `device_runtime`

设备端接口默认运行在 `8001`，不挂业务后端的 `/api` 前缀，而是直接使用 `/api/device/*`。

| 方法 | 路径 | 功能说明 | 请求参数简述 |
| --- | --- | --- | --- |
| GET | `/api/device/health` | 设备运行时健康检查 | 无 |
| POST | `/api/device/session/open` | 打开设备会话 | `session_code`、`stream_url`、`start_mode` |
| POST | `/api/device/session/close` | 关闭设备会话 | 可选 `session_code` |
| GET | `/api/device/status` | 查询设备、云台、检测、AI 状态 | 无 |
| PATCH | `/api/device/config` | 更新 overlay、手势、检测开关 | `overlay`、`gesture`、`detection` |
| POST | `/api/device/control/manual-move` | 手动移动云台 | `action` 或 `pan_delta`、`tilt_delta` |
| POST | `/api/device/control/mode` | 切换控制模式 | `MANUAL`、`AUTO_TRACK`、`SMART_COMPOSE` |
| POST | `/api/device/control/home` | 云台回中 | 无 |
| POST | `/api/device/control/follow-mode` | 切换跟随目标 | `shoulders`、`face` 等 |
| POST | `/api/device/control/sensitivity` | 调整灵敏度 | `sensitivity` |
| POST | `/api/device/control/track-target` | 手机端提供归一化目标点，设备端执行跟踪 | `target_x`、`target_y`、`desired_x`、`desired_y` |
| WS | `/api/device/stream/mobile-ws` | 手机 NV21 连续帧推送 | 首帧配置 JSON，后续二进制帧 |
| POST | `/api/device/stream/frame` | HTTP JPEG 帧上传 fallback | multipart `file` |
| GET | `/api/device/preview.jpg` | 调试预览 JPEG | 无 |
| WS | `/api/device/preview-ws` | 调试预览 WebSocket | 无 |
| GET/POST/DELETE | `/api/device/templates` | 设备侧模板列表、上传、导入、删除、选择 | 图片文件或模板 ID |
| POST | `/api/device/capture/trigger` | 设备侧兼容抓拍触发 | `reason`、`auto_analyze` |
| GET | `/api/device/capture/list` | 列出设备侧抓拍文件 | `limit` |
| POST | `/api/device/ai/angle-search/start` | 设备侧兼容角度扫描 | 扫描范围、步进、候选数量 |
| POST | `/api/device/ai/background-lock/start` | 设备侧兼容背景锁定扫描 | 扫描范围、步进、候选数量 |
| POST | `/api/device/ai/apply-angle` | 应用后端/手机返回的角度建议 | `recommended_pan_delta`、`recommended_tilt_delta` |
| POST | `/api/device/ai/apply-lock` | 应用背景锁定建议 | 云台角度和 `target_box_norm` |

## 功能展示

仓库目前只提交了 App 图标和启动图，尚未提交正式功能截图。下面预留展示位，后续把图片补充到 `docs/images/` 后即可在 GitHub 自动显示：

![移动端首页](./docs/images/mobile-home.png)
![拍摄页与模板构图](./docs/images/mobile-camera-template.png)
![设备联动页](./docs/images/device-link.png)
![管理后台工作台](./docs/images/admin-overview.png)
![AI Provider 配置](./docs/images/admin-ai-provider.png)

当前可引用的品牌图：

![云影随行 Logo](./mobile_client/assets/branding/app_logo.png)

## 我的职责 / 个人贡献

在这个项目中，我负责从需求分析到工程落地的完整实现：梳理“手机主预览、设备负责云台、后端统一 AI、后台负责运营”的系统边界；完成 Flutter 手机端拍摄、录像、模板构图、设备联动和 AI 扫描流程；设计 FastAPI 后端的数据模型、接口契约、AI 任务流转和 Provider 配置；实现设备运行时的会话管理、手机帧接收、目标跟踪和云台控制；完成 Vue 管理后台的用户、套餐、模板、媒体、AI 任务和模型配置页面；同时整理数据库结构、环境配置、运行说明和项目文档，保证项目可以用于演示、复现和求职展示。

## 后续优化方向

- **补齐部署工程**：增加 Docker Compose、生产环境配置模板、Nginx 反向代理示例和一键启动脚本。
- **完善安全与权限**：为后台接口补充更细粒度的权限控制、操作审计、API Key 加密存储和敏感日志脱敏。
- **增强 AI 能力**：在现有 OpenAI-compatible 视觉调用基础上，补充更多 Provider 适配器，并探索拍摄知识库 RAG、工具调用和可解释评分规则。
- **提升测试覆盖**：继续增加后端接口测试、设备端控制算法测试、Flutter 集成测试和管理后台组件测试。
- **优化前端体验**：补充正式截图、演示数据、失败状态引导，减少管理后台 chunk 体积，并优化真机联调配置流程。

## 安全和隐私

- 不要提交 `.env`、真实数据库密码、认证密钥、AI Provider API Key。
- 不要提交 `uploads/`、`captures/`、用户照片、演示视频、本地数据库、日志和缓存。
- 不要提交 `.venv/`、`node_modules/`、Flutter/Android/iOS 构建产物和本地 IDE 配置。
- 生产 AI Key 应通过管理后台写入后端 Provider 配置，不应写入移动端、设备端或 README 示例。

提交前建议执行：

```bash
git status --ignored --short
git diff --check
```
