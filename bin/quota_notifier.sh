#!/bin/bash
# 实时配额通知守护进程
# 路径: /opt/quota_manager/bin/quota_notifier.sh

set -u

BASE_DIR=$(dirname "$(readlink -f "$0")")/..
STATE_DIR="/var/lib/quota_system"
WARN_INTERVAL=600  # 生产环境：建议10分钟
# WARN_INTERVAL=5      # 测试环境：5秒

while true; do
    # 遍历所有状态文件
    for state_file in "$STATE_DIR"/*.state; do
        [ -e "$state_file" ] || continue
        
        # 尝试读取用户名
        # 优先读取文件内的 QUOTA_USER，兼容旧文件名
        user=""
        if grep -q "QUOTA_USER=" "$state_file"; then
             user=$(grep "QUOTA_USER=" "$state_file" | cut -d'"' -f2)
        fi
        
        # 如果未找到，尝试从文件名解析（旧兼容）
        if [[ -z "$user" ]]; then
            user=$(basename "$state_file" .state)
        fi

        # 警告时间戳文件 (与 state 文件一一对应)
        warn_file="${state_file%.state}.warn_time"
        
        # 读取上次警告时间
        last_warn=0
        if [[ -f "$warn_file" ]]; then
            last_warn=$(cat "$warn_file")
        fi
        
        current_ts=$(date +%s)
        
        # 检查是否到达警告间隔
        if (( current_ts - last_warn >= WARN_INTERVAL )); then
            # 查找在线终端
            pids_found=0
            # 获取用户的所有 tty，去重，忽略 '?'
            for tty in $(ps -u "$user" -o tty= 2>/dev/null | grep -v '?' | sort -u); do
                # ps 输出通常是 pts/0 或 tty1
                dev_tty="/dev/$tty"
                
                # 双重检查设备是否存在且是字符设备
                if [[ -c "$dev_tty" ]]; then
                    # 发送警告到该终端
                    (
                        export USER="$user"
                        export TERM=xterm-256color # 确保颜色正常显示
                        
                        # 尝试定位 banner 脚本
                        BANNER_SCRIPT="$BASE_DIR/bin/quota_banner.sh"
                        if [[ ! -f "$BANNER_SCRIPT" ]]; then
                             BANNER_SCRIPT="/opt/quota_manager/bin/quota_banner.sh"
                        fi
                        
                        if [[ -f "$BANNER_SCRIPT" ]]; then
                            # 2>/dev/null 防止终端已关闭时报错
                            timeout 1s /bin/bash "$BANNER_SCRIPT" > "$dev_tty" 2>&1 || true
                        fi
                    )
                    pids_found=1
                fi
            done
            
            if [[ "$pids_found" -eq 1 ]]; then
                echo "$current_ts" > "$warn_file"
            fi
        fi
    done
    
    sleep 5
done
