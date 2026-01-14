#!/bin/bash
# 存储配额监控主程序
# 路径: /opt/quota_manager/bin/quota_monitor.sh

set -euo pipefail

BASE="/amax/data"
CONFIG="/etc/user_quota.conf"
STATE_DIR="/var/lib/quota_system"
LOG_FILE="/var/log/quota.log"
LOCK_DAYS=7 # 宽限期（天）。测试模式设为0（立即锁定），生产环境建议设为7。
WARN_INTERVAL=3600 # 警告间隔（秒），防止刷屏。1小时通知一次

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
            
            # --- 新增：通知在线用户 ---
            warn_file="$STATE_DIR/$user.warn_time"
            last_warn=0
            if [[ -f "$warn_file" ]]; then
                last_warn=$(cat "$warn_file")
            fi
            
            # 确保 now 变量是最新的（虽然上面循环用了 now，但这里为了保险也可以沿用 or update）
            # 注意：上面的 now 是第一阶段循环计算的。第二阶段循环没有更新 now。
            # 建议给 now 赋新值或者认为脚本执行极快（通常是）在此处复用即可。
            # 这里如果不更新，now 可能有点旧，但对于 3600秒间隔无所谓。
            # 为了严谨，使用当前时间判断
            current_ts=$(date +%s)
            
            if (( current_ts - last_warn >= WARN_INTERVAL )); then
                # 寻找该用户的所有伪终端 (pts)
                # who 输出示例: user pts/0 2024-01-01 ...
                for tty in $(who | awk -v u="$user" '$1 == u {print $2}'); do
                    if [[ -c "/dev/$tty" ]]; then
                        # 启动子进程 调用 quota_banner.sh 并输出到目标终端
                        (
                            export USER="$user"
                            export QUOTA_BANNER_SHOWN="" # 强制显示，忽略已显示标记
                            # 定位脚本目录 (假设 banner 和 monitor 在同一目录)
                            BIN_DIR=$(dirname "$0")
                            if [[ ! -f "$BIN_DIR/quota_banner.sh" ]]; then
                                # 回退到绝对路径 (根据原有注释)
                                BIN_DIR="/opt/quota_manager/bin"
                            fi
                            
                            if [[ -f "$BIN_DIR/quota_banner.sh" ]]; then
                                /bin/bash "$BIN_DIR/quota_banner.sh" > "/dev/$tty" 2>&1
                            fi
                        )
                    fi
                done
                # 更新警告时间
                echo "$current_ts" > "$warn_file"
            fi
        fi
    fi
done < "$CONFIG"