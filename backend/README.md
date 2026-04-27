# backend

`backend` 是业务后端，基于 FastAPI + SQLAlchemy + PostgreSQL。它负责账号、套餐、订阅、设备登记、模板、拍摄会话、历史抓拍、AI 任务、上传文件和管理后台接口。

实时设备视频不经过 `backend`。手机端设备联动页会直接访问局域网内的 `device_runtime`。

## 职责边界

- 手机端登录、注册、当前用户信息。
- 手机端套餐、订阅、模板、拍摄会话、抓拍记录、历史列表。
- 手机端图片上传、照片分析、背景分析和连拍选优。
- 管理端登录、用户、套餐、推荐模板、设备、抓拍、AI 任务和 Provider 配置。
- 通过 `/uploads` 暴露本地上传文件。
- 不代理实时视频，不保存设备端本地手势抓拍。

## 目录

| 目录 | 说明 |
| --- | --- |
| `app/api` | FastAPI 路由和依赖注入 |
| `app/core` | 配置、数据库、认证、异常处理 |
| `app/models` | SQLAlchemy ORM 模型 |
| `app/repositories` | 数据访问层 |
| `app/schemas` | Pydantic 请求/响应结构 |
| `app/services` | 业务服务和 AI Provider 调用 |
| `tests` | 后端单元测试 |

## 启动

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

## 关键环境变量

| 变量 | 默认值 | 说明 |
| --- | --- | --- |
| `DATABASE_URL` | 空 | PostgreSQL 连接串，生产/联调必须设置 |
| `BACKEND_AUTH_SECRET` | 开发环境自动生成 | Token 签名密钥，非开发环境必须设置 |
| `BACKEND_ACCESS_TOKEN_TTL_SECONDS` | `86400` | 登录 token 有效期 |
| `BACKEND_UPLOADS_DIR` | 仓库根目录 `uploads` | 上传文件存储目录 |
| `BACKEND_UPLOADS_URL_PATH` | `/uploads` | 静态文件 URL 前缀 |
| `BACKEND_CORS_ORIGINS` | `127.0.0.1:5173,localhost:5173` | 管理后台 CORS 白名单 |

## 关键接口

业务接口统一挂载在 `/api` 下：

- 手机端：`/api/mobile/*`
- 管理端：`/api/admin/*`
- 健康检查：`/api/health`
- 静态上传：`/uploads/*`

完整列表见 [接口契约](../docs/接口契约.md)。

## AI Provider

AI 调用由 `app/services/ai_provider_service.py` 负责，当前支持 `openai_compatible` 格式。Provider 配置由管理后台维护，移动端不会直接持有 API key。

套餐的 `feature_flags` 可指定：

- `default_ai_provider_code`
- `available_ai_provider_codes`

后端会优先使用套餐默认 Provider，其次使用可用 Provider 列表，最后退回系统默认配置或 mock 结果。

## 历史和设备抓拍

后端 `captures.capture_type` 当前允许：

- `single`
- `photo`
- `burst`
- `best`
- `background`
- `device_link`

但当前产品流程中，设备联动手势抓拍默认只保存在 `device_runtime/captures`，不会自动写入后端历史。后端历史主要服务于手机端独立拍摄、背景分析、连拍选优和管理后台回看。

## 测试

```powershell
..\.venv\Scripts\python.exe -m unittest backend.tests.test_capture_type
```
