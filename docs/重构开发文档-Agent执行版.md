# 云影随行重构开发文档 Agent 执行版

本文档用于指导后续使用多个 agent 进行并行开发。它不是宣传稿，而是开发约定、接口约定、数据库约定和任务拆分基准。

## 1. 重构目标

本次重构的目标不是单纯减少代码量，而是把项目整理成一条清晰、稳定、可演示、可扩展的产品主线。

核心目标：

1. 手机端负责画面、预览、拍照、录像、关键点、骨架、模板线框、AI 推荐框显示。
2. 树莓派端负责 TTL 总线舵机控制、云台状态、手势触发辅助、自动跟随执行。
3. 服务器端负责账号、设备、媒体文件、模板、AI 任务、AI Provider 配置和大模型调用。
4. 管理员端负责用户、设备、模板、媒体记录、AI 任务和 AI 配置管理。
5. 设备联动时也以主手机摄像头画面为准，不再依赖树莓派回传画面作为用户看到的主预览。
6. 所有 AI 分析都统一走服务器端，避免手机端、树莓派端、后端各自维护一套 AI 配置。

一句话架构原则：

```text
手机负责画面，树莓派负责转动，服务器负责智能，后台负责管理。
```

## 2. 四端职责边界

### 2.1 手机端 mobile_client

手机端是用户主入口，也是所有实时视觉叠加的唯一绘制端。

必须负责：

- 相机实时预览。
- 人体关键点识别。
- 骨架线绘制。
- 人体框绘制。
- 模板姿势线框绘制。
- AI 背景分析推荐框绘制。
- 拍照。
- 录像。
- 保存照片和视频到手机相册。
- 上传照片和视频到服务器。
- 从相册选择照片上传。
- 多图上传并展示 AI 选中的最佳照片。
- 设备联动界面中的主手机预览和云台控制 UI。
- 第二台手机作为遥控器时的摇杆控制 UI。

不应该负责：

- 直接保存云端 AI Provider 密钥。
- 直接调用大模型 API。
- 维护长期业务数据。
- 执行 TTL 舵机底层协议。

### 2.2 树莓派端 device_runtime

树莓派端是云台控制节点，不再是主画面来源。

必须负责：

- TTL 总线舵机控制。
- 云台 pan/tilt 角度状态。
- 手动摇杆控制命令执行。
- 自动跟随控制命令执行。
- 云台回中。
- 云台移动限位。
- 接收主手机上报的目标点偏移。
- 按手机或服务器命令执行多角度扫描。
- 设备健康检查。
- 设备会话打开和关闭。

可选负责：

- 手势状态辅助识别。
- 简单的本地安全保护，例如移动频率限制、角度边界限制。
- 本地日志和调试状态。

不应该作为第一版主职责：

- 不作为最终预览画面的提供者。
- 不作为主要关键点识别端。
- 不直接调用云端大模型。
- 不保存最终用户作品的权威记录。

只有以下情况才考虑让树莓派计算关键点：

1. 树莓派自己接了摄像头，并且最终画面也来自树莓派摄像头。
2. 手机性能不足，必须把帧推给树莓派处理。
3. 希望树莓派离线独立运行，不依赖手机。

当前重构主线不采用这三种路线。

### 2.3 服务器端 backend

服务器端是业务和 AI 的权威中心。

必须负责：

- 用户和管理员登录。
- 用户信息。
- 设备信息。
- 拍摄会话。
- 照片和视频文件记录。
- 模板记录。
- AI 任务创建、执行、查询。
- AI Provider 配置。
- 调用云端大模型。
- 返回评分、评价、推荐框、推荐角度、最佳照片等结构化结果。

不应该负责：

- 实时绘制手机预览 UI。
- 执行 TTL 舵机底层协议。
- 保存手机本地相册状态的唯一真相。

### 2.4 管理员端 admin_web

管理员端第一版可以复用现有结构，但需要把展示重点收敛到本次重构主线。

必须负责：

- 用户管理。
- 设备管理。
- 模板管理。
- 照片和视频记录管理。
- AI 任务记录管理。
- AI Provider 配置管理。
- 基础统计。

可以弱化或隐藏：

- 复杂会员订阅。
- 商业化套餐。
- 不参与演示的统计页面。
- 实验功能入口。

## 3. 两大使用模式

### 3.1 只有手机 mobile_only

用户只使用一台手机完成拍摄。

功能范围：

- 实时预览。
- 人物关键点、骨架线、人体框显示。
- 拍照模式。
- 录像模式。
- 拍照保存到手机相册。
- 录像保存到手机相册。
- 从相册选择照片上传。
- 现场拍摄后上传。
- AI 单图评分，返回 0 到 100 分和文字评价。
- AI 背景分析指导拍摄。
- 多图上传，AI 选择评分最高的一张并标记。
- 模板照片上传。
- 模板中的人物姿势和位置叠加到实时画面，方便模仿。

推荐会话模式枚举：

```text
mobile_only
```

### 3.2 手机 + 云台 gimbal

云台模式中至少有一台主手机，也可以有第二台控制手机。

角色定义：

