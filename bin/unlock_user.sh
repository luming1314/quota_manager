#!/bin/bash
# 手动解锁用户并重置配额状态
# 用法: sudo ./unlock_user.sh <username>
# 功能: 强制恢复用户所有配置目录的读写权限，并清理配额状态

set -euo pipefail

if [ -z "${1:-}" ]; then
    echo "Usage: sudo $0 <username>"
    echo "Example: sudo $0 alice"
    echo ""
    echo "This script will:"
    echo "  1. Read all directories for the user from /etc/user_quota.conf"
    echo "  2. Restore write permissions unconditionally"
    echo "  3. Clean up all quota state files"
    exit 1
fi

USER=$1
STATE_DIR="/var/lib/quota_system"
CONFIG="/etc/user_quota.conf"

echo "========================================"
echo "� Unlocking user: $USER"
echo "========================================"
echo ""

# 检查配置文件是否存在
if [ ! -f "$CONFIG" ]; then
    echo "❌ Error: Configuration file $CONFIG not found!"
    exit 1
fi

# 创建状态目录（如果不存在）
mkdir -p "$STATE_DIR"

# 第一步：从配置文件读取所有该用户的目录并恢复权限
echo "📂 Step 1: Restoring permissions from config..."
echo ""

found_in_config=0

while read -r line || [[ -n "$line" ]]; do
    # 去除 Windows 换行符和首尾空格
    line=$(echo "$line" | tr -d '\r' | xargs)
    
    # 跳过注释和空行
    [[ -z "$line" || "$line" =~ ^# ]] && continue
    
    # 解析配置行
    config_user=""
    base_dir=""
    limit_gb=""
    
    if [[ "$line" == *"="* ]]; then
        # 旧格式: user=limit (默认 /amax/data)
        config_user=$(echo "$line" | cut -d'=' -f1 | xargs)
        limit_gb=$(echo "$line" | cut -d'=' -f2 | xargs)
        base_dir="/amax/data"
    else
        # 新格式: user base_dir limit
        read -r config_user base_dir limit_gb <<< "$line"
    fi
    
    # 只处理匹配的用户
    if [[ "$config_user" != "$USER" ]]; then
        continue
    fi
    
    found_in_config=1
    target_dir="$base_dir/$USER"
    
    echo "----------------------------------------"
    echo "� Directory: $target_dir"
    echo "   Quota: ${limit_gb}GB"
    
    # 检查目录是否存在
    if [ ! -d "$target_dir" ]; then
        echo "   ⚠️  Directory does not exist, skipping..."
        continue
    fi
    
    # 显示当前权限
    current_perms=$(stat -c "%a %U:%G" "$target_dir" 2>/dev/null || echo "unknown")
    echo "   Current: $current_perms"
    
    # 恢复所有权和写权限
    if chown "$USER:$(id -g "$USER")" "$target_dir" 2>/dev/null && chmod u+w "$target_dir" 2>/dev/null; then
        new_perms=$(stat -c "%a %U:%G" "$target_dir" 2>/dev/null || echo "unknown")
        echo "   ✅ Restored: $new_perms"
    else
        echo "   ❌ Failed to restore permissions!"
    fi
    
done < "$CONFIG"

echo ""

if [ "$found_in_config" -eq 0 ]; then
    echo "⚠️  Warning: User $USER not found in $CONFIG"
    echo "   No directories to unlock from configuration."
    echo ""
fi

# 第二步：清理所有状态文件
echo "🧹 Step 2: Cleaning up state files..."
echo ""

# Enable nullglob
shopt -s nullglob

state_files_found=0

for state_file in "$STATE_DIR/${USER}.state" "$STATE_DIR/${USER}_"*.state; do
    [[ -f "$state_file" ]] || continue
    state_files_found=1
    
    locked_file="${state_file%.state}.locked"
    warn_file="${state_file%.state}.warn_time"
    
    echo "   🗑️  Removing: $(basename "$state_file")"
    
    rm -f "$state_file"
    [ -f "$locked_file" ] && rm -f "$locked_file" && echo "   🗑️  Removing: $(basename "$locked_file")"
    [ -f "$warn_file" ] && rm -f "$warn_file" && echo "   🗑️  Removing: $(basename "$warn_file")"
done

shopt -u nullglob

if [ "$state_files_found" -eq 0 ]; then
    echo "   ℹ️  No state files found (already clean)"
fi

echo ""
echo "========================================"

# 总结
if [ "$found_in_config" -eq 0 ] && [ "$state_files_found" -eq 0 ]; then
    echo "⚠️  Nothing to do for user $USER"
    echo ""
    echo "💡 User may not be configured in $CONFIG"
else
    echo "✅ Unlock completed for user: $USER"
    echo ""
    if [ "$found_in_config" -eq 1 ]; then
        echo "📝 All configured directories have been unlocked"
    fi
    if [ "$state_files_found" -eq 1 ]; then
        echo "🧹 All quota state files have been cleaned"
    fi
fi

echo "========================================"
