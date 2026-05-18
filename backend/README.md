# backend

`backend` 是业务后端，负责账号、套餐、订阅、设备、模板、媒体记录、AI 任务和管理后台接口。生产 AI Provider 也统一在后端配置和调用，手机端与树莓派端不保存生产 AI Key。

## 职责边界

- 手机端登录、注册、当前用户、套餐和当前订阅。
- 手机端模板创建、删除、列表、缓存同步。
- 手机端拍摄会话、照片/视频媒体记录、历史列表。
- 手机端照片分析、背景分析、连拍选优、多角度扫描分析。
- 管理后台登录、用户、套餐、推荐模板、设备、媒体记录、AI 任务和 Provider 配置。
- 本地 `/uploads` 静态文件服务。
- 数据库结构初始化和旧库兼容补丁。

不负责实时视频代理；设备联动实时帧在手机和 `device_runtime` 之间直连。

## 技术组成

| 技术 | 使用位置 | 作用 |
| --- | --- | --- |
| FastAPI | `app/main.py`, `app/api/routes` | HTTP API、依赖注入、请求响应模型 |
| SQLAlchemy 2 | `app/models`, `app/repositories` | ORM、数据库访问、事务 |
| PostgreSQL / psycopg | `DATABASE_URL` | 业务数据持久化 |
| Pydantic | `app/schemas` | 请求/响应校验和字段归一化 |
| httpx | `app/services/ai_provider_service.py` | 调用 OpenAI-compatible AI Provider |
| python-multipart | 上传接口 | 图片/视频/模板文件上传 |
| MediaPipe / OpenCV / Pillow | 模板辅助服务 | 后端兼容模板识别和图像读取；当前 App 优先走手机本地识别 |

## 目录

| 目录 | 说明 |
| --- | --- |
| `app/api` | FastAPI 路由和认证依赖 |
| `app/core` | 配置、数据库初始化、认证、接口契约归一化 |
| `app/models` | SQLAlchemy ORM 模型 |
| `app/repositories` | 数据访问层 |
| `app/schemas` | Pydantic schema |
| `app/services` | 业务服务、AI Provider、模板识别 |
| `tests` | 单元测试 |

## 核心接口

所有业务接口挂载在 `/api` 下：

- `/api/health`
- `/api/mobile/*`
- `/api/admin/*`

上传文件静态访问：

- `/uploads/*`

完整接口见 [接口契约](../docs/接口契约.md)。

## 数据契约

核心枚举以 `backend/app/core/contract.py` 和数据库约束为准。

### `capture_sessions.mode`

- `mobile_only`
- `gimbal_manual`
- `gimbal_follow`
- `gimbal_template`
- `ai_auto_angle`
- `ai_background`

旧值兼容：

- `device_link` -> `gimbal_manual`
- `MANUAL` -> `gimbal_manual`
- `AUTO_TRACK` -> `gimbal_follow`
- `SMART_COMPOSE` -> `gimbal_template`

### `captures.capture_type`

- `single`
- `burst`
- `best`
- `background`
- `template`
- `recording`

旧值 `photo`、`device_link` 会兼容映射为 `single`，语义写入 `metadata.source` / `metadata.media_type`。

### `ai_tasks.task_type`

- `analyze_photo`
- `analyze_background`
- `batch_pick`
- `auto_angle`
- `template_match`
- `video_analysis`

旧值 `background_lock` 会兼容映射为 `analyze_background`。

### `target_box_norm`

统一使用对象格式：

```json
{
  "x": 0.31,
  "y": 0.14,
  "w": 0.36,
  "h": 0.70,
  "label": "recommended_person_position"
}
```

后端仍兼容旧数组格式 `[x, y, w, h]`，但新代码应写对象格式。

## AI Provider

AI 调用由 `app/services/ai_provider_service.py` 完成。当前主力格式是 `openai_compatible`：

1. 管理后台维护 `ai_provider_configs`。
2. 套餐 `feature_flags` 可指定默认 Provider 或可用 Provider 列表。
3. 手机调用 `/api/mobile/ai/*`。
4. 后端读取媒体文件或临时候选图。
5. 后端把图片和结构化提示词发给 Provider。
6. 后端解析 JSON，写入 `ai_tasks`。

Provider 不可用时不会让手机崩溃，而是创建失败状态的 AI 任务并返回明确错误原因。

## 多角度扫描

`POST /api/mobile/ai/analyze-scan` 用于设备联动 AI 自动找角度和背景锁定：

- 手机端上传 1 到 12 张临时候选图。
- `candidates_json` 记录每张图对应的 `candidate_index`、`pan_offset`、`tilt_offset`。
- 后端只做统一分析和任务记录，不保存生产 AI Key 到手机或树莓派。
- 返回值中可包含 `best_candidate_index`、推荐角度、分数、原因、`target_box_norm`。

## 启动

建议从仓库根目录启动，避免 `ModuleNotFoundError: No module named 'backend'`：

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

## 检查

```powershell
python -m compileall -q backend/app backend/tests backend/main.py backend/init_db.py
python -m unittest backend.tests.test_capture_type
```
