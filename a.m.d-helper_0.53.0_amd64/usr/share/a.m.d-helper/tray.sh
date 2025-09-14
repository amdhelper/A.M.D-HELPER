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
export GDK_BACKEND="x11"
export XDG_SESSION_TYPE="${XDG_SESSION_TYPE:-x11}"
export XDG_CURRENT_DESKTOP="${XDG_CURRENT_DESKTOP:-GNOME}"

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