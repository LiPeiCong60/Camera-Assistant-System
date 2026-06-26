# admin_web

`admin_web` 是运营管理后台，基于 Vue 3 + Vite + Element Plus + Pinia。它只访问业务后端 `backend`，不直接连接 `device_runtime`。

## 职责

- 管理员登录和登录态保存。
- 概览统计。
- 用户管理。
- 套餐管理、额度配置和 AI Provider 绑定。
- 推荐模板管理和图片上传。
- 媒体记录查看和删除。
- AI 任务查看、删除和错误排查。
- 多 AI Provider 配置管理。

后端仍保留设备登记 CRUD 接口和 `DevicesView.vue` 代码，但当前前端路由 `/admin/devices` 会重定向到工作台，侧栏不展示设备管理入口。

## 技术组成

| 技术 | 使用位置 | 作用 |
| --- | --- | --- |
| Vue 3 | `src/views`, `src/components` | 页面和组件 |
| Vite | `npm run dev/build` | 开发服务器和生产构建 |
| Element Plus | 管理后台 UI | 表格、表单、弹窗、分页、按钮 |
| Pinia | `src/stores` | 管理端 token、用户和 API 地址 |
| Vue Router | `src/router` | 路由和登录拦截 |
| Axios | `src/api` | 调用 `/api/admin/*` |

## 页面

| 路由 | 页面 | 说明 |
| --- | --- | --- |
| `/login` | `LoginView.vue` | 管理员登录 |
| `/admin/overview` | `WorkbenchView.vue` | 总览统计 |
| `/admin/users` | `UsersView.vue` | 用户管理 |
| `/admin/plans` | `PlansView.vue` | 套餐管理 |
| `/admin/templates` | `RecommendedTemplatesView.vue` | 推荐模板 |
| `/admin/devices` | 重定向到工作台 | 设备登记前端入口当前未启用 |
| `/admin/captures` | `CapturesView.vue` | 媒体记录 |
| `/admin/ai-tasks` | `AiTasksView.vue` | AI 任务 |
| `/admin/ai-provider` | `AiProviderConfigsView.vue` | AI Provider 配置 |

## AI Provider 管理

后台维护的 Provider 会写入 `ai_provider_configs`。手机端创建 AI 任务时，后端按套餐和 Provider 状态选择可用配置。

当前后端实际调用只实现 `openai_compatible`，后台表单中的 `anthropic_compatible`、`custom` 可保存配置但还需要后续补调用适配器。

不要把真实 API Key 写入前端代码。Key 只通过后台表单提交到后端，由后端调用 Provider。

## 推荐模板

推荐模板页支持上传图片，后端会保存到 `/uploads/templates/...` 并自动生成 `template_data`。当前模板 JSON 主字段为 `bbox_norm`、`head_bbox_norm`、`pose_points_image`、`pose_points_bbox` 和肩部/面部锚点。

## 启动

```powershell
cd admin_web
npm install
$env:VITE_API_BASE_URL="http://127.0.0.1:8000/api"
npm run dev
```

默认访问：

```text
http://127.0.0.1:5173
```

生产构建：

```powershell
npm run build
```

## 检查

```powershell
npm run build
```

如果出现 chunk 体积警告，通常是 Element Plus 和管理后台页面集中打包导致，不影响本地演示；正式部署可再做路由级动态导入。
