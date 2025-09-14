#!/bin/bash

# This script is executed by a keyboard shortcut for hover reading mode (e.g., F1).
# It is designed to be relocatable and run from the installation directory.

# Determine the script's absolute directory.
APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENV_ACTIVATOR="$APP_DIR/venv/bin/activate"
LOG_FILE="/tmp/a.m.d-helper-f1.log"

# Ensure GUI tools can find the display server.
export DISPLAY=:0
if [ -z "$XAUTHORITY" ]; then
    USER_HOME=$(getent passwd "$(whoami)" | cut -d: -f6)
    XAUTH_FILE="$USER_HOME/.Xauthority"
    if [ -f "$XAUTH_FILE" ]; then
        export XAUTHORITY="$XAUTH_FILE"
    fi
fi

echo "--- F1 shortcut triggered at $(date) ---" > "$LOG_FILE"
echo "App Directory: $APP_DIR" >> "$LOG_FILE"

# Activate the virtual environment before running the script.
if [ -f "$VENV_ACTIVATOR" ]; then
    source "$VENV_ACTIVATOR"
else
    echo "FATAL: Python virtual environment activator not found at $VENV_ACTIVATOR." >> "$LOG_FILE"
    exit 1
fi

# The original script set PYTHONPATH to find 'gi' and 'pyatspi'.
# This is often required for system-level libraries not in the venv.
# This command dynamically finds the system's 'dist-packages' directory.
# We run this *after* activating the venv, which is created with --system-site-packages,
# so it should still have access to the necessary system paths.
SYSTEM_SITE_PACKAGES=$(python3 -c "import sys; print(':'.join(p for p in sys.path if p.endswith('dist-packages')))")
export PYTHONPATH="${SYSTEM_SITE_PACKAGES}:${PYTHONPATH}"
echo "PYTHONPATH set to: $PYTHONPATH" >> "$LOG_FILE"

# Execute the python script using the virtual environment.
exec python3 "$APP_DIR/f1.py" >> "$LOG_FILE" 2>&1
