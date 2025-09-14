#!/bin/bash

# This script is executed by a keyboard shortcut (e.g., F4).
# It is designed to be relocatable and run from the installation directory.

# Determine the script's absolute directory, which is the application's root.
APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENV_ACTIVATOR="$APP_DIR/venv/bin/activate"
LOG_FILE="/tmp/a.m.d-helper-f4.log"

echo "--- F4 shortcut triggered at $(date) ---" > "$LOG_FILE"
echo "App Directory: $APP_DIR" >> "$LOG_FILE"

# 快速设置显示环境 - 减少不必要的检查
export DISPLAY="${DISPLAY:-:0}"

# 快速设置 XAUTHORITY - 直接使用当前用户的 .Xauthority
if [ -z "$XAUTHORITY" ] && [ -n "$HOME" ] && [ -f "$HOME/.Xauthority" ]; then
    export XAUTHORITY="$HOME/.Xauthority"
    echo "Using XAUTHORITY: $XAUTHORITY" >> "$LOG_FILE"
fi

# 设置 DBUS 会话总线地址 - 这对于 Wayland 环境很重要
if [ -z "$DBUS_SESSION_BUS_ADDRESS" ]; then
    USER_ID=$(id -u)
    if [ -S "/run/user/$USER_ID/bus" ]; then
        export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$USER_ID/bus"
        echo "Using DBUS_SESSION_BUS_ADDRESS: $DBUS_SESSION_BUS_ADDRESS" >> "$LOG_FILE"
    fi
fi

# 设置 GTK 相关环境变量 - 确保 Wayland 和 X11 兼容
export GTK_DEBUG=""
# 自动检测显示服务器类型
if [ "$XDG_SESSION_TYPE" = "wayland" ]; then
    export GDK_BACKEND="wayland"
else
    export GDK_BACKEND="x11"
fi

# 设置 GObject Introspection 路径
export GI_TYPELIB_PATH="/usr/lib/x86_64-linux-gnu/girepository-1.0"

# 精简的环境信息日志
echo "Environment setup:" >> "$LOG_FILE"
echo "DISPLAY=$DISPLAY" >> "$LOG_FILE"
echo "XAUTHORITY=$XAUTHORITY" >> "$LOG_FILE"
echo "DBUS_SESSION_BUS_ADDRESS=$DBUS_SESSION_BUS_ADDRESS" >> "$LOG_FILE"
echo "XDG_SESSION_TYPE=$XDG_SESSION_TYPE" >> "$LOG_FILE"
echo "GDK_BACKEND=$GDK_BACKEND" >> "$LOG_FILE"

# 快速检查虚拟环境和脚本是否存在
if [ ! -f "$VENV_ACTIVATOR" ]; then
    echo "ERROR: Virtual environment not found at $VENV_ACTIVATOR" >> "$LOG_FILE"
    exit 1
fi

if [ ! -f "$APP_DIR/f4.py" ]; then
    echo "ERROR: f4.py not found at $APP_DIR/f4.py" >> "$LOG_FILE"
    exit 1
fi

# 激活虚拟环境
source "$VENV_ACTIVATOR"

# 直接运行 Python 脚本，减少日志输出以加快启动速度
echo "Starting F4 application..." >> "$LOG_FILE"
"$APP_DIR/venv/bin/python3" "$APP_DIR/f4.py" >> "$LOG_FILE" 2>&1

# 立即退出，不等待 Python 脚本完成
exit 0