```text
主手机：
放在云台上，负责实时预览、关键点识别、拍照、录像、上传和视觉叠加。

控制手机：
拿在用户手里，负责摇杆控制、模式切换、触发拍摄、查看状态。

树莓派：
固定在云台控制盒中，负责接收控制命令并驱动 TTL 总线舵机。
```

功能范围：

- 主手机预览和拍摄。
- 第二台手机摇杆控制云台。
- 手势触发拍摄。
- 拳头张开再合上触发手动拍摄。
- OK 手势触发强制拍摄。
- 自动跟随。
- 以面部中心或肩部中心作为跟随目标。
- 手动点击或手势触发拍摄。
- 模板拍摄。
- 云台自动转动，让真人和模板人物位置尽量对齐。
- AI 自动找角度。
- AI 背景分析。
- 云台转到推荐角度。
- 手机画面中显示推荐姿势框。

推荐会话模式枚举：

```text
gimbal_manual
gimbal_follow
gimbal_template
ai_auto_angle
ai_background
```

## 4. 关键架构决策

### 4.1 画面权威属于手机

设备联动时，用户看到的实时画面仍然来自主手机摄像头。

因此：

- 骨架线由手机端画。
- 人体框由手机端画。
- 模板线框由手机端画。
- AI 背景分析推荐框由手机端画。
- 录像由手机端录。
- 最终照片由手机端拍。
- 树莓派只控制云台，不返回最终画面。

### 4.2 所有视觉坐标使用归一化坐标

所有跨端传输的视觉坐标必须使用 0 到 1 的归一化坐标。

不要跨端传屏幕像素坐标。

统一约定：

```text
x: 距离画面左侧比例，范围 0 到 1
y: 距离画面顶部比例，范围 0 到 1
w: 宽度比例，范围 0 到 1
h: 高度比例，范围 0 到 1
```

示例：

```json
{
  "x": 0.56,
  "y": 0.18,
  "w": 0.28,
  "h": 0.58
}
```

### 4.3 手机端必须有统一的坐标转换层

手机相机画面经常存在以下问题：

- 预览画面和相机原始分辨率比例不同。
- 预览可能使用 cover 裁剪。
- 前置摄像头可能涉及镜像。
- 横屏和竖屏坐标不同。
- 拍照保存方向和预览方向可能不同。

因此手机端必须统一封装：

```text
NormalizedCoordinate
PreviewTransform
CameraImageCoordinate
ScreenOverlayCoordinate
```

所有叠加元素必须走同一套转换逻辑：

- 实时人体框。
- 实时骨架线。
- 模板姿势线。
- AI 推荐框。
- 手势提示框。
- 跟随目标点。

验收标准：

```text
同一个人站在画面中时，人体框、骨架线、模板线、推荐框都不会出现各偏各的情况。
```

### 4.4 AI 分析统一由服务器执行

服务器负责：

- 保存 AI Provider 配置。
- 保存 API Key。
- 调用大模型。
- 解析大模型结果。
- 写入 ai_tasks。
- 返回结构化结果。

手机端和树莓派端只负责上传材料和展示结果。

### 4.5 长任务必须可查询状态

以下任务不是一次请求立即完成：

- AI 自动找角度。
- AI 背景分析。
- 多图选最佳。
- 视频分析。

这些必须按任务模型处理：

```text
创建任务 -> status=pending
开始执行 -> status=running
完成 -> status=succeeded
失败 -> status=failed
取消 -> status=cancelled
```

手机端通过轮询或后续 WebSocket 查询任务状态。

## 5. 数据库设计建议

现有数据库已经有基础表：

```text
users
devices
templates
capture_sessions
captures
ai_tasks
ai_provider_configs
plans
user_subscriptions
```

重构时建议尽量复用已有表，降低迁移风险。第一版可以继续使用 `captures` 表，但语义上把它理解成媒体资源表。后续如果时间充足，再将它重命名或迁移为 `media_assets`。

### 5.1 users 用户表

用途：

- 手机端用户。
- 管理员。

关键字段：

```text
id
user_code
phone
email
password_hash
display_name
avatar_url
role              user / admin
status            active / inactive / disabled
last_login_at
created_at
updated_at
```

建议：

- 如果比赛演示不强调复杂账号体系，保留基础登录即可。
- 不要在第一版继续扩展复杂会员订阅逻辑。

### 5.2 devices 设备表

用途：

- 记录树莓派云台设备。

关键字段：

```text
id
user_id
device_code
device_name
device_type        raspberry_pi_gimbal
serial_number
local_ip
control_base_url
firmware_version
status             offline / online / busy / disabled
is_online
last_seen_at
created_at
updated_at
```

建议新增或放入 metadata 的字段：

```json
{
  "hardware": {
    "board": "raspberry_pi_5_8g",
    "servo_type": "ttl_bus",
    "pan_servo_id": 1,
    "tilt_servo_id": 2
  },
  "limits": {
    "pan_min": -90,
    "pan_max": 90,
    "tilt_min": -45,
    "tilt_max": 45
  }
}
```

### 5.3 capture_sessions 拍摄会话表

用途：

- 一次拍摄过程。
- 只有手机模式和云台模式都必须创建会话。

关键字段：

