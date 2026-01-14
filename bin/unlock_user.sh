#!/bin/bash
# 手动解锁用户并重置配额状态
# 用法: sudo ./unlock_user.sh <username>

set -e

if [ -z "$1" ]; then
    echo "Usage: sudo $0 <username>"
    echo "Example: sudo $0 lu_ming_2023"
    exit 1
fi

USER=$1
BASE_DIR="/amax/data"
STATE_DIR="/var/lib/quota_system"
DIR="$BASE_DIR/$USER"

if [ ! -d "$DIR" ]; then
    echo "❌ Error: Directory $DIR does not exist."
    exit 1
fi

echo "🔓 Unlocking user $USER..."

# 1. 恢复权限
echo "   Restoring permissions for $DIR..."
if chown "$USER:$(id -g "$USER")" "$DIR" && chmod u+w "$DIR"; then
    echo "   Permissions restored."
else
    echo "   ⚠️ Warning: Failed to restore permissions. Check if you are root."
fi

# 2. 清理状态文件
echo "   Clearing lock state..."
if rm -f "$STATE_DIR/$USER.locked" "$STATE_DIR/$USER.state"; then
    echo "   State files removed."
else
    echo "   ⚠️ Warning: Failed to remove state files."
fi

echo "✅ User $USER has been unlocked."
echo "   Note: If they are still over quota, the grace period has been reset."
