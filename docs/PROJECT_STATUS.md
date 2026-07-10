# 云影随行项目现状

> 状态快照：2026-07-10。本文以当前 `main` 工作区中的现有代码与配置为准。

## 1. 当前阶段

云影随行已经形成 Flutter 手机端、Python 设备运行时、FastAPI 业务后端、Vue 管理后台和 PostgreSQL 数据库组成的多端原型。核心数据契约和模块边界已经明确，适合课程展示、局域网联调和树莓派云台演示。

当前版本仍属于“可演示的工程原型”：软件模块较完整，但真实拍摄效果需要结合具体手机、摄像头、舵机、树莓派性能、网络延迟和视觉模型逐项标定。

## 2. 已实现能力

| 模块 | 当前实现 |
| --- | --- |
| Flutter 手机端 | 登录注册、拍照录像、模板 Overlay、AI 连拍选优、背景分析、历史记录、设备联动、服务地址配置 |
| 设备运行时 | 会话管理、手机帧输入、预览、MediaPipe/OpenCV 检测、手动控制、自动跟随、模板构图、TTL 总线舵机 |
| 业务后端 | 用户、套餐、订阅、模板、拍摄会话、媒体、AI 任务和 Provider 管理 |
| AI 工作流 | 单图分析、背景分析、批量选优、多角度扫描、结构化 JSON 归一化和失败任务记录 |
| 管理后台 | 登录、统计、用户、套餐、推荐模板、媒体、AI 任务和 Provider 配置 |
| 数据库 | PostgreSQL schema、外键与检查约束、JSONB 字段、更新时间触发器和旧库兼容补丁 |
| 测试 | Flutter 页面/格式化测试，后端和设备运行时 Python 测试，以及设备烟雾测试脚本 |

## 3. 已知限制

- AI Provider 的实际调用适配器目前只实现 `openai_compatible`；`anthropic_compatible` 和 `custom` 只可保存配置。
- 管理后台保留 `DevicesView.vue`，后端也有设备 CRUD，但 `/admin/devices` 当前重定向到工作台，侧栏入口未启用。
- 媒体默认存储在后端本地 `uploads/`；多实例或公网部署前应切换到对象存储并补生命周期管理。
- 手机端、业务后端和设备运行时需要在同一可达网络中正确配置两个服务地址；真机不能使用宿主机的 `127.0.0.1`。
- 树莓派性能档位、检测帧率、云台方向、死区、灵敏度和舵机 ID 必须按实际硬件标定。
- WebRTC 作为可选链路保留；稳定联调时仍需要结合网络环境验证，HTTP/WebSocket fallback 更适合排障。
- 仓库没有统一的 GitHub Actions 流程；真实硬件端到端测试不能完全由普通 CI 替代。

## 4. 安全与数据边界

- `BACKEND_AUTH_SECRET`、数据库密码和 AI Provider Key 不得写入源码或提交到仓库。
- 用户照片、视频、上传文件、缓存、日志、本地数据库和模型权重已通过 `.gitignore` 排除。
- Provider Key 由业务后端保存和调用，手机端与设备端不应持有生产密钥。
- 公网部署应增加 HTTPS、反向代理、上传大小限制、访问日志脱敏、备份和密钥轮换。

## 5. 验证建议

### 2026-07-10 本地验证结果

- 后端 3 个 Python 测试全部通过。
- 设备运行时 18 个测试中 17 个通过；`test_config_route_model_exists` 在当前最新 FastAPI 环境中因 `app.routes` 包含无 `path` 属性的 `_IncludedRouter` 而报错。依赖声明为 `fastapi>=0.115`，需要固定兼容版本或让测试只检查带 `path` 的路由对象。
- 后端与设备运行时通过 Python `compileall`。
- Vue 管理后台生产构建通过；Vite 提示主 JS chunk 约 1.1 MB，后续可做路由级拆包。
- 当前机器没有 Flutter SDK，因此本次未执行 `flutter analyze` 和 `flutter test`。

提交前的软件验证顺序：

1. 后端 Python 编译与单元测试。
2. 设备运行时 Python 编译与单元测试，先使用 `DEVICE_SERVO_DRIVER=mock`。
3. 管理后台 `npm run build`。
4. Flutter `flutter analyze` 与 `flutter test`。
5. 局域网内完成登录、拍摄上传、AI 分析、设备跟随和云台回中主流程。
6. 最后再接 TTL 舵机和真实模型 Provider 做硬件验收。

## 6. 下一步优先级

1. 修复设备路由测试对新版 FastAPI 的兼容性，并固定可复现的依赖版本。
2. 建立基础 CI，覆盖 Python 测试、Vue 构建和 Flutter 静态检查。
3. 增加可复现的一键本地启动配置，并补充数据库迁移版本管理。
4. 用固定场景建立跟随稳定性、构图偏差、端到端延迟和 AI 成功率指标。
5. 将上传媒体迁移到对象存储，补充删除、过期和隐私授权流程。
6. 根据产品需要启用设备管理入口，并实现其他 Provider 调用适配器。

## 7. 文档入口

- [根 README](../README.md)
- [项目说明](项目说明.md)
- [接口契约](接口契约.md)
- [数据字典](数据字典.md)
- [移动端说明](../mobile_client/README.md)
- [设备运行时说明](../device_runtime/README.md)
- [业务后端说明](../backend/README.md)
- [管理后台说明](../admin_web/README.md)
- [数据库说明](../database/README.md)