```text
id
session_code
user_id
device_id
template_id
mode
status
started_at
ended_at
metadata
created_at
updated_at
```

推荐 mode：

```text
mobile_only
gimbal_manual
gimbal_follow
gimbal_template
ai_auto_angle
ai_background
```

推荐 status：

```text
opened
closed
cancelled
```

metadata 示例：

```json
{
  "preview_source": "phone_camera",
  "main_phone_id": "phone-a",
  "controller_phone_id": "phone-b",
  "camera": {
    "lens": "back",
    "orientation": "portrait",
    "mirror_preview": false
  },
  "follow": {
    "target": "shoulder_center",
    "enabled": true
  }
}
```

### 5.4 captures 媒体记录表

当前仓库已有 `captures` 表。重构第一版建议继续使用它，但补充媒体语义。

用途：

- 单张照片。
- 多图连拍中的某一张。
- AI 选中的最佳照片。
- 背景分析照片。
- 视频记录。

建议字段：

```text
id
session_id
user_id
media_type          photo / video
capture_type        single / burst / best / background / template / recording
file_url
thumbnail_url
width
height
duration_ms         视频使用
storage_provider    local / server / object_storage
local_album_saved   true / false
is_ai_selected
score
metadata
created_at
updated_at
```

metadata 示例：

```json
{
  "source": "phone_camera",
  "capture_trigger": "button",
  "album_saved": true,
  "device_pose": {
    "pan": 12.5,
    "tilt": -3.0
  },
  "camera": {
    "lens": "back",
    "orientation": "portrait",
    "mirror_saved": false
  }
}
```

如果暂时不改表结构，可以先把 `media_type`、`duration_ms`、`local_album_saved` 放到 `metadata` 中。

### 5.5 templates 模板表

用途：

- 保存用户上传的模板照片。
- 保存模板人物关键点。
- 保存模板人体框。
- 保存模板参考中心点和缩放比例。

关键字段：

```text
id
user_id
name
template_type        pose / composition / background
source_image_url
preview_image_url
template_data
status
created_at
updated_at
```

template_data 示例：

```json
{
  "coordinate_space": "normalized",
  "image": {
    "width": 1080,
    "height": 1920,
    "orientation": "portrait"
  },
  "person_box": {
    "x": 0.28,
    "y": 0.12,
    "w": 0.44,
    "h": 0.72
  },
  "reference": {
    "center": {
      "x": 0.50,
      "y": 0.48
    },
    "scale": 0.72,
    "primary_target": "shoulder_center"
  },
  "keypoints": [
    {
      "name": "left_shoulder",
      "x": 0.38,
      "y": 0.31,
      "score": 0.95
    },
    {
      "name": "right_shoulder",
      "x": 0.61,
      "y": 0.31,
      "score": 0.94
    }
  ]
}
```

### 5.6 ai_tasks AI 任务表

用途：

- 统一记录所有 AI 请求。
- 支持长任务。
- 支持后台查看。

关键字段：

```text
id
task_code
user_id
session_id
capture_id
device_id
task_type
status
provider_name
request_payload
response_payload
result_summary
result_score
recommended_pan_delta
recommended_tilt_delta
target_box_norm
error_message
finished_at
created_at
updated_at
```

推荐 task_type：

```text
analyze_photo
analyze_background
batch_pick
auto_angle
template_match
video_analysis
```

target_box_norm 示例：

```json
{
  "x": 0.56,
  "y": 0.18,
  "w": 0.28,
  "h": 0.58,
  "label": "recommended_person_position"
}
```

response_payload 示例：

```json
{
  "score": 86,
  "summary": "人物位置自然，背景层次较好，建议身体略向左侧转动。",
  "strengths": [
    "主体清晰",
    "背景干净"
  ],
  "suggestions": [
    "头部略向左偏",
    "保留右侧背景空间"
  ],
  "target_box_norm": {
    "x": 0.56,
    "y": 0.18,
    "w": 0.28,
    "h": 0.58
  }
}
```

### 5.7 ai_provider_configs AI 配置表

用途：

- 管理云端大模型配置。

关键字段：

```text
provider_code
vendor_name
provider_format
display_name
api_base_url
api_key
model_name
enabled
is_default
extra_config
```

重构要求：

- 手机端不能持有 API Key。
- 树莓派端第一版不再持有 AI Key。
- AI Key 只在服务器端配置和调用。
- 管理员端显示时必须脱敏。

### 5.8 gimbal_commands 云台命令表 可选

第一版可选，但强烈建议加入，方便调试自动跟随和摇杆控制。

用途：

- 记录云台移动命令。
- 排查为什么云台转动异常。
- 对齐手机目标点和树莓派实际动作。

字段建议：

```text
id
session_id
device_id
command_type       joystick / follow / template_align / auto_angle / home
source             main_phone / controller_phone / server / device_runtime
target_x
target_y
pan_delta
tilt_delta
pan_after
tilt_after
status             pending / sent / applied / failed
error_message
created_at
applied_at
```

### 5.9 pose_snapshots 姿态快照表 可选

第一版可以不建。若后续需要复盘关键点识别效果，再引入。

字段建议：

