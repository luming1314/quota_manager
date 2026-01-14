#!/bin/bash
# 一键安装脚本
# 路径: /opt/quota_manager/install.sh

set -e

BASE_DIR="/opt/quota_manager"
BIN_DIR="$BASE_DIR/bin"
ETC_DIR="$BASE_DIR/etc"

echo "🔧 正在安装配额管理系统（snake_case 版）..."

# 1. 创建状态目录
sudo mkdir -p /var/lib/quota_system
sudo chmod 755 /var/lib/quota_system
sudo chown root:root /var/lib/quota_system

# 2. 初始化日志
sudo touch /var/log/quota.log
sudo chmod 644 /var/log/quota.log

# 3. 安装主监控脚本
sudo cp "$BIN_DIR/quota_monitor.sh" /usr/local/bin/
sudo chmod +x /usr/local/bin/quota_monitor.sh
sudo cp "$BIN_DIR/unlock_user.sh" /usr/local/bin/
sudo chmod +x /usr/local/bin/unlock_user.sh

# 4. 安装登录提示（符号链接便于更新）
sudo ln -sf "$BASE_DIR/bin/quota_banner.sh" /etc/profile.d/quota_banner.sh
sudo chmod +x /etc/profile.d/quota_banner.sh

# 5. 安装配置文件（仅当不存在时）
if [ ! -f /etc/user_quota.conf ]; then
    sudo cp "$ETC_DIR/user_quota.conf" /etc/user_quota.conf
    sudo chmod 644 /etc/user_quota.conf
    echo "✅ 配置文件已创建：/etc/user_quota.conf，请按需编辑"
else
    sudo chmod 644 /etc/user_quota.conf
    echo "ℹ️ 配置文件 /etc/user_quota.conf 已存在，跳过创建"
fi

# 6. 创建 cron wrapper
WRAPPER="$BASE_DIR/bin/quota_monitor_wrapper.sh"
cat > /tmp/quota_monitor_wrapper.sh << EOF
#!/bin/bash
cd "$BASE_DIR" || exit 1
exec ./bin/quota_monitor.sh
EOF
sudo mv /tmp/quota_monitor_wrapper.sh "$WRAPPER"
sudo chmod +x "$WRAPPER"

# 7. 设置定时任务
# 正常模式（每小时）：
CRON_JOB="0 * * * * $WRAPPER >> /var/log/quota.log 2>&1"
# 测试模式（每分钟）：
# CRON_JOB="* * * * * $WRAPPER >> /var/log/quota.log 2>&1"
(sudo crontab -l 2>/dev/null | grep -v quota_monitor) | sudo crontab -
echo "$CRON_JOB" | sudo crontab -

echo ""
echo "✅ 安装成功！"
echo "📁 项目路径: $BASE_DIR"
echo "⚙️ 配置文件: /etc/user_quota.conf"
echo "📊 状态目录: /var/lib/quota_system/"
echo "📝 日志: /var/log/quota.log"
echo "🔁 请编辑 /etc/user_quota.conf 添加用户，然后等待下次 cron 执行（或手动运行 quota_monitor.sh）"

# 8. 配置非登录 Shell 支持 (VS Code Support)
BASH_CONFIG="/etc/bash.bashrc"
if [ ! -f "$BASH_CONFIG" ]; then
    BASH_CONFIG="/etc/bashrc" # RHEL/CentOS
fi

if [ -f "$BASH_CONFIG" ]; then
    if ! grep -q "BEGIN QUOTA MANAGER" "$BASH_CONFIG"; then
        echo ""
        echo "🔧 正在配置 VS Code 终端支持 ($BASH_CONFIG)..."
        cat << 'EOF' | sudo tee -a "$BASH_CONFIG" > /dev/null

# --- BEGIN QUOTA MANAGER ---
# 确保非登录 Shell (如 VS Code 终端) 也能显示配额警告
if [ -f /etc/profile.d/quota_banner.sh ]; then
    source /etc/profile.d/quota_banner.sh
fi
# --- END QUOTA MANAGER ---
EOF
        echo "✅ VS Code 终端支持已启用"
    else
        echo "ℹ️ VS Code 终端支持已存在，跳过配置"
    fi
else
    echo "⚠️ 未找到全局 bash 配置文件，VS Code 终端可能无法自动显示警告"
fi