#!/bin/bash

# This script is designed to be run at system startup to launch the tray icon.
# The .deb installer places a .desktop file in /etc/xdg/autostart that calls this script.

# The application is installed in a fixed location by the package manager.
APP_DIR="/usr/share/a.m.d-helper"
VENV_ACTIVATOR="$APP_DIR/venv/bin/activate"
LOG_FILE="/tmp/a.m.d-helper-tray.log"

# Change to the app directory to ensure relative paths in the python script work correctly.
cd "$APP_DIR" || exit 1

echo "--- Tray service started at $(date) ---" > "$LOG_FILE"

# Find the current desktop user
# This is critical: we need to run as the user who is actually logged into the desktop
CURRENT_USER=$(who | grep "(:0)" | awk '{print $1}' | head -n 1)
if [ -z "$CURRENT_USER" ]; then
    CURRENT_USER=$(ps aux | grep -E "(gnome-session|xfce4-session|kde-session|mate-session|cinnamon-session)" | grep -v grep | awk '{print $1}' | head -n 1)
fi

if [ -z "$CURRENT_USER" ]; then
    echo "ERROR: Could not determine desktop user. Will try to continue as $(whoami)" >> "$LOG_FILE"
    CURRENT_USER=$(whoami)
else
    echo "Running as desktop user: $CURRENT_USER" >> "$LOG_FILE"
fi

# Check if virtual environment exists
if [ ! -f "$VENV_ACTIVATOR" ]; then
    echo "FATAL: Python virtual environment activator not found at $VENV_ACTIVATOR. Cannot start tray service." >> "$LOG_FILE"
    exit 1
fi

# --- Python 版本 / 依赖自检（Ubuntu 大版本升级后 venv 会失效）-------------
# 系统升级（例如 Python 3.12 -> 3.14）后，venv 里 site-packages 的预编译扩展
# 全部无法加载，表现为启动即报 "ModuleNotFoundError: No module named 'pystray'"。
# 这里主动检测并尝试自动重建，避免用户只看到一个不出现的托盘图标。
SYS_PYTHON="/usr/bin/python3"
[ -x "$SYS_PYTHON" ] || SYS_PYTHON="$(command -v python3)"
SYS_PY_VER=$("$SYS_PYTHON" -c 'import sys; print("%d.%d" % sys.version_info[:2])' 2>/dev/null || echo "")
VENV_PY_VER=""
if [ -f "$APP_DIR/venv/pyvenv.cfg" ]; then
    VENV_PY_VER=$(sed -n 's/^version = \([0-9][0-9]*\.[0-9][0-9]*\).*/\1/p' "$APP_DIR/venv/pyvenv.cfg" | head -n 1)
fi

NEED_REPAIR=0
REPAIR_REASON=""
if [ -n "$VENV_PY_VER" ] && [ -n "$SYS_PY_VER" ] && [ "$VENV_PY_VER" != "$SYS_PY_VER" ]; then
    NEED_REPAIR=1
    REPAIR_REASON="虚拟环境 Python $VENV_PY_VER 与系统 Python $SYS_PY_VER 不匹配"
elif ! "$APP_DIR/venv/bin/python" -c "import pystray, PIL" >/dev/null 2>&1; then
    NEED_REPAIR=1
    REPAIR_REASON="虚拟环境缺少运行依赖（pystray/PIL 无法导入）"
fi

if [ "$NEED_REPAIR" -eq 1 ]; then
    echo "ERROR: $REPAIR_REASON" >> "$LOG_FILE"
    echo "尝试运行 repair-venv.sh 自动修复..." >> "$LOG_FILE"
    REPAIRED=0
    if [ "$(id -u)" -eq 0 ]; then
        "$APP_DIR/repair-venv.sh" >> "$LOG_FILE" 2>&1 && REPAIRED=1
    elif sudo -n true 2>/dev/null; then
        sudo -n "$APP_DIR/repair-venv.sh" >> "$LOG_FILE" 2>&1 && REPAIRED=1
    elif command -v pkexec >/dev/null 2>&1 && [ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]; then
        # 弹出系统授权框（用户输入一次密码），修复过程全自动
        pkexec "$APP_DIR/repair-venv.sh" >> "$LOG_FILE" 2>&1 && REPAIRED=1
    fi

    if [ "$REPAIRED" -ne 1 ]; then
        echo "FATAL: $REPAIR_REASON；自动修复未完成。请运行: sudo $APP_DIR/repair-venv.sh" >> "$LOG_FILE"
        if command -v zenity >/dev/null 2>&1; then
            zenity --error --no-wrap --title="A.M.D-HELPER 需要修复" \
                --text="$REPAIR_REASON。\n\n请在终端执行：\nsudo $APP_DIR/repair-venv.sh\n\n执行完成后重新登录即可恢复。" \
                >/dev/null 2>&1 || true
        fi
        exit 1
    fi
    echo "虚拟环境已修复，继续启动。" >> "$LOG_FILE"
fi

# Check if tray.py exists
if [ ! -f "$APP_DIR/tray.py" ]; then
    echo "FATAL: tray.py not found at $APP_DIR/tray.py. Cannot start tray service." >> "$LOG_FILE"
    exit 1
fi

# If we're running as root but found a desktop user, switch to that user
if [ "$(id -u)" -eq 0 ] && [ "$CURRENT_USER" != "root" ]; then
    echo "Switching from root to user: $CURRENT_USER" >> "$LOG_FILE"
    
    # Find the user's home directory
    USER_HOME=$(getent passwd "$CURRENT_USER" | cut -d: -f6)
    
    # Set up environment for the user
    export DISPLAY="${DISPLAY:-:0}"
    export XAUTHORITY="$USER_HOME/.Xauthority"
    export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$(id -u $CURRENT_USER)/bus"
    
    # Switch to the user and restart this script
    exec sudo -u "$CURRENT_USER" env DISPLAY="$DISPLAY" XAUTHORITY="$XAUTHORITY" DBUS_SESSION_BUS_ADDRESS="$DBUS_SESSION_BUS_ADDRESS" "$0"
    exit 0