```text
id
session_id
capture_id
source             phone / server
person_box
keypoints
confidence
created_at
```

第一版建议：

```text
模板关键点存 templates.template_data。
拍摄时的关键点快照先存 captures.metadata。
不要过早新增 pose_snapshots 表。
```

## 6. 后端接口约定

### 6.1 基础返回格式

统一使用：

```json
{
  "success": true,
  "message": "ok",
  "data": {}
}
```

错误返回：

```json
{
  "success": false,
  "message": "error message",
  "data": null
}
```

### 6.2 手机端接口 /api/mobile

#### 创建拍摄会话

```http
POST /api/mobile/sessions
```

请求：

```json
{
  "device_id": 1,
  "template_id": 2,
  "mode": "gimbal_follow",
  "metadata": {
    "preview_source": "phone_camera",
    "follow": {
      "target": "shoulder_center"
    }
  }
}
```

返回：

```json
{
  "id": 1001,
  "session_code": "S202605150001",
  "mode": "gimbal_follow",
  "status": "opened"
}
```

#### 上传媒体文件

```http
POST /api/mobile/media/upload
```

第一版可复用现有：

```http
POST /api/mobile/captures/file
```

建议新接口支持照片和视频：

表单字段：

```text
file
media_type: photo / video
session_id
capture_type
metadata
```

返回：

```json
{
  "file_url": "/uploads/2026/05/15/photo.jpg",
  "storage_provider": "local",
  "storage_path": "uploads/2026/05/15/photo.jpg",
  "relative_path": "2026/05/15/photo.jpg",
  "original_filename": "photo.jpg",
  "content_type": "image/jpeg"
}
```

#### 创建媒体记录

```http
POST /api/mobile/captures/upload
```

请求：

```json
{
  "session_id": 1001,
  "capture_type": "single",
  "file_url": "/uploads/2026/05/15/photo.jpg",
  "thumbnail_url": null,
  "width": 1080,
  "height": 1920,
  "storage_provider": "local",
  "is_ai_selected": false,
  "score": null,
  "metadata": {
    "media_type": "photo",
    "local_album_saved": true,
    "source": "phone_camera"
  }
}
```

#### 单图 AI 分析

```http
POST /api/mobile/ai/analyze-photo
```

请求：

```json
{
  "session_id": 1001,
  "capture_id": 2001
}
```

返回：

```json
{
  "id": 3001,
  "task_type": "analyze_photo",
  "status": "succeeded",
  "result_score": 86,
  "result_summary": "主体清晰，构图较好，建议头部略向左侧偏转。",
  "response_payload": {
    "score": 86,
    "comment": "主体清晰，构图较好。",
    "suggestions": [
      "肩部放松",
      "保留右侧背景空间"
    ]
  }
}
```

#### 背景分析

```http
POST /api/mobile/ai/analyze-background
```

请求：

```json
{
  "session_id": 1001,
  "capture_id": 2002,
  "device_id": 1
}
```

返回重点：

```json
{
  "task_type": "analyze_background",
  "status": "succeeded",
  "result_summary": "建议人物站在右侧三分之一处，保留左侧建筑线条。",
  "target_box_norm": {
    "x": 0.56,
    "y": 0.18,
    "w": 0.28,
    "h": 0.58
  },
  "recommended_pan_delta": 8,
  "recommended_tilt_delta": -2
}
```

手机端用 `target_box_norm` 在实时预览画面中画推荐姿势框。

#### 多图选最佳

```http
POST /api/mobile/ai/batch-pick
```

请求：

```json
{
  "session_id": 1001,
  "capture_ids": [2001, 2002, 2003]
}
```

返回：

```json
{
  "task": {
    "id": 3002,
    "task_type": "batch_pick",
    "status": "succeeded",
    "result_summary": "第 2 张主体最清晰，表情自然，背景干扰最少。",
    "response_payload": {
      "best_capture_id": 2002,
      "scores": [
        {
          "capture_id": 2001,
          "score": 78
        },
        {
          "capture_id": 2002,
          "score": 91
        },
        {
          "capture_id": 2003,
          "score": 83
        }
      ]
    }
  },
  "best_capture_id": 2002
}
```

#### 创建模板

```http
POST /api/mobile/templates
```

请求：

```json
{
  "name": "站姿模板",
  "template_type": "pose",
  "source_image_url": "/uploads/templates/template.jpg",
  "preview_image_url": "/uploads/templates/template_preview.jpg",
  "template_data": {
    "coordinate_space": "normalized",
    "person_box": {
      "x": 0.28,
      "y": 0.12,
      "w": 0.44,
      "h": 0.72
    },
    "keypoints": []
  }
}
```

### 6.3 管理员端接口 /api/admin

管理员端继续复用现有接口方向。

必须保留：

```text
POST /api/admin/login
GET  /api/admin/users
GET  /api/admin/devices
GET  /api/admin/captures
GET  /api/admin/templates/recommended
GET  /api/admin/ai/tasks
GET  /api/admin/ai/provider-configs
PUT  /api/admin/ai/provider-configs/{config_id}
GET  /api/admin/statistics/overview
```

可弱化：

```text
plans
subscriptions
商业化 quota
```

