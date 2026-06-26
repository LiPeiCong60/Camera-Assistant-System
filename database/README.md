# database

`database` 保存 PostgreSQL schema。实际初始化推荐通过 `backend/init_db.py` 执行，因为后端还会运行兼容旧库的补丁。

## 核心表

| 表 | 说明 |
| --- | --- |
| `users` | 用户和管理员账号 |
| `plans` | 套餐、额度和 `feature_flags` |
| `user_subscriptions` | 用户当前订阅 |
| `devices` | 设备登记信息 |
| `templates` | 用户模板和推荐模板 |
| `capture_sessions` | 拍摄/设备联动/AI 扫描会话 |
| `captures` | 手机端照片、视频和媒体记录 |
| `ai_tasks` | AI 分析任务和结果 |
| `ai_provider_configs` | AI Provider 配置 |

## 当前枚举

### `capture_sessions.mode`

- `mobile_only`
- `gimbal_manual`
- `gimbal_follow`
- `gimbal_template`
- `ai_auto_angle`
- `ai_background`

### `captures.capture_type`

- `single`
- `burst`
- `best`
- `background`
- `template`
- `recording`

### `ai_tasks.task_type`

- `analyze_photo`
- `analyze_background`
- `batch_pick`
- `auto_angle`
- `template_match`
- `video_analysis`

## 坐标结构

所有跨端视觉坐标都使用 `0..1` 归一化坐标。推荐框 `target_box_norm` 存为 JSON 对象：

```json
{
  "x": 0.31,
  "y": 0.14,
  "w": 0.36,
  "h": 0.70,
  "label": "recommended_person_position"
}
```

模板 `template_data` 存储人物框、头部框、关键点和肩部/面部/头部锚点。手机端绘制时根据当前画面尺寸转换为屏幕坐标。

当前主字段为：

- `bbox_norm`、`head_bbox_norm`：人物框和头部框，格式 `[x, y, w, h]`。
- `pose_points_image`：整张图归一化关键点。
- `pose_points_bbox`：人物框内归一化关键点。
- `pose_points`：姿态相似度计算用的身体坐标系关键点。
- `shoulder_anchor_norm_x/y`、`face_anchor_norm_x/y`、`head_anchor_norm_x/y`：模板对齐锚点。

推荐模板通过 `templates.is_recommended_default` 和 `templates.recommended_sort_order` 区分；旧库由 `backend/app/core/db.py` 自动补列。

## 初始化

推荐方式：

```powershell
cd <repo-root>
.\.venv\Scripts\Activate.ps1
$env:DATABASE_URL="postgresql+psycopg://postgres:<db_password>@127.0.0.1:5432/camera_assistant"
python backend\init_db.py
```

手动执行 SQL：

```powershell
psql -d camera_assistant -f database/schema.sql
```

手动 SQL 适合全新库参考。已有库升级和推荐模板相关补列仍建议优先运行 `python backend\init_db.py`，因为它会执行 ORM 建表、兼容迁移和序列校准。

## 数据边界

数据库保存业务后端数据：用户、套餐、订阅、模板、拍摄会话、手机端媒体记录、AI 任务和 Provider 配置。

`device_runtime` 的实时帧、WebSocket 会话和云台状态不直接写入数据库。设备联动最终照片/视频由手机保存到相册，按用户设置再上传后端。

## 升级注意

`backend/app/core/db.py` 包含兼容补丁：

- 给旧库补新增字段。
- 迁移旧 `capture_type`、`task_type` 值。
- 重建检查约束。

已有库升级时优先运行：

```powershell
python backend\init_db.py
```
