# database

`database` 保存 PostgreSQL schema 说明。实际初始化推荐通过 `backend/init_db.py` 执行，因为后端启动逻辑还包含兼容旧库的补丁。

## 文件

| 文件 | 说明 |
| --- | --- |
| `schema.sql` | 核心表结构、索引、约束和更新时间触发器 |

## 核心表

- `users`
- `plans`
- `user_subscriptions`
- `devices`
- `templates`
- `capture_sessions`
- `captures`
- `ai_tasks`
- `ai_provider_configs`

## 初始化

推荐方式：

```powershell
cd backend
$env:DATABASE_URL="postgresql+psycopg://postgres:postgres@127.0.0.1:5432/camera_assistant"
python init_db.py
```

手动执行 SQL：

```powershell
psql -d camera_assistant -f database/schema.sql
```

## 数据边界

数据库保存业务后端数据，包括用户、套餐、订阅、模板、拍摄会话、手机端历史抓拍、AI 任务和 Provider 配置。

`device_runtime` 的实时视频状态、WebSocket/WebRTC 会话和设备本地抓拍不直接写入该库。设备抓拍默认保存在设备运行时的 `captures` 目录。

## 升级注意

`backend/app/core/db.py` 中包含少量兼容补丁，用于给旧数据库补新增字段和重建约束。已有库升级时优先运行：

```powershell
cd backend
python init_db.py
```

注意：ORM 和兼容补丁当前允许 `capture_type='device_link'`。如果手动维护 `database/schema.sql`，需要确保约束与 ORM 保持一致。
