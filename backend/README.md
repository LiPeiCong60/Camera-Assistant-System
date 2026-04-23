# backend

Camera Assistant 业务后端，基于 FastAPI + SQLAlchemy + PostgreSQL。

## 职责

- 手机端账号登录、注册和当前用户信息。
- 管理端账号登录和后台管理接口。
- 套餐、订阅、设备、模板、拍摄会话、抓拍记录管理。
- 图片文件上传并通过 `/uploads` 静态路径访问。
- AI Provider 配置选择、真实图片分析调用和 AI 任务落库。

## 目录

| 目录 | 说明 |
| --- | --- |
| `app/api` | FastAPI 路由和依赖。 |
| `app/core` | 配置、数据库、鉴权、异常处理。 |
| `app/models` | SQLAlchemy ORM 模型。 |
| `app/repositories` | 数据访问层。 |
| `app/schemas` | Pydantic 请求/响应结构。 |
| `app/services` | 业务服务层。 |

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

## 关键接口

- 手机端：`/api/mobile/*`
- 管理端：`/api/admin/*`
- 健康检查：`/api/health`
- 静态上传：`/uploads/*`

更多接口见 `docs/接口契约.md`。

## AI 说明

AI 调用由 `app/services/ai_provider_service.py` 负责，当前支持 `openai_compatible` 格式。Provider 配置由管理后台维护，移动端不会直接持有 API key。
