#!/bin/bash
# 登录时显示配额警告
# 路径: /opt/quota_manager/bin/quota_banner.sh

USER_QUOTA_BASE="/amax/data"
STATE_DIR="/var/lib/quota_system"
LOCK_DAYS=7 # 宽限期（天）。测试模式设为0（立即锁定），生产环境建议设为7。 # 测试时改为0 正常运行为7天

# 防止重复显示
if [[ -n "$QUOTA_BANNER_SHOWN" ]]; then
    return
fi
export QUOTA_BANNER_SHOWN=1

if [[ -f "$STATE_DIR/$USER.state" ]]; then
    source "$STATE_DIR/$USER.state" 2>/dev/null
    if [[ -n "${over_quota_since:-}" ]]; then
        # 1. 获取用户配额
        limit_gb=$(grep "^$USER=" /etc/user_quota.conf | cut -d'=' -f2)
        if [[ -z "$limit_gb" ]]; then limit_gb="Unknown"; fi

        # 2. 计算时间
        now=$(date +%s)
        days_over=$(( (now - over_quota_since) / 86400 ))
        days_left=$(( LOCK_DAYS - days_over ))
        
        lock_time=$(( over_quota_since + LOCK_DAYS * 86400 ))
        lock_date=$(date -d "@$lock_time" "+%Y-%m-%d %H:%M")

        # 3. 显示彩显警告
        echo ""
        if [[ $days_left -gt 0 ]]; then
            echo -e "\033[41;37m                                             \033[0m"
            echo -e "\033[41;37m   ⚠️  严重警告：存储配额已超限！           \033[0m"
            echo -e "\033[41;37m                                             \033[0m"
            echo -e "\033[1;31m"
            echo "   当前用户: $USER"
            echo "   配额限制: ${limit_gb}GB"
            echo "   您的目录: $USER_QUOTA_BASE/$USER"
            echo ""
            echo "   您的目录将于 【$lock_date】 ($days_left 天后) 被锁定，届时将无法写入！"
            echo "   请立即清理文件，以免影响使用。"
            echo -e "\033[0m"
        else
            echo -e "\033[41;37m                                             \033[0m"
            echo -e "\033[41;37m   🔴  严重错误：目录已被锁定！             \033[0m"
            echo -e "\033[41;37m                                             \033[0m"
            echo -e "\033[1;31m"
            echo "   由于超限超过 $LOCK_DAYS 天，您的目录已被禁止写入。"
            echo "   锁定目录: $USER_QUOTA_BASE/$USER"
            echo "   锁定时间: $lock_date"
            echo ""
            echo "   请立即联系管理员解除锁定！"
            echo -e "\033[0m"
        fi
    fi
fi