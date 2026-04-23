# Camera Assistant

Camera Assistant 是一个面向移动端拍摄辅助、设备联动和 AI 图片分析的多端项目。当前仓库已经形成四端协作结构：业务后端负责账号、套餐、模板、抓拍记录和 AI 任务；移动端负责拍摄、模板引导和设备联动操作；设备运行时负责本地视频流、人体检测、云台控制和模板构图；管理后台负责运营配置和数据回看。

## 当前模块

| 模块 | 技术栈 | 作用 |
| --- | --- | --- |
| `backend` | FastAPI, SQLAlchemy, PostgreSQL | 业务 API、鉴权、上传文件、AI Provider 调用、数据落库 |
| `mobile_client` | Flutter | 登录、拍摄、模板管理、历史记录、设备联动 |
| `device_runtime` | FastAPI, OpenCV, MediaPipe, TTL 总线舵机 | 树莓派本地控制 API、检测跟踪、云台控制、预览和抓拍 |
| `admin_web` | Vue 3, Vite, Element Plus, Pinia | 用户、套餐、设备、推荐模板、AI 配置、抓拍和任务管理 |
| `database` | PostgreSQL SQL | 核心表结构和索引 |

## 推荐阅读顺序

1. [项目总览与架构说明](./docs/%E9%A1%B9%E7%9B%AE%E6%80%BB%E8%A7%88%E4%B8%8E%E6%9E%B6%E6%9E%84%E8%AF%B4%E6%98%8E.md)
2. [接口契约](./docs/%E6%8E%A5%E5%8F%A3%E5%A5%91%E7%BA%A6.md)
3. [部署说明](./docs/%E9%83%A8%E7%BD%B2%E8%AF%B4%E6%98%8E.md)
4. [AI 照片分析链路说明](./docs/AI%E7%85%A7%E7%89%87%E5%88%86%E6%9E%90%E9%93%BE%E8%B7%AF%E8%AF%B4%E6%98%8E.md)
5. [演示流程](./docs/%E6%BC%94%E7%A4%BA%E6%B5%81%E7%A8%8B.md)

## 快速启动

### 1. backend

```powershell
cd backend
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
$env:DATABASE_URL="postgresql+psycopg://postgres:postgres@127.0.0.1:5432/camera_assistant"
python init_db.py
uvicorn backend.app.main:app --reload --host 0.0.0.0 --port 8000
```

### 2. device_runtime

```powershell
cd device_runtime
pip install -r requirements.txt
$env:DEVICE_SERVO_DRIVER="mock"
uvicorn device_runtime.api.app:app --reload --host 0.0.0.0 --port 8001
```

注意：`device_runtime/main.py` 目前是占位入口，实际本地控制 API 从 `device_runtime.api.app:app` 启动。

### 3. admin_web

```powershell
cd admin_web
npm install
$env:VITE_API_BASE_URL="http://127.0.0.1:8000/api"
npm run dev
```

默认访问 `http://127.0.0.1:5173`。

### 4. mobile_client

```powershell
cd mobile_client
flutter pub get
flutter run `
  --dart-define=API_BASE_URL=http://127.0.0.1:8000/api `
  --dart-define=DEVICE_API_BASE_URL=http://127.0.0.1:8001
```

Android 模拟器访问宿主机时通常需要把 `127.0.0.1` 改为 `10.0.2.2`。真机联调时改为电脑的局域网 IP。

## 公开仓库说明

以下内容不应提交到仓库：

- `.venv`、`node_modules`、Flutter/Android 构建产物
- 本地缓存、日志、IDE 配置
- 用户上传图片、抓拍样本、演示视频
- 本地模型权重、MediaPipe 缓存和可重新下载的运行时资产
- 真实数据库口令、测试账号、私有密钥和本地 `.env`

## 当前限制

- 设备端第一版是单会话本地运行时，打开新会话会关闭旧会话。
- AI 任务当前在后端请求内同步调用 Provider，尚未接入独立队列。
- 设备抓拍文件保存在设备本地，移动端业务抓拍则上传到 backend 静态目录；二者还没有完全统一回流。
- 树莓派真实硬件需要根据舵机方向、串口和角度范围做现场校准。
