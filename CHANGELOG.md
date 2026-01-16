# 更新日志 (Changelog)

## [2.0.0] - 2026-01-16

### 新增功能
- ✨ **多目录配额支持**：支持监控多个基础目录（如 `/amax/data`, `/home` 等）
- ✨ **改进的解锁工具**：`unlock_user.sh` 现在从配置文件读取并无条件恢复权限
- ✨ **VS Code 终端支持**：自动在非登录 Shell 中显示配额警告
- ✨ **实时通知守护进程**：`quota_notifier.service` 持续向活动终端发送警告

### 改进
- 🔧 状态文件命名机制：使用 `username_path.state` 格式支持多目录
- 🔧 配置文件格式：新增三列格式 `username directory limit`
- 🔧 更详细的日志输出和错误提示
- 🔧 兼容旧配置格式（`username=limit`）

### 修复
- 🐛 修复登录横幅重复显示问题
- 🐛 修复 Windows 换行符导致的路径问题
- 🐛 修复条件表达式错误

### 技术改进
- 📦 使用 systemd timer 替代 cron
- 📦 添加 `quota_notifier.service` 后台服务
- 📦 改进脚本错误处理（`set -euo pipefail`）

---

## [1.0.0] - 初始版本

### 功能
- 📊 基础配额监控（仅支持 `/amax/data`）
- ⏰ 定时检查（cron）
- 🔒 宽限期后自动锁定
- 📢 登录时显示警告
