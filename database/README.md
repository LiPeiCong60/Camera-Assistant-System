# database

???? PostgreSQL 数据库说明。

## 文件

| 文件 | 说明 |
| --- | --- |
| `schema.sql` | 当前核心表结构、索引和更新时间触发器。 |

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

## 初始化方式

推荐通过 backend 初始化：

```powershell
cd backend
$env:DATABASE_URL="postgresql+psycopg://postgres:postgres@127.0.0.1:5432/camera_assistant"
python init_db.py
```

也可以手动执行：

```powershell
psql -d camera_assistant -f database/schema.sql
```

## 数据边界

该数据库保存业务后端数据，包括用户、套餐、模板、业务抓拍记录和 AI 任务。`device_runtime` 的实时视频状态、WebRTC 会话和设备本地抓拍不直接写入该库；设备抓拍默认保存在设备运行端的 `captures` 目录。

## 升级注意

`backend/app/core/db.py` 中还有少量兼容补丁，用于给旧数据库补充新增字段和约束。已有库升级时建议优先跑 `python init_db.py`。
