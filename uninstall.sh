#!/bin/bash
# 一键卸载脚本
# 路径: /opt/quota_manager/uninstall.sh

set -e

echo "🗑️  正在卸载配额管理系统..."

# 移除 cron 任务
echo "⏳ 正在移除定时任务..."
(sudo crontab -l 2>/dev/null | grep -v quota_monitor) | sudo crontab -
echo "✅ 定时任务已移除"

# 停止并移除服务
echo "🛑 正在停止后台服务..."
if systemctl list-unit-files | grep -q quota_notifier.service; then
    sudo systemctl stop quota_notifier.service || true
    sudo systemctl disable quota_notifier.service || true
    sudo rm -f /etc/systemd/system/quota_notifier.service
    sudo systemctl daemon-reload
    echo "✅ 服务已停止并移除"
else
    echo "ℹ️ 服务未安装，跳过"
fi

# 移除系统集成文件
echo "🧹 正在移除系统文件..."
# 主程序
if [ -f /usr/local/bin/quota_notifier.sh ]; then
    sudo rm -f /usr/local/bin/quota_notifier.sh
    echo "   - 已删除: /usr/local/bin/quota_notifier.sh"
fi

if [ -f /usr/local/bin/quota_monitor.sh ]; then
    sudo rm -f /usr/local/bin/quota_monitor.sh
    echo "   - 已删除: /usr/local/bin/quota_monitor.sh"
else
    echo "   - 未找到: /usr/local/bin/quota_monitor.sh (跳过)"
fi

# 解锁工具
if [ -f /usr/local/bin/unlock_user.sh ]; then
    sudo rm -f /usr/local/bin/unlock_user.sh
    echo "   - 已删除: /usr/local/bin/unlock_user.sh"
else
    echo "   - 未找到: /usr/local/bin/unlock_user.sh (跳过)"
fi

# 登录提示 banner
if [ -f /etc/profile.d/quota_banner.sh ]; then
    sudo rm -f /etc/profile.d/quota_banner.sh
    echo "   - 已删除: /etc/profile.d/quota_banner.sh"
else
    echo "   - 未找到: /etc/profile.d/quota_banner.sh (跳过)"
fi

# Wrapper 脚本 (安装时生成的)
WRAPPER="/opt/quota_manager/bin/quota_monitor_wrapper.sh"
if [ -f "$WRAPPER" ]; then
    sudo rm -f "$WRAPPER"
    echo "   - 已删除: $WRAPPER"
else
    echo "   - 未找到: $WRAPPER (跳过)"
fi

echo "✅ 系统集成文件已清理"

echo ""
echo "⚠️  注意：以下数据保留（如需彻底清除请手动删除）："
echo "   - 状态目录: /var/lib/quota_system/"
echo "   - 配置文件: /etc/user_quota.conf"
echo "   - 日志文件: /var/log/quota.log"
echo ""
echo "✅ 卸载完成（系统集成部分已移除）"

# 移除 VS Code 终端支持配置
BASH_CONFIG="/etc/bash.bashrc"
if [ ! -f "$BASH_CONFIG" ]; then
    BASH_CONFIG="/etc/bashrc"
fi

if [ -f "$BASH_CONFIG" ]; then
    if grep -q "BEGIN QUOTA MANAGER" "$BASH_CONFIG"; then
        echo "🧹 正在移除 VS Code 终端支持配置..."
        # 使用 sed 删除 begin 和 end 之间的内容
        sudo sed -i '/# --- BEGIN QUOTA MANAGER ---/,/# --- END QUOTA MANAGER ---/d' "$BASH_CONFIG"
        echo "✅ 配置已清除"
    fi
fi