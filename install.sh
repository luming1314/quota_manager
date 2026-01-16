#!/bin/bash
# 一键安装脚本
# 路径: /opt/quota_manager/install.sh

set -e

BASE_DIR="/opt/quota_manager"
# 处理 Windows 换行符带来的路径问题
BASE_DIR=$(echo "$BASE_DIR" | tr -d '\r')
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
sudo cp "$BIN_DIR/quota_notifier.sh" /usr/local/bin/
sudo chmod +x /usr/local/bin/quota_notifier.sh

# 3.1 安装系统服务
sudo cp "$ETC_DIR/quota_notifier.service" /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable quota_notifier.service
sudo systemctl restart quota_notifier.service

# 4. 安装登录提示（符号链接便于更新）
sudo ln -sf "$BASE_DIR/bin/quota_banner.sh" /etc/profile.d/quota_banner.sh
sudo chmod +x /etc/profile.d/quota_banner.sh

# 5. 安装配置文件（仅当不存在时）
if [ ! -f /etc/user_quota.conf ]; then
    sudo cp "$ETC_DIR/user_quota.conf" /etc/user_quota.conf
    sudo chmod 644 /etc/user_quota.conf
    echo "✅ 配置文件已创建：/etc/user_quota.conf，请按需编辑"
else
    # 检查内容是否一致
    if ! cmp -s "$ETC_DIR/user_quota.conf" /etc/user_quota.conf; then
        echo "⚠️  注意：检测到您的源配置文件与系统 /etc/user_quota.conf 不一致！"
        echo "   install.sh 默认不会覆盖现有的配置文件。"
        echo "   👉 如果需要应用新的配额规则，请手动执行："
        echo "   sudo cp \"$ETC_DIR/user_quota.conf\" /etc/user_quota.conf"
    else
        echo "ℹ️ 配置文件 /etc/user_quota.conf 已存在且内容一致"
    fi
     sudo chmod 644 /etc/user_quota.conf
fi

# 6. 安装 systemd timer（替代 cron）
echo "⏳ 安装 Systemd Timer 定时任务..."
sudo cp "$ETC_DIR/quota_monitor.service" /etc/systemd/system/
sudo cp "$ETC_DIR/quota_monitor.timer" /etc/systemd/system/
sudo chmod 644 /etc/systemd/system/quota_monitor.service
sudo chmod 644 /etc/systemd/system/quota_monitor.timer

# 重新加载 systemd 并启用 timer
sudo systemctl daemon-reload
sudo systemctl enable quota_monitor.timer
sudo systemctl restart quota_monitor.timer

echo "✅ Systemd Timer 已安装并启动"
echo "   查看状态: sudo systemctl status quota_monitor.timer"
echo "   查看日志: sudo journalctl -u quota_monitor.service -f"

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