## 7. 树莓派设备端接口约定

设备端接口只处理控制和状态，不处理最终 AI 结果。

### 7.1 健康检查

```http
GET /api/device/health
```

返回：

```json
{
  "success": true,
  "message": "ok",
  "data": {
    "device_code": "DEV_RUNTIME_LOCAL",
    "status": "idle",
    "service_version": "0.1.0",
    "session_code": null
  }
}
```

### 7.2 打开设备会话

```http
POST /api/device/session/open
```

请求：

```json
{
  "session_code": "S202605150001",
  "mode": "gimbal_follow",
  "preview_source": "phone_camera",
  "mirror_view": false
}
```

### 7.3 手动摇杆控制

```http
POST /api/device/control/manual-move
```

请求：

```json
{
  "pan_delta": 4.0,
  "tilt_delta": -1.5,
  "source": "controller_phone"
}
```

要求：

- 树莓派端必须做角度限位。
- 树莓派端必须做移动频率限制。
- 返回当前 pan/tilt。

### 7.4 自动跟随目标上报

建议新增：

```http
POST /api/device/control/track-target
```

请求：

```json
{
  "target": "shoulder_center",
  "x": 0.43,
  "y": 0.52,
  "confidence": 0.91,
  "frame": {
    "width": 1080,
    "height": 1920,
    "orientation": "portrait",
    "mirror": false
  },
  "timestamp_ms": 1760000000000
}
```

树莓派端根据 `x/y` 相对 0.5 的偏移控制云台。

要求：

- 低置信度不移动。
- 偏移小于死区不移动。
- 单次移动不能过大。
- 必须支持 `target=face_center` 和 `target=shoulder_center`。

### 7.5 设置跟随模式

```http
POST /api/device/control/follow-mode
```

请求：

```json
{
  "enabled": true,
  "target": "shoulder_center",
  "dead_zone": 0.06,
  "speed": "normal"
}
```

### 7.6 触发拍摄

```http
POST /api/device/capture/trigger
```

注意：

如果画面来自手机，则这个接口不能让树莓派自己拍最终照片。它应该通知主手机拍照，或者只记录一次触发事件。

建议逻辑：

```text
控制手机/树莓派发出触发 -> 主手机收到触发 -> 主手机拍照 -> 主手机保存相册 -> 主手机上传服务器
```

### 7.7 AI 自动找角度

建议由手机端或服务器端编排，树莓派端只执行转动。

接口：

```http
POST /api/device/ai/angle-search/start
```

请求：

```json
{
  "session_code": "S202605150001",
  "shot_count": 5,
  "delay_s": 3,
  "pan_step": 8,
  "tilt_step": 0,
  "settings": {
    "return_home_after": false
  }
}
```

流程：

```text
1. 手机端创建 ai_auto_angle 会话。
2. 手机端显示倒计时。
3. 手机端通知树莓派移动到第一个角度。
4. 主手机拍摄并上传。
5. 重复多次。
6. 手机端调用服务器 batch_pick 或 auto_angle。
7. 服务器返回最佳照片。
8. 手机端标记最佳照片。
```

### 7.8 AI 背景分析

流程：

```text
1. 用户选择 AI 背景分析。
2. 主手机拍摄一张或多张背景照片。
3. 上传服务器。
4. 服务器返回推荐角度和 target_box_norm。
5. 树莓派转到推荐角度。
6. 主手机在实时画面画出推荐站位框。
```

## 8. 手机端视觉叠加约定

### 8.1 叠加元素分类

手机端需要支持以下 overlay：

```text
live_person_box        实时人体框
live_pose_skeleton     实时骨架线
template_pose          模板姿态线
ai_target_box          AI 推荐站位框
follow_target_point    自动跟随目标点
gesture_status         手势状态提示
recording_status       录像状态
```

### 8.2 统一数据结构

BoxNorm：

```json
{
  "x": 0.28,
  "y": 0.12,
  "w": 0.44,
  "h": 0.72
}
```

KeypointNorm：

```json
{
  "name": "left_shoulder",
  "x": 0.38,
  "y": 0.31,
  "score": 0.95
}
```

PoseNorm：

```json
{
  "person_box": {
    "x": 0.28,
    "y": 0.12,
    "w": 0.44,
    "h": 0.72
  },
  "keypoints": [],
  "center": {
    "x": 0.50,
    "y": 0.48
  }
}
```

### 8.3 模板线框绘制

模板上传时：

```text
读取模板照片 -> 识别人体关键点 -> 转成归一化坐标 -> 存入 templates.template_data
```

实时预览时：

```text
读取 template_data -> 通过 PreviewTransform 转成屏幕坐标 -> 绘制模板线框
```

要求：

- 模板线框默认半透明。
- 模板人体框和骨架线颜色应区别于实时人体骨架。
- 支持开关模板显示。
- 支持调整模板透明度。
- 支持按画面适配，不允许写死像素。

### 8.4 AI 背景推荐框绘制

服务器返回：

```json
{
  "target_box_norm": {
    "x": 0.56,
    "y": 0.18,
    "w": 0.28,
    "h": 0.58
  }
}
```

手机端：

