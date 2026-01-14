# 课题组服务器磁盘监控管理系统 (Quota Manager)

本系统用于自动监控服务器用户的磁盘用量，并在用户超额使用时执行"软限制"和"硬锁定"策略。

## 📖 项目简介

系统旨在解决公共服务器磁盘空间被滥用的问题。通过定时任务（默认每小时）扫描用户目录，执行以下策略：
1.  **软限制 (Soft Quota)**: 当用户磁盘用量超过设定限额时，记录超限起始时间，并写入日志。系统会自动向在线用户终端广播警告信息。
2.  **宽限期 (Grace Period)**: 用户在首次超限后有 **7天** 的宽限期进行清理。
3.  **硬锁定 (Hard Lock)**: 如果连续超限超过7天，系统将锁定用户目录（移除写权限，修改所有者），直到管理员介入或用户清理后自动恢复。

## 📂 目录结构

```text
quota_manager/
├── bin/
│   ├── quota_monitor.sh         # [核心] 监控主程序，执行检查、锁定及通知逻辑
│   ├── quota_banner.sh          # 登录提示脚本，显示当前配额状态及彩显警告
│   └── unlock_user.sh           # 管理员手动解锁用户的辅助脚本
├── etc/
│   └── user_quota.conf          # 配置文件模板
├── install.sh                   # 一键安装脚本
├── uninstall.sh                 # 卸载脚本
└── README.md                    # 本说明文件
```

## ⚠️ 关键配置说明

以下路径在脚本中存在硬编码引用。其中 **软件安装路径** 建议保持默认，而 **用户数据根目录** 通常需要根据服务器实际情况进行修改。

如需修改，请务必仔细同步更新以下涉及的脚本：

*   **软件安装路径 (`BASE_DIR`)**
    *   **默认值**: `/opt/quota_manager`
    *   **涉及脚本**: `install.sh`
    *   **说明**: 安装脚本默认将程序安装在此位置。如果修改此路径，需同步更新 `install.sh` 中定义的 `BASE_DIR` 变量。

*   **用户数据根目录 (`USER_QUOTA_BASE`)**
    *   **默认值**: `/amax/data`
    *   **涉及脚本**: `bin/quota_banner.sh`, `bin/quota_monitor.sh`, `bin/unlock_user.sh`
    *   **说明**: 系统仅监控此目录下的子文件夹大小。如果您的用户数据存储在其他挂载点（如 `/home`），请务必修改以上三个脚本中的 `USER_QUOTA_BASE` 变量。

## 🚀 安装说明

1.  **赋予脚本执行权限**:
    ```bash
    sudo chmod +x /opt/quota_manager/*.sh
    sudo chmod +x /opt/quota_manager/bin/*.sh
    ```

2.  **运行安装脚本**:
    ```bash
    sudo ./install.sh
    ```
    脚本会自动：
    *   创建必要的系统目录 (`/var/lib/quota_system`, `/var/log/quota.log`)。
    *   将核心脚本 (`quota_monitor.sh`, `unlock_user.sh`) 复制到 `/usr/local/bin`。
    *   设置 `/etc/profile.d/` 登录提示，并配置 VS Code 终端支持。
    *   配置 Crontab 定时任务（每小时执行一次）。

3.  **配置用户限额**:
    安装完成后，编辑配置文件 `/etc/user_quota.conf`：
    ```bash
    sudo vim /etc/user_quota.conf
    ```

## ⚙️ 配置格式

配置文件 `/etc/user_quota.conf` 使用 `用户名=限额(GB)` 的格式。

```ini
# 格式: username=限额(GB)
# 注意: 用户名必须是系统中存在的用户

alice=10
bob=20

# 注释掉的行将被忽略
# test_user=50
```

## 🛠 工作原理与运维

### 监控逻辑
- **正常状态**: 目录权限正常，用户可读写。
- **首次超限**: 系统记录当前时间戳到 `/var/lib/quota_system/<user>.state`。
- **持续超限**: 
    - 每次检查都会确认是否仍超限。
    - **在线通知**: 如果用户在线，每隔1小时会向其所有终端发送全屏警告（支持 VS Code 终端）。
- **恢复正常**: 一旦用量低于限额，系统自动删除 `.state` 文件，如果目录曾被锁定，会自动解锁（恢复写权限，归还所有者）。
- **锁定触发**: 若 `(当前时间 - 首次超限时间) > 7天`，系统将：
    1.  执行 `chmod a-w` (移除全员写权限)。
    2.  执行 `chown root:gid` (改变所有者防止用户修改权限)。
    3.  创建 `.locked` 标记文件。

### 日志查看
所有操作日志记录在 `/var/log/quota.log`：
```bash
tail -f /var/log/quota.log
```

### 手动触发检查
安装后，cron 任务实际上调用的是 `/opt/quota_manager/bin/quota_monitor_wrapper.sh`。
如果想立即手动执行检查，可以直接运行：
```bash
sudo quota_monitor.sh
```
或者运行安装目录下的 wrapper：
```bash
sudo /opt/quota_manager/bin/quota_monitor_wrapper.sh
```

### 解锁用户
通常用户清理文件后，下次 Cron 任务执行时会自动解锁。
如果需要紧急解锁或重置宽限期，请使用提供的辅助脚本：

```bash
sudo unlock_user.sh <username>
```
此命令会：
1. 立即恢复目录权限和所有者。
2. 清除锁定的状态文件（重置7天倒计时）。

### 卸载系统
如果需要移除本系统：
```bash
sudo ./uninstall.sh
```
