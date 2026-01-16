# 存储配额管理系统 (Quota Manager)

Linux 服务器多目录用户存储配额监控、警告与自动锁定系统。

## 功能特性

- ✅ **多目录支持**：支持监控多个基础目录（如 `/amax/data`, `/home` 等）下的用户配额
- ✅ **自动监控**：基于 systemd timer 的定时任务，每小时自动检查用户存储使用情况
- ✅ **实时警告**：后台守护进程实时向超限用户的终端发送警告
- ✅ **登录提示**：用户登录时自动显示配额超限警告（支持 SSH 和 VS Code 远程终端）
- ✅ **宽限期机制**：超限后提供 7 天宽限期，超期自动锁定目录
- ✅ **自动恢复**：用户清理数据后自动解除锁定
- ✅ **管理工具**：提供手动解锁脚本，管理员可快速处理特殊情况

## 系统要求

- **操作系统**：Linux（推荐 Ubuntu 20.04+、CentOS 7+）
- **权限**：需要 root 权限进行安装和配置
- **依赖工具**：`bash`, `systemd`, `du`, `awk`, `grep`

## 快速开始

### 1. 安装

```bash
# 进入项目目录
cd /opt/quota_manager

# 设置脚本可执行权限
sudo chmod +x /opt/quota_manager/*.sh
sudo chmod +x /opt/quota_manager/bin/*.sh

# 运行安装脚本
sudo ./install.sh
```

安装脚本会自动完成以下操作：

- 创建系统目录和日志文件
- 复制脚本到系统路径
- 安装并启用 systemd 服务和定时器
- 配置登录提示和 VS Code 终端支持
- 生成默认配置文件（如不存在）

### 2. 配置用户配额

编辑配置文件 `/etc/user_quota.conf`：

```bash
sudo nano /etc/user_quota.conf
```

**配置格式**：
```
username  directory  limit(GB)
```

**示例**：
```conf
# 用户 alice 在 /amax/data 下限额 100GB
alice /amax/data 100

# 同一用户在 /home 下限额 20GB
alice /home 20

# 用户 bob 在 /amax/data 下限额 500GB
bob /amax/data 500
```

**配置说明**：
- 每行定义一条配额规则
- 同一用户可针对不同目录设置不同配额
- 系统会监控 `directory/username` 目录的大小
- 配额单位为 GB（支持小数，如 `0.001` 用于测试）

### 3. 验证安装

```bash
# 检查定时器状态
sudo systemctl status quota_monitor.timer

# 检查通知服务状态
sudo systemctl status quota_notifier.service

# 查看日志
sudo journalctl -u quota_monitor.service -f
```

### 4. 手动触发检查（可选）

```bash
sudo /usr/local/bin/quota_monitor.sh
```

## 目录结构

```
/opt/quota_manager/          # 项目安装目录
├── bin/                     # 可执行脚本
│   ├── quota_monitor.sh     # 配额监控主程序
│   ├── quota_notifier.sh    # 实时通知守护进程
│   ├── quota_banner.sh      # 登录警告横幅
│   └── unlock_user.sh       # 手动解锁工具
├── etc/                     # 配置文件和服务定义
│   ├── user_quota.conf      # 用户配额配置模板
│   ├── quota_monitor.service # systemd 服务单元
│   ├── quota_monitor.timer   # systemd 定时器
│   └── quota_notifier.service # 通知守护进程服务
├── install.sh               # 安装脚本
└── uninstall.sh             # 卸载脚本

/etc/user_quota.conf         # 系统配置文件（安装后生成）
/var/lib/quota_system/       # 运行时状态目录
/var/log/quota.log           # 系统日志
/usr/local/bin/              # 系统集成的可执行脚本
/etc/profile.d/quota_banner.sh  # 登录提示脚本
```

## 核心组件说明

### quota_monitor.sh - 配额监控主程序

- **功能**：扫描所有用户配额，检测超限情况，管理锁定状态
- **运行频率**：每小时（由 systemd timer 控制）
- **状态管理**：
  - 首次超限：记录超限时间到状态文件
  - 超限 7 天：自动锁定目录（移除写权限）
  - 用量恢复正常：自动解锁并清理状态

