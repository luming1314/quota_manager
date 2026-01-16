#!/bin/bash
# 登录时显示配额警告
# 路径: /opt/quota_manager/bin/quota_banner.sh

# 使用非导出的变量防止在同一 Shell 实例中重复加载
if [[ -z "${_QUOTA_BANNER_HAS_RUN_IN_THIS_SHELL:-}" ]]; then
    _QUOTA_BANNER_HAS_RUN_IN_THIS_SHELL="true"
    STATE_DIR="/var/lib/quota_system"
    LOCK_DAYS=7 # 宽限期（天）

    # 启用 nullglob 以正确处理无匹配文件的情况
    shopt -s nullglob

    # 遍历当前用户的所有状态文件 (兼容旧命名和新命名)
    # 模式: user.state (旧) 或 user_目录.state (新, 以_开头)
    for state_file in "$STATE_DIR/${USER}.state" "$STATE_DIR/${USER}_"*.state; do
        [[ -f "$state_file" ]] || continue

        # 初始化/重置变量
        over_quota_since=""
        QUOTA_BASE=""
        QUOTA_LIMIT=""
        QUOTA_USER=""

        # 读取状态文件
        source "$state_file" 2>/dev/null

        # 安全检查: 确保是当前用户的记录 (防止如 username=rob 匹配到 robert)
        # 如果文件里没有 QUOTA_USER (旧文件)，则假设匹配成功
        if [[ -n "$QUOTA_USER" && "$QUOTA_USER" != "$USER" ]]; then continue; fi

        # 检查是否超限
        if [[ -n "${over_quota_since:-}" ]]; then
            
            # 补全信息 (兼容旧文件)
            if [[ -z "$QUOTA_BASE" ]]; then QUOTA_BASE="/amax/data"; fi
            if [[ -z "$QUOTA_LIMIT" ]]; then 
                # 尝试从配置文件读取 (兼容新旧格式)
                # 查找匹配 USER 和 QUOTA_BASE 的行
                # 如果是旧格式 (user=limit)，grep 仍然有效
                # 如果是新格式 (user dir limit)
                
                QUOTA_LIMIT="Unknown"
                
                # 1. 尝试匹配 "user dir limit"
                # safe_base needs escapement if it contains regex chars, but for paths usually ok.
                # using awk for safer field matching
                # Match user (field 1) and exact base dir (field 2)
                
                # Check for explicit entry: username /path/to/dir limit
                found_limit=$(awk -v u="$USER" -v d="$QUOTA_BASE" '$1==u && $2==d {print $3}' /etc/user_quota.conf)
                
                if [[ -n "$found_limit" ]]; then
                    QUOTA_LIMIT="$found_limit"
                else
                    # 2. Check for default entry (old format or implied base): username limit
                    # Old format: username=limit -> awk sees "username=limit" as $1
                    old_limit=$(grep "^$USER=" /etc/user_quota.conf 2>/dev/null | cut -d'=' -f2)
                    if [[ -n "$old_limit" ]]; then
                         # Only use this if QUOTA_BASE matches the default
                         if [[ "$QUOTA_BASE" == "/amax/data" ]]; then
                             QUOTA_LIMIT="$old_limit"
                         fi
                    fi
                    
                    # 3. Check for "username limit" (2 columns), assuming default path
                     if [[ "$QUOTA_LIMIT" == "Unknown" && "$QUOTA_BASE" == "/amax/data" ]]; then
                        limit_2col=$(awk -v u="$USER" '$1==u && NF==2 {print $2}' /etc/user_quota.conf)
                        if [[ -n "$limit_2col" ]]; then
                            QUOTA_LIMIT="$limit_2col"
                        fi
                     fi
                fi
            fi

            # 计算时间
            now=$(date +%s)
            days_over=$(( (now - over_quota_since) / 86400 ))
            days_left=$(( LOCK_DAYS - days_over ))
            
            lock_time=$(( over_quota_since + LOCK_DAYS * 86400 ))
            lock_date=$(date -d "@$lock_time" "+%Y-%m-%d %H:%M")
            display_dir="$QUOTA_BASE/$USER"

            # 显示警告
            echo ""
            if [[ $days_left -gt 0 ]]; then
                echo -e "\033[41;37m                                             \033[0m"
                echo -e "\033[41;37m   ⚠️  严重警告：存储配额已超限！           \033[0m"
                echo -e "\033[41;37m                                             \033[0m"
                echo -e "\033[1;31m"
                echo "   当前用户: $USER"
                echo "   受限位置: $display_dir"
                echo "   配额限制: ${QUOTA_LIMIT}GB"
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
                echo "   锁定位置: $display_dir"
                echo "   锁定时间: $lock_date"
                echo ""
                echo "   请立即联系管理员解除锁定！"
                echo -e "\033[0m"
            fi
        fi
    done
    shopt -u nullglob
fi