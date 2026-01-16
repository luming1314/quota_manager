#!/bin/bash
# 存储配额监控主程序
# 路径: /opt/quota_manager/bin/quota_monitor.sh

set -euo pipefail

BASE="/amax/data"
CONFIG="/etc/user_quota.conf"
STATE_DIR="/var/lib/quota_system"
LOG_FILE="/var/log/quota.log"
LOCK_DAYS=7 # 宽限期（天）。测试模式设为0（立即锁定），生产环境建议设为7。


mkdir -p "$STATE_DIR"
chmod 755 "$STATE_DIR"

# 第一阶段：检查用量，记录超限起始时间
while IFS='=' read -r user limit_gb; do
    [[ -z "$user" || "$user" =~ ^# ]] && continue
    if ! id -u "$user" &>/dev/null; then
        continue
    fi

    dir="$BASE/$user"
    state_file="$STATE_DIR/$user.state"
    locked_file="$STATE_DIR/$user.locked"

    # 目录不存在则清理状态
    if [[ ! -d "$dir" ]]; then
        rm -f "$state_file" "$locked_file"
        continue
    fi

    # 获取用量（KB）
    usage_kb=$(du -s --block-size=1K "$dir" 2>/dev/null | cut -f1 || echo 0)
    limit_kb=$(awk -v gb="$limit_gb" 'BEGIN {printf "%.0f", gb * 1024 * 1024}')
    now=$(date +%s)

    if [[ $usage_kb -gt $limit_kb ]]; then
        # 超限
        if [[ ! -f "$state_file" ]]; then
            echo "over_quota_since=$now" > "$state_file"
            chmod 644 "$state_file"
            echo "[$(date)] $user 首次超限（限额 ${limit_gb}G）" >> "$LOG_FILE"
        fi
    else
        # 未超限：清除状态，恢复权限
        rm -f "$state_file"
        if [[ -f "$locked_file" ]]; then
            chmod u+w "$dir"
            chown "$user:$user" "$dir"
            rm -f "$locked_file"
            echo "[$(date)] $user 已清理，恢复写权限" >> "$LOG_FILE"
        fi
    fi
done < "$CONFIG"

# 第二阶段：检查是否超期需锁定
while IFS='=' read -r user limit_gb; do
    [[ -z "$user" || "$user" =~ ^# ]] && continue
    state_file="$STATE_DIR/$user.state"
    locked_file="$STATE_DIR/$user.locked"

    if [[ -f "$state_file" ]]; then
        chmod 644 "$state_file"
        source "$state_file" 2>/dev/null
        if [[ -n "${over_quota_since:-}" ]]; then
            days_over=$(( (now - over_quota_since) / 86400 ))
            if [[ $days_over -ge $LOCK_DAYS ]] && [[ ! -f "$locked_file" ]]; then
                dir="$BASE/$user"
                chown root:"$(id -g "$user")" "$dir"
                chmod a-w "$dir"
                touch "$locked_file"
                echo "[$(date)] $user 已超 $LOCK_DAYS 天，目录已锁定" >> "$LOG_FILE"
            fi
            
            # --- 通知逻辑已移至 quota_notifier.sh ---
        fi
    fi
done < "$CONFIG"
        fi
    fi
done < "$CONFIG"