fi

# Set up display environment for GUI applications
export DISPLAY="${DISPLAY:-:0}"

# Set up XAUTHORITY if not already set
if [ -z "$XAUTHORITY" ]; then
    USER_HOME=$(getent passwd "$(whoami)" | cut -d: -f6)
    XAUTH_FILE="$USER_HOME/.Xauthority"
    if [ -f "$XAUTH_FILE" ]; then
        export XAUTHORITY="$XAUTH_FILE"
        echo "Using XAUTHORITY: $XAUTH_FILE" >> "$LOG_FILE"
    else
        echo "Warning: XAUTHORITY file not found at $XAUTH_FILE" >> "$LOG_FILE"
    fi
fi

# Set up DBUS session bus address if not already set
if [ -z "$DBUS_SESSION_BUS_ADDRESS" ]; then
    USER_ID=$(id -u)
    if [ -S "/run/user/$USER_ID/bus" ]; then
        export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$USER_ID/bus"
        echo "Using DBUS_SESSION_BUS_ADDRESS: $DBUS_SESSION_BUS_ADDRESS" >> "$LOG_FILE"
    fi
fi

# Set up GTK and GUI environment variables
export GTK_DEBUG=""
export XDG_SESSION_TYPE="${XDG_SESSION_TYPE:-x11}"
export XDG_CURRENT_DESKTOP="${XDG_CURRENT_DESKTOP:-GNOME}"
# 仅在 Xorg 会话强制 X11 后端。Wayland 会话（Ubuntu 26.04 默认）下强制
# GDK_BACKEND=x11 会退化到 XWayland，可能拿不到显示授权（实测出现
# "Authorization required" 警告）。
if [ "$XDG_SESSION_TYPE" = "x11" ]; then
    export GDK_BACKEND="x11"
fi

# Ensure GUI libraries can be found
export LD_LIBRARY_PATH="/usr/lib/x86_64-linux-gnu:/lib/x86_64-linux-gnu:${LD_LIBRARY_PATH}"

# Critical: Set GObject Introspection path for GTK
export GI_TYPELIB_PATH="/usr/lib/x86_64-linux-gnu/girepository-1.0"

# Ensure Python can find system packages
export PYTHONPATH="/usr/lib/python3/dist-packages:${PYTHONPATH}"

# Wait a moment to ensure desktop environment is ready
sleep 3

echo "Environment setup:" >> "$LOG_FILE"
echo "DISPLAY=$DISPLAY" >> "$LOG_FILE"
echo "XAUTHORITY=$XAUTHORITY" >> "$LOG_FILE"
echo "DBUS_SESSION_BUS_ADDRESS=$DBUS_SESSION_BUS_ADDRESS" >> "$LOG_FILE"
echo "XDG_SESSION_TYPE=$XDG_SESSION_TYPE" >> "$LOG_FILE"
echo "XDG_CURRENT_DESKTOP=$XDG_CURRENT_DESKTOP" >> "$LOG_FILE"
echo "USER=$(whoami)" >> "$LOG_FILE"
echo "GI_TYPELIB_PATH=$GI_TYPELIB_PATH" >> "$LOG_FILE"
echo "PYTHONPATH=$PYTHONPATH" >> "$LOG_FILE"

# Activate the virtual environment
echo "Activating virtual environment..." >> "$LOG_FILE"
# 忽略 ~/.local/lib/pythonX.Y/site-packages，避免用户环境里的旧版包
# （numpy/torch 等）混入 venv 造成难以复现的导入错误。
export PYTHONNOUSERSITE=1
source "$VENV_ACTIVATOR"

# Verify virtual environment activation
echo "Virtual environment PATH: $PATH" >> "$LOG_FILE"
echo "Python executable: $(which python3)" >> "$LOG_FILE"
echo "Python path: $(python3 -c 'import sys; print(sys.executable)')" >> "$LOG_FILE"

# Check if virtual environment has all required packages
echo "Checking virtual environment completeness..." >> "$LOG_FILE"
pip list >> "$LOG_FILE" 2>&1

# Check if required modules are available
echo "Checking Python environment..." >> "$LOG_FILE"
python3 -c "import sys; print('Python version:', sys.version)" >> "$LOG_FILE" 2>&1
python3 -c "import sys; print('Python path:', sys.path)" >> "$LOG_FILE" 2>&1
python3 -c "import PIL; print('PIL version:', PIL.__version__)" >> "$LOG_FILE" 2>&1 || echo "ERROR: PIL not found in virtual environment" >> "$LOG_FILE"

# Test GTK availability
echo "Testing GTK availability..." >> "$LOG_FILE"
python3 -c "
import gi
try:
    gi.require_version('Gtk', '3.0')
    from gi.repository import Gtk
    print('GTK import successful')
    if Gtk.init_check()[0]:
        print('GTK initialization successful')
    else:
        print('GTK initialization failed')
except Exception as e:
    print('GTK import failed:', str(e))
    import traceback
    traceback.print_exc()
" >> "$LOG_FILE" 2>&1

python3 -c "import pystray; print('pystray imported successfully')" >> "$LOG_FILE" 2>&1 || echo "ERROR: pystray not found in virtual environment" >> "$LOG_FILE"

echo "Starting tray application..." >> "$LOG_FILE"

# Run the application
python3 "$APP_DIR/tray.py" >> "$LOG_FILE" 2>&1

# If we get here, the application exited
echo "Tray application exited with status: $?" >> "$LOG_FILE"