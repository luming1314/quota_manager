#!/bin/bash
# 存储配额监控主程序
# 路径: /opt/quota_manager/bin/quota_monitor.sh

set -euo pipefail

CONFIG="/etc/user_quota.conf"
STATE_DIR="/var/lib/quota_system"
LOG_FILE="/var/log/quota.log"
LOCK_DAYS=7 # 宽限期（天）。测试模式设为0（立即锁定），生产环境建议设为7。

mkdir -p "$STATE_DIR"
chmod 755 "$STATE_DIR"

# === 核心处理函数 ===
process_user_quota() {
    local user="$1"
    local base_dir="$2"
    local limit_gb="$3"

    # 检查用户是否存在
    if ! id -u "$user" &>/dev/null; then return; fi

    local dir="$base_dir/$user"
    
    # 路径安全转换 (用于文件名)
    local safe_path_suffix=$(echo "$base_dir" | sed 's|/|_|g')
    local state_file="$STATE_DIR/${user}${safe_path_suffix}.state"
    local locked_file="$STATE_DIR/${user}${safe_path_suffix}.locked"

    # 目录不存在则清理状态
    if [[ ! -d "$dir" ]]; then
        rm -f "$state_file" "$locked_file"
        return
    fi
    
    # 获取用量 (KB)
    local usage_kb
    usage_kb=$(du -s --block-size=1K "$dir" 2>/dev/null | cut -f1 || echo 0)
    local limit_kb
    limit_kb=$(awk -v gb="$limit_gb" 'BEGIN {printf "%.0f", gb * 1024 * 1024}')
    local now
    now=$(date +%s)
    
    # 检查是否超限
    if [[ $usage_kb -gt $limit_kb ]]; then
        # === 超限逻辑 ===
        if [[ ! -f "$state_file" ]]; then
            # 首次发现超限，记录状态
            {
                echo "over_quota_since=$now"
                echo "QUOTA_USER=\"$user\""
                echo "QUOTA_BASE=\"$base_dir\""
                echo "QUOTA_LIMIT=\"$limit_gb\""
            } > "$state_file"
            chmod 644 "$state_file"
            echo "[$(date)] $user @ $base_dir 首次超限（限额 ${limit_gb}G，已用 $((usage_kb/1024/1024))G）" >> "$LOG_FILE"
        else
             # 状态文件已存在，检查是否需要增加元数据 (兼容旧文件)
             # 如果文件里没有 QUOTA_USER，则追加所有元数据
             if ! grep -q "QUOTA_USER=" "$state_file"; then
                 {
                    echo "QUOTA_USER=\"$user\""
                    echo "QUOTA_BASE=\"$base_dir\""
                    echo "QUOTA_LIMIT=\"$limit_gb\""
                 } >> "$state_file"
             fi
        fi
        
        # 检查锁定逻辑 (每次都检查是否到了锁定时间)
        if [[ -f "$state_file" ]]; then
            # 读取状态
            local over_quota_since=""
            # shellcheck disable=SC1090
            source "$state_file" 2>/dev/null
            
            if [[ -n "${over_quota_since:-}" ]]; then
                local days_over=$(( (now - over_quota_since) / 86400 ))
                if [[ $days_over -ge $LOCK_DAYS ]] && [[ ! -f "$locked_file" ]]; then
                    # 执行锁定
                    chown root:"$(id -g "$user")" "$dir"
                    chmod a-w "$dir"
                    touch "$locked_file"
                    echo "[$(date)] $user @ $base_dir 已超 $LOCK_DAYS 天，目录已锁定" >> "$LOG_FILE"
                fi
            fi
        fi
    else
        # === 未超限逻辑 ===
        # 清除状态，恢复权限
        if [[ -f "$state_file" ]] || [[ -f "$locked_file" ]]; then
            rm -f "$state_file"
            if [[ -f "$locked_file" ]]; then
                chmod u+w "$dir"
                chown "$user:$user" "$dir"
                rm -f "$locked_file"
                echo "[$(date)] $user @ $base_dir 已清理，恢复写权限" >> "$LOG_FILE"
            fi
        fi
    fi
}

# === 主循环 ===
# 确保配置文件存在
touch "$CONFIG"

while read -r line || [[ -n "$line" ]]; do
    # 去除 Windows 换行符 (\r) 和首尾空格
    line=$(echo "$line" | tr -d '\r' | xargs)
    # 跳过注释及空行
    [[ -z "$line" || "$line" =~ ^# ]] && continue
    
    # 变量初始化
    user=""
    base_dir=""
    limit_gb=""
    
    if [[ "$line" == *"="* ]]; then
        # 旧格式兼容: user=limit (默认 /amax/data)
        user=$(echo "$line" | cut -d'=' -f1 | xargs)
        limit_gb=$(echo "$line" | cut -d'=' -f2 | xargs)
        base_dir="/amax/data"
    else
        # 新格式: user base_dir limit
        read -r user base_dir limit_gb <<< "$line"
    fi
    
    if [[ -n "$user" && -n "$base_dir" && -n "$limit_gb" ]]; then
        process_user_quota "$user" "$base_dir" "$limit_gb"
    fi

done < "$CONFIG"