**重要参数**：
- `LOCK_DAYS=7`：宽限期天数（可在脚本中修改）
- `CONFIG="/etc/user_quota.conf"`：配置文件路径
- `STATE_DIR="/var/lib/quota_system"`：状态文件存储目录

### quota_notifier.sh - 实时通知守护进程

- **功能**：向超限用户的活动终端发送实时警告
- **运行方式**：作为 systemd 服务常驻后台
- **警告间隔**：每 10 分钟（可通过 `WARN_INTERVAL` 修改）
- **检测范围**：自动发现所有 SSH、pts 终端

### quota_banner.sh - 登录横幅

- **功能**：在用户登录时显示配额超限警告
- **触发场景**：
  - SSH 登录
  - VS Code 远程终端启动
  - 新建 bash 会话
- **显示内容**：
  - 超限目录位置
  - 配额限制
  - 剩余宽限天数或锁定状态

### unlock_user.sh - 管理员解锁工具

- **功能**：手动解除用户目录锁定并重置配额状态
- **用法**：
  ```bash
  sudo /usr/local/bin/unlock_user.sh <username>
  ```
- **操作**：
  - 恢复目录所有权和写权限
  - 清除所有相关状态文件（`.state`, `.locked`, `.warn_time`）

## 使用场景

### 场景 1：用户首次超限

1. **系统检测**：`quota_monitor.sh` 发现用户目录超限
2. **状态记录**：创建状态文件 `/var/lib/quota_system/username_path.state`
3. **用户提示**：
   - 下次登录时显示红色警告横幅
   - 后台服务每 10 分钟向终端发送警告
4. **倒计时**：警告中显示剩余宽限天数

### 场景 2：宽限期内用户清理数据

1. **用户操作**：删除文件使用量降至限额以下
2. **自动解锁**：下次检查时自动恢复权限并清除状态
3. **日志记录**：记录恢复操作到 `/var/log/quota.log`

### 场景 3：超期自动锁定

1. **触发条件**：超限超过 7 天
2. **锁定操作**：
   - 目录所有权改为 `root:用户组`
   - 移除所有用户的写权限
   - 创建 `.locked` 标记文件
3. **用户体验**：
   - 无法创建或修改文件
   - 登录时显示"目录已锁定"错误提示

### 场景 4：管理员介入

```bash
# 管理员决定提前解锁用户
sudo unlock_user.sh alice

# 输出示例：
# 📂 Processing Directory: /amax/data/alice
#    Restoring permissions...
#    ✅ Permissions restored.
#    Clearing state files...
#    ✅ State reset.
# 🎉 User alice has been unlocked/reset.
```

## 配置调整

### 修改宽限期

编辑 `/usr/local/bin/quota_monitor.sh` 和 `/opt/quota_manager/bin/quota_banner.sh`：

```bash
LOCK_DAYS=7  # 改为所需天数（如 14）
```

### 修改检查频率

编辑 `/etc/systemd/system/quota_monitor.timer`：

```ini
# 每小时（默认）
OnCalendar=hourly

# 改为每 30 分钟
OnCalendar=*:0/30

# 改为每天凌晨 2 点
OnCalendar=*-*-* 02:00:00
```

应用更改：
```bash
sudo systemctl daemon-reload
sudo systemctl restart quota_monitor.timer
```

### 修改实时警告间隔

编辑 `/usr/local/bin/quota_notifier.sh`：

```bash
WARN_INTERVAL=600  # 改为所需秒数（如 300 = 5分钟）
```

重启服务：
```bash
sudo systemctl restart quota_notifier.service
```

## 日志与监控

### 查看系统日志

```bash
# 实时查看配额检查日志
sudo journalctl -u quota_monitor.service -f

# 查看最近 100 行
sudo journalctl -u quota_monitor.service -n 100

# 查看通知服务日志
sudo journalctl -u quota_notifier.service -f
```

### 检查用户状态

```bash
# 查看所有状态文件
ls -lh /var/lib/quota_system/

# 查看特定用户状态
cat /var/lib/quota_system/alice_amax_data.state
```

**状态文件格式**：
```
over_quota_since=1705123456
QUOTA_USER="alice"
QUOTA_BASE="/amax/data"
QUOTA_LIMIT="100"
```

### 手动检查用户使用量

