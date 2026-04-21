# Camera Assistant System

Camera Assistant 是一个面向移动端拍摄辅助、设备联动和云端 AI 分析的多端项目，当前仓库包含：

- `backend`：FastAPI 业务后端
- `device_runtime`：本地设备运行时与控制 API
- `mobile_client`：Flutter 手机端
- `admin_web`：Vue 3 管理后台
- `docs`：项目文档、联调记录与部署说明

## 仓库公开版说明

本仓库已按公开发布要求做过内容筛选，以下内容不会提交：

- 本地虚拟环境、`node_modules`、Flutter/Android 构建产物
- 本地缓存、日志、IDE 配置
- 用户上传图片、抓拍样本、演示视频
- 本地模型权重与可重复下载的运行时资产
- 本机数据库口令、真实测试账号、私有密钥与本地环境文件

## 快速开始

请优先阅读：

- [docs/开发定稿.md](./docs/%E5%BC%80%E5%8F%91%E5%AE%9A%E7%A8%BF.md)
- [docs/项目当前状态说明.md](./docs/%E9%A1%B9%E7%9B%AE%E5%BD%93%E5%89%8D%E7%8A%B6%E6%80%81%E8%AF%B4%E6%98%8E.md)
- [docs/部署说明.md](./docs/%E9%83%A8%E7%BD%B2%E8%AF%B4%E6%98%8E.md)

## 本地依赖

- Python 3.12
- PostgreSQL
- Node.js 20+
- Flutter SDK

后端与设备端 Python 依赖请分别参考：

- `backend/requirements.txt`
- `device_runtime/requirements.txt`

前端与移动端依赖请分别参考：

- `admin_web/package.json`
- `mobile_client/pubspec.yaml`

## 安全提示

- 请使用自己的 `.env` 或环境变量，不要把真实口令和密钥提交回仓库
- 公开发布前，建议再次运行一轮敏感信息扫描和文件清单审查
