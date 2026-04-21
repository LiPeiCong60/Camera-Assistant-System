# database

数据库模块，技术栈按定稿使用 PostgreSQL。

当前阶段先建立数据库目录骨架，后续小阶段再补：

- `schema.sql`：第一版核心表结构
- `migrations/`：后续迁移脚本目录

第一版需要覆盖的核心表包括：

- `users`
- `plans`
- `user_subscriptions`
- `devices`
- `templates`
- `capture_sessions`
- `captures`
- `ai_tasks`