```text
target_box_norm -> PreviewTransform -> 屏幕矩形 -> 绘制推荐框
```

要求：

- 推荐框必须跟随预览区域变化。
- 横竖屏切换后仍然正确。
- 前后摄像头切换后仍然正确。
- 推荐框不能直接用服务器像素坐标。

### 8.5 镜像约定

默认：

```text
预览不镜像。
保存照片不镜像。
设备联动画面不镜像。
```

如需前置摄像头镜像，仅作为 UI 可选项处理，不影响服务器和数据库中的归一化坐标定义。

## 9. 关键业务流程

### 9.1 手机单机拍照 + AI 分析

```text
1. 用户进入手机单机模式。
2. 手机打开摄像头预览。
3. 手机本地识别人像关键点，绘制骨架线和人体框。
4. 用户拍照。
5. 手机保存照片到相册。
6. 手机上传照片到服务器。
7. 手机创建 captures 记录。
8. 手机调用 analyze_photo。
9. 服务器调用大模型。
10. 服务器写入 ai_tasks。
11. 手机展示评分和评价。
```

### 9.2 相册选择照片 + AI 分析

```text
1. 用户从相册选择照片。
2. 手机上传照片。
3. 服务器创建媒体记录。
4. 手机调用 analyze_photo。
5. 展示评分和评价。
```

### 9.3 多图选最佳

```text
1. 用户选择多张照片或现场连拍多张。
2. 手机逐张上传。
3. 手机创建 captures 记录。
4. 手机调用 batch_pick。
5. 服务器调用大模型打分。
6. 服务器返回 best_capture_id。
7. 手机标记最佳照片。
8. 管理端可查看该照片 is_ai_selected=true。
```

### 9.4 模板拍摄 手机单机

```text
1. 用户上传模板照片。
2. 手机或服务器识别模板人物关键点。
3. 保存 templates.template_data。
4. 用户进入预览。
5. 手机绘制实时骨架线。
6. 手机绘制模板骨架线。
7. 用户对齐后拍照或录像。
```

### 9.5 第二手机摇杆控制云台

```text
1. 主手机打开设备联动会话。
2. 控制手机加入同一个 session_code。
3. 控制手机显示摇杆。
4. 控制手机发送 manual-move 到树莓派。
5. 树莓派驱动 TTL 舵机。
6. 主手机画面变化。
7. 主手机继续负责预览和拍摄。
```

### 9.6 自动跟随

```text
1. 用户选择自动跟随。
2. 用户选择 face_center 或 shoulder_center。
3. 主手机实时识别目标点。
4. 主手机将目标点归一化坐标发送给树莓派。
5. 树莓派根据偏移控制云台。
6. 目标点接近画面中心后停止微调。
7. 用户通过手势、按钮或控制手机触发拍摄。
```

### 9.7 云台模板拍摄

第一版建议只做中心点和人体框对齐，不做复杂全身关键点完全重合。

```text
1. 用户选择模板。
2. 手机读取模板 person_box 和 shoulder_center。
3. 手机识别实时 person_box 和 shoulder_center。
4. 手机计算实时中心点与模板中心点的偏移。
5. 手机向树莓派发送 track-target 或 align-target。
6. 树莓派微调云台。
7. 手机绘制模板线框和实时骨架。
8. 用户对齐后拍摄。
```

### 9.8 AI 自动找角度

```text
1. 用户打开 AI 自动找角度。
2. 默认倒计时 3 秒。
3. 高级设置中可配置拍摄张数、步长、角度范围。
4. 主手机发起会话。
5. 树莓派按计划转动。
6. 主手机每个角度拍一张并保存相册。
7. 主手机上传所有照片。
8. 服务器执行 auto_angle 或 batch_pick。
9. 服务器返回最佳照片和理由。
10. 手机标记最佳照片。
```

高级设置默认隐藏：

```text
shot_count
delay_s
pan_step
tilt_step
pan_range
tilt_range
return_home_after
```

### 9.9 AI 背景分析

```text
1. 用户选择 AI 背景分析。
2. 主手机拍摄背景照片。
3. 可选：云台转动后拍摄多张背景照片。
4. 手机上传背景照片。
5. 服务器调用大模型。
6. 服务器返回推荐角度和 target_box_norm。
7. 树莓派转到推荐角度。
8. 手机在实时预览中画出推荐站位框。
9. 用户站到框中。
10. 用户拍照或录像。
```

### 9.10 录像

第一版录像需求：

```text
1. 手机端支持开始录像和停止录像。
2. 录像保存到手机相册。
3. 录像可上传服务器。
4. 后台可查看视频记录。
5. AI 视频分析先预留 task_type，不必第一版完整实现。
```

录像数据库要求：

```text
captures.metadata.media_type = video
captures.metadata.duration_ms = 录像时长
captures.thumbnail_url = 视频封面
```

## 10. Agent 开发任务拆分

### 10.1 Agent A 手机端视觉与相机

负责目录：

```text
mobile_client/lib/features/camera
mobile_client/lib/features/device_link
mobile_client/lib/shared 或新增的视觉坐标工具目录
```

任务：