```bash
# 查看用户目录大小
du -sh /amax/data/alice

# 查看详细使用情况
du -h --max-depth=1 /amax/data/alice
```

## 卸载

```bash
cd /opt/quota_manager
sudo ./uninstall.sh
```

卸载脚本会：
- 停止并移除所有 systemd 服务和定时器
- 删除 `/usr/local/bin/` 下的脚本
- 移除登录提示和 VS Code 配置
- **保留**以下数据（需手动删除）：
  - `/etc/user_quota.conf`
  - `/var/lib/quota_system/`
  - `/var/log/quota.log`

完全清除（可选）：
```bash
sudo rm -f /etc/user_quota.conf
sudo rm -rf /var/lib/quota_system
sudo rm -f /var/log/quota.log
```

## 故障排除

### 警告未显示

1. 检查状态文件是否存在：
   ```bash
   ls /var/lib/quota_system/
   ```

2. 手动触发检查：
   ```bash
   sudo /usr/local/bin/quota_monitor.sh
   ```

3. 测试登录横幅：
   ```bash
   bash /opt/quota_manager/bin/quota_banner.sh
   ```

### VS Code 终端不显示警告

检查 `/etc/bash.bashrc` 或 `/etc/bashrc` 是否包含：
```bash
grep -A5 "BEGIN QUOTA MANAGER" /etc/bash.bashrc
```

如未找到，重新运行安装脚本。

### 定时任务未执行

```bash
# 检查 timer 状态
sudo systemctl status quota_monitor.timer

# 查看下次执行时间
sudo systemctl list-timers quota_monitor.timer

# 手动启动
sudo systemctl start quota_monitor.service
```

### 权限问题

所有核心脚本必须以 root 权限运行：
```bash
# 检查脚本权限
ls -l /usr/local/bin/quota_*.sh

# 应显示：
# -rwxr-xr-x 1 root root ... quota_monitor.sh
```

## 安全说明

- **权限管理**：仅 root 可修改配额配置和执行锁定操作
- **状态隔离**：每个用户的状态文件独立存储，避免互相影响
- **日志审计**：所有关键操作记录到 `/var/log/quota.log`
- **路径安全**：所有路径处理已转义，防止注入攻击

## 技术细节

### 多目录支持机制

- **状态文件命名**：`username_escaped_path.state`
  - 示例：`alice_amax_data.state`（对应 `/amax/data/alice`）
  - 示例：`alice_home.state`（对应 `/home/alice`）

- **配额计算**：使用 `du -s --block-size=1K` 获取精确使用量

- **锁定机制**：修改目录所有权和权限而非使用 `chattr`，兼容性更好

### systemd 集成

- **quota_monitor.timer**：定时触发配额检查
  - `OnCalendar=hourly`：每小时执行
  - `Persistent=true`：错过时间后会立即执行
  - `OnBootSec=2min`：启动后 2 分钟首次运行

- **quota_notifier.service**：常驻后台服务
  - `Restart=always`：崩溃后自动重启
  - `RestartSec=10`：重启等待 10 秒

## 开发与贡献

### 测试模式

**快速测试（每分钟检查一次）**：

编辑 `/etc/systemd/system/quota_monitor.timer`：
```ini
OnCalendar=*:0/1  # 取消注释此行
# OnCalendar=hourly  # 注释此行
```

编辑 `/usr/local/bin/quota_monitor.sh`：
```bash
LOCK_DAYS=0  # 立即锁定（无宽限期）
```

编辑 `/usr/local/bin/quota_notifier.sh`：
```bash
WARN_INTERVAL=5  # 每 5 秒警告一次
```

应用更改：
```bash
sudo systemctl daemon-reload
sudo systemctl restart quota_monitor.timer
sudo systemctl restart quota_notifier.service
```

### 日志调试

启用详细日志：
```bash
# 编辑脚本，在开头添加：
set -x  # 启用命令跟踪
```

## 版本历史

- **v2.0**（当前）：
  - 支持多目录配额监控
  - 改进状态文件命名机制
  - 添加 VS Code 终端支持
  - 优化实时通知逻辑

- **v1.0**：
  - 初始版本，仅支持单一目录 `/amax/data`

## 许可证

MIT License

## 联系方式

如有问题或建议，请联系系统管理员。
