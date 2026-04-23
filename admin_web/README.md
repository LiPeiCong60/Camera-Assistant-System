# admin_web

Camera Assistant 管理后台，基于 Vue 3 + Vite + Element Plus + Pinia。

## 职责

- 管理员登录。
- 概览统计。
- 用户管理和套餐绑定。
- 套餐管理，包含额度和 AI Provider 绑定。
- 推荐默认模板管理。
- 设备列表管理。
- 抓拍记录和 AI 任务回看。
- 多 AI Provider 配置管理。

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

## 目录

| 目录 | 说明 |
| --- | --- |
| `src/views` | 页面视图。 |
| `src/components` | 侧栏、顶部栏等通用组件。 |
| `src/api` | Axios 实例和管理端接口封装。 |
| `src/stores` | Pinia 状态，保存 token、当前用户和 API 地址。 |
| `src/router` | 前端路由和登录拦截。 |
| `src/styles` | 全局样式。 |

## 页面路由

- `/login`
- `/admin/overview`
- `/admin/users`
- `/admin/plans`
- `/admin/templates`
- `/admin/devices`
- `/admin/captures`
- `/admin/ai-tasks`
- `/admin/ai-provider`

## 套餐与 AI 配置

套餐通过 `feature_flags` 影响后端 AI Provider 选择：

- `default_ai_provider_code`：套餐默认 Provider。
- `available_ai_provider_codes`：可用 Provider 列表。

后端会优先使用套餐默认配置，其次使用可用列表中的第一个配置，最后退回系统默认配置。