1. 建立统一视觉坐标模型。
2. 建立 PreviewTransform。
3. 将人体框、骨架线、模板线、AI 推荐框统一接入 PreviewTransform。
4. 手机单机模式支持拍照保存相册。
5. 手机单机模式支持录像保存相册。
6. 相册选择照片上传。
7. 多图选择上传。
8. 设备联动界面改为主手机摄像头预览。

验收：

```text
flutter analyze
flutter test
flutter build apk --release
```

手动验收：

```text
前后摄像头切换后，人体框和骨架线仍然对齐。
横竖屏或不同手机尺寸下，模板线框不偏移。
AI 推荐框在预览画面中的位置正确。
拍照和录像能进入手机相册。
```

### 10.2 Agent B 树莓派端云台控制

负责目录：

```text
device_runtime
```

任务：

1. 确认 TTL 总线舵机控制接口。
2. 整理 pan/tilt 限位。
3. 实现或整理 manual-move。
4. 实现 track-target。
5. 整理 follow-mode。
6. 支持 face_center 和 shoulder_center。
7. 支持 home。
8. 支持 AI 自动找角度中的分步移动。
9. 移除或弱化树莓派直接大模型调用。

验收：

```text
python -m compileall -q device_runtime
GET /api/device/health 返回 200
manual-move 能控制舵机
track-target 输入 x/y 后云台方向正确
角度不会超过安全限制
```

### 10.3 Agent C 后端数据库与 AI 任务

负责目录：

```text
backend
database
uploads
```

任务：

1. 梳理并迁移数据库枚举。
2. captures 支持照片和视频语义。
3. ai_tasks 支持新的 task_type。
4. 统一 AI Provider 调用。
5. 实现 analyze_photo。
6. 实现 analyze_background。
7. 实现 batch_pick。
8. 预留 auto_angle 和 video_analysis。
9. 确保 API Key 只存在服务器端。
10. 补充 pytest 开发依赖。

验收：

```text
python -m compileall -q backend/app backend/tests backend/main.py backend/init_db.py
GET /api/health 返回 200
上传图片后能创建 capture
analyze_photo 能创建 ai_task
batch_pick 能返回 best_capture_id
```

### 10.4 Agent D 管理员端与工程脚本

负责目录：

```text
admin_web
scripts
docs
```

任务：

1. 管理后台保留用户、设备、媒体、模板、AI 任务、AI 配置。
2. 弱化 plans 和 subscriptions。
3. 媒体列表支持 photo/video。
4. AI 任务列表显示 task_type、status、score、summary。
5. AI Provider 配置脱敏显示 API Key。
6. 优化 admin_web 构建体积。
7. 新增 scripts/check_project.ps1。
8. 新增 scripts/clean_workspace.ps1 可选。

验收：

```text
npm run build
后台能查看媒体记录
后台能查看 AI 任务
后台能编辑 AI Provider 配置
scripts/check_project.ps1 能跑完整检查
```

## 11. 开发顺序建议

不要四个人同时乱改。建议按以下顺序推进：

### 第一阶段：锁定接口和数据结构

负责人：

```text
后端 Agent C 主导，其他 agent 配合确认字段。
```

产出：

```text
数据库迁移草案
接口请求和响应 JSON
mode 和 task_type 枚举
坐标结构约定
```

### 第二阶段：手机端坐标和视觉叠加

负责人：

```text
手机 Agent A
```

原因：

模板线框和 AI 推荐框是否准确，决定后续云台跟随是否可靠。

### 第三阶段：云台手动控制和自动跟随

负责人：

```text
树莓派 Agent B
```

前提：

手机端已经能输出稳定的 `target_x/target_y`。

### 第四阶段：AI 任务闭环

负责人：

```text
后端 Agent C + 手机 Agent A
```

内容：

```text
上传照片 -> 创建记录 -> 创建 AI 任务 -> 大模型返回 -> 手机展示
```

### 第五阶段：管理员端复用和精简

负责人：

```text
管理员端 Agent D
```

内容：

```text
让后台围绕新数据结构展示，不再扩展无关功能。
```

### 第六阶段：录像和高级功能

负责人：

```text
手机 Agent A + 后端 Agent C
```

内容：

```text
录像保存相册
视频上传
后台显示视频
AI 视频分析预留
```

## 12. 第一版 MVP 范围

第一版必须完成：

```text
手机单机：
实时预览
人体关键点
骨架线
人体框
拍照保存相册
相册选择上传
AI 单图评分
多图选最佳
模板叠加

云台联动：
主手机预览
第二手机摇杆控制
TTL 舵机转动
自动跟随 face_center / shoulder_center
AI 自动找角度基础流程
AI 背景推荐框显示

后台：
用户
设备
媒体记录
模板
AI 任务
AI 配置
```

第一版可以暂缓：

```text
复杂 WebRTC
复杂会员订阅
视频 AI 分析
全身关键点完全模板重合
多设备并发控制
树莓派端独立视觉识别
复杂商业化统计
```

## 13. 风险和注意事项

### 13.1 两台手机协同

必须明确主手机和控制手机。

如果不区分，会出现：

```text
控制手机以为自己在拍照
主手机没有收到触发
树莓派执行了动作但照片没有保存
```

建议：

```text
所有最终拍照和录像都由主手机执行。
控制手机只发控制命令。
```

### 13.2 预览和保存方向

不能假设预览方向就是保存方向。

必须分别验证：

```text
预览方向
骨架方向
模板方向
AI 推荐框方向
保存照片方向
上传照片方向
```

### 13.3 前置摄像头镜像

默认不镜像。

如果提供镜像开关，也必须让：

```text
预览
骨架
人体框
模板线
AI 推荐框
保存照片
上传照片
```

保持一致或明确转换。

### 13.4 AI 结果必须结构化

不要只让大模型返回一段文字。

必须要求返回：

```text
score
summary
suggestions
best_capture_id
target_box_norm
recommended_pan_delta
recommended_tilt_delta
```

按不同任务返回对应字段。

### 13.5 自动跟随不要第一版过度复杂

第一版只做：

```text
face_center 居中
shoulder_center 居中
死区控制
限速控制
角度限位
```

不要一开始做复杂 PID 或全身姿态重合。

### 13.6 AI 背景推荐框不是拍摄框

推荐框的含义是：

```text
建议人物站在这里。
```

不是相机裁剪框，也不是最终照片裁剪框。

手机端 UI 要表达清楚。

### 13.7 设备端进程必须重启验证

树莓派端改动后，只改代码不等于运行生效。

必须验证：

```text
设备端服务已经重启
GET /api/device/health 版本和状态正确
实际舵机动作正确
```

## 14. 给 Agent 的通用开发规则

每个 agent 开始前必须：

```text
1. 先读本开发文档。
2. 只修改自己负责的目录。
3. 不随意重命名跨端字段。
4. 所有跨端字段先写入接口约定。
5. 每次完成一个小功能就运行对应检查。
6. 不要引入新的 AI 配置路径。
7. 不要让树莓派重新成为主预览画面来源。
8. 不要把服务器像素坐标直接画到手机屏幕。
```

提交前最低检查：

```text
mobile_client:
flutter analyze
flutter test

backend:
python -m compileall -q backend/app backend/tests backend/main.py backend/init_db.py

device_runtime:
python -m compileall -q device_runtime

admin_web:
npm run build
```

## 15. 推荐 Agent Prompt 模板

### 15.1 手机端 Agent Prompt

```text
你负责 mobile_client 重构。请先阅读 docs/重构开发文档-Agent执行版.md。
本次只处理手机端视觉坐标和 overlay，不修改后端和树莓派端。
目标：建立统一的归一化坐标到预览屏幕坐标转换层，并让人体框、骨架线、模板线框、AI 推荐框共用它。
完成后运行 flutter analyze 和 flutter test。
不要改变用户主流程，不要引入新的服务器接口字段，若必须新增字段先在文档中说明。
```

### 15.2 树莓派端 Agent Prompt

```text
你负责 device_runtime 重构。请先阅读 docs/重构开发文档-Agent执行版.md。
本次只处理树莓派云台控制，不做关键点识别，不调用大模型，不处理最终照片保存。
目标：整理 manual-move、follow-mode，并新增或实现 track-target，使主手机上报 normalized target 后云台能稳定微调。
必须加入死区、限速、角度限位。
完成后运行 python -m compileall -q device_runtime，并说明实际硬件验证步骤。
```

### 15.3 后端 Agent Prompt

```text
你负责 backend 和 database 重构。请先阅读 docs/重构开发文档-Agent执行版.md。
目标：统一 AI 任务、媒体记录、模板数据和 AI Provider 配置。
第一步不要大删表，优先兼容现有 captures、capture_sessions、ai_tasks、templates。
补充 task_type、mode、metadata 约定，并实现 analyze_photo、analyze_background、batch_pick 的结构化返回。
API Key 只能保存在服务器端，不能下发给手机或树莓派。
完成后运行 Python compileall，并给出接口测试样例。
```

### 15.4 管理员端 Agent Prompt

```text
你负责 admin_web、scripts 和文档整理。请先阅读 docs/重构开发文档-Agent执行版.md。
目标：让后台围绕用户、设备、媒体、模板、AI 任务、AI Provider 配置展示。
弱化 plans 和 subscriptions，不要扩展复杂商业化功能。
增加或整理一键检查脚本 scripts/check_project.ps1。
完成后运行 npm run build。
```

## 16. 当前仓库可复用基础

当前仓库已有可复用部分：

```text
backend:
用户、设备、模板、拍摄会话、照片记录、AI 任务、AI Provider 配置基础模型。

device_runtime:
设备健康检查、会话、控制、拍摄、模板、AI 角度搜索、背景分析相关接口雏形。

mobile_client:
相机页面、设备联动页面、Flutter 测试和 APK 构建基础。

admin_web:
Vue + Vite 管理后台，已有用户、设备、模板、AI 配置、统计等页面基础。
```

需要重点调整：

```text
1. 设备联动画面改为主手机摄像头画面。
2. 所有视觉 overlay 统一手机端绘制。
3. AI 调用统一后端。
4. captures 扩展为照片和视频都能表达。
5. 树莓派端聚焦云台控制。
6. 管理后台围绕新媒体和 AI 任务结构收敛。
```
