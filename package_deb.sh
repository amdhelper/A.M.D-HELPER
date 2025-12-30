#!/bin/bash
#
# This script packages the A.M.D-HELPER application into a .deb file for Debian-based systems.
# It is designed to create a fully automated installation experience, especially for visually impaired users.
#
# v7 - Final fix
# - Removed disallowed comment from DEBIAN/control file.

set -e

# --- Configuration ---
APP_NAME="a.m.d-helper"
VERSION="0.54.0"
ARCH="amd64"
MAINTAINER="Your Name <your.email@example.com>"
DESCRIPTION_SHORT="A screen reader and OCR application."
DESCRIPTION_LONG="A.M.D-HELPER is an accessibility tool that provides screen reading (TTS) and optical character recognition (OCR) capabilities.
 This package automatically configures the application, including dependencies, autostart, and custom keyboard shortcuts."

# --- Build directories ---
BUILD_DIR="${APP_NAME}_${VERSION}_${ARCH}"
DEB_DIR="$BUILD_DIR"
APP_INSTALL_DIR="/usr/share/$APP_NAME"

# --- Cleanup previous builds ---
echo "Cleaning up previous build directories..."
rm -rf "$BUILD_DIR"
rm -f "${APP_NAME}_${VERSION}_${ARCH}.deb"

# --- Create package structure ---
echo "Creating package directory structure..."
mkdir -p "$DEB_DIR/DEBIAN"
mkdir -p "$DEB_DIR$APP_INSTALL_DIR"
mkdir -p "$DEB_DIR/usr/share/applications"
mkdir -p "$DEB_DIR/etc/xdg/autostart"

# --- Copy application files ---
echo "Copying application files..."
rsync -av --progress \
    --exclude "$BUILD_DIR" \
    --exclude "*.deb" \
    --exclude "package_deb.sh" \
    --exclude ".git" \
    --exclude ".vscode" \
    --exclude "venv" \
    --exclude "libshot/venv" \
    --exclude "__pycache__" \
    --exclude "build" \
    . "$DEB_DIR$APP_INSTALL_DIR/"


# --- Create DEBIAN/control file ---
cat <<EOF > "$DEB_DIR/DEBIAN/control"
Package: $APP_NAME
Version: $VERSION
Architecture: $ARCH
Maintainer: $MAINTAINER
Depends: python3, python3-venv, python3-pip, python3-gi, gir1.2-gdkpixbuf-2.0, gnome-settings-daemon, coreutils, procps
Description: $DESCRIPTION_SHORT
 $DESCRIPTION_LONG
EOF

# --- Create DEBIAN/postinst (post-installation) script ---
echo "Creating DEBIAN/postinst script for automated setup..."
cat <<'EOF' > "$DEB_DIR/DEBIAN/postinst"
#!/bin/bash
set -e

APP_DIR="/usr/share/a.m.d-helper"
VENV_DIR="$APP_DIR/venv"
LOG_FILE="/tmp/a.m.d-helper-install.log"

# Start with a clean log file and provide user-facing status updates.
echo "--- A.M.D-HELPER Installation Log ---" > "$LOG_FILE"
date >> "$LOG_FILE"
echo "------------------------------------" >> "$LOG_FILE"

echo "Starting A.M.D-HELPER post-installation setup..."
echo "A detailed log is available in $LOG_FILE"

REAL_USER=${SUDO_USER:-$(whoami)}
USER_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)
echo "Installation user: $REAL_USER" >> "$LOG_FILE"

# --- 1. Create and populate virtual environment ---
echo "Creating Python virtual environment with access to system site-packages..."
# Using --system-site-packages is key to allow the venv to use system-installed libraries like PyGObject (python3-gi)
python3 -m venv --system-site-packages "$VENV_DIR" >> "$LOG_FILE" 2>&1

echo "Installing Python dependencies. This may take several minutes..."

# Setup pip options
PIP_MIRROR_OPTIONS="--index-url https://pypi.tuna.tsinghua.edu.cn/simple"
PIP_TIMEOUT_OPTION="--timeout 90"

# Upgrade pip, showing progress to the user via tee
echo "Step 1/3: Upgrading pip..."
if ! "$VENV_DIR/bin/pip" install $PIP_TIMEOUT_OPTION $PIP_MIRROR_OPTIONS --upgrade pip 2>&1 | tee -a "$LOG_FILE"; then
    echo "Pip upgrade with mirror failed. Retrying with default PyPI..." | tee -a "$LOG_FILE"
    if ! "$VENV_DIR/bin/pip" install $PIP_TIMEOUT_OPTION --upgrade pip 2>&1 | tee -a "$LOG_FILE"; then
        echo "FATAL: Failed to upgrade pip." | tee -a "$LOG_FILE"
        exit 1
    fi
fi

# Install requirements, showing progress to the user via tee
# PyGObject will be skipped by pip because it's already visible from the system site-packages.
echo "Step 2/3: Installing application requirements..."
if ! "$VENV_DIR/bin/pip" install $PIP_TIMEOUT_OPTION $PIP_MIRROR_OPTIONS -r "$APP_DIR/requirements.txt" 2>&1 | tee -a "$LOG_FILE"; then
    echo "Installation with mirror failed. Retrying with default PyPI..." | tee -a "$LOG_FILE"
    if ! "$VENV_DIR/bin/pip" install $PIP_TIMEOUT_OPTION -r "$APP_DIR/requirements.txt" 2>&1 | tee -a "$LOG_FILE"; then
        echo "FATAL: Failed to install requirements." | tee -a "$LOG_FILE"
        exit 1
    fi
fi

# Install the local libshot library
echo "Step 3/3: Installing local libshot library..."
if ! "$VENV_DIR/bin/pip" install "$APP_DIR/libshot" 2>&1 | tee -a "$LOG_FILE"; then
    echo "FATAL: Failed to install local libshot library." | tee -a "$LOG_FILE"
    exit 1
fi
echo "Dependency installation complete."


# --- 2. Set file permissions ---
echo "Setting file permissions..."
{
    chown -R root:root "$APP_DIR"
    chmod +x "$APP_DIR/run.sh"
    chmod +x "$APP_DIR/run_fast.sh"
    chmod +x "$APP_DIR/run_hover.sh"
    chmod +x "$APP_DIR/tray.sh"
} >> "$LOG_FILE" 2>&1


# --- 3. Set custom keyboard shortcut for F4 ---
echo "Setting up keyboard shortcut..."
{
    if command -v gsettings &> /dev/null && [ -n "$USER_HOME" ]; then
        echo "Attempting to set F4 keyboard shortcut for GNOME..."

        # 获取用户的 UID
        USER_ID=$(id -u "$REAL_USER" 2>/dev/null)
        if [ -z "$USER_ID" ]; then
            echo "WARNING: Could not get UID for user $REAL_USER"
            USER_ID=$(id -u)
        fi
        
        # 设置 XDG_RUNTIME_DIR
        XDG_RUNTIME_DIR="/run/user/$USER_ID"
        
        # 检查 D-Bus socket 是否存在
        if [ ! -S "$XDG_RUNTIME_DIR/bus" ]; then
            echo "WARNING: D-Bus session bus socket not found at $XDG_RUNTIME_DIR/bus"
            echo "The user may need to log in first. Shortcut will be set on first login."
            
            # 创建一个首次登录时运行的脚本
            FIRST_RUN_SCRIPT="$USER_HOME/.config/a.m.d-helper/setup-shortcut.sh"
            mkdir -p "$USER_HOME/.config/a.m.d-helper"
            cat > "$FIRST_RUN_SCRIPT" << 'SHORTCUT_SCRIPT'
#!/bin/bash
# This script sets up the F4 keyboard shortcut on first login
SHORTCUT_APP_NAME="A.M.D-HELPER OCR"
CMD_TO_RUN="/usr/share/a.m.d-helper/run.sh"
BINDING="F4"

# Check if shortcut already exists
for i in {0..19}; do
    SLOT_PATH="/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom$i/"
    EXISTING_NAME=$(gsettings get org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:"$SLOT_PATH" name 2>/dev/null || echo "free")
    if [[ "$EXISTING_NAME" == "'$SHORTCUT_APP_NAME'" ]]; then
        echo "Shortcut already exists in slot custom$i"
        rm -f "$0"
        exit 0
    fi
done

# Find available slot
TARGET_SLOT=""
for i in {0..19}; do
    SLOT_PATH="/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom$i/"
    EXISTING_NAME=$(gsettings get org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:"$SLOT_PATH" name 2>/dev/null || echo "free")
    if [[ "$EXISTING_NAME" == "free" || "$EXISTING_NAME" == "''" ]]; then
        TARGET_SLOT="custom$i"
        break
    fi
done

if [ -n "$TARGET_SLOT" ]; then
    KEYBINDING_PATH="org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/$TARGET_SLOT/"
    SLOT_URI="/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/$TARGET_SLOT/"

    gsettings set "$KEYBINDING_PATH" name "$SHORTCUT_APP_NAME"
    gsettings set "$KEYBINDING_PATH" command "$CMD_TO_RUN"
    gsettings set "$KEYBINDING_PATH" binding "$BINDING"

    CURRENT_BINDINGS_STR=$(gsettings get org.gnome.settings-daemon.plugins.media-keys custom-keybindings | sed "s/@as //")
    if [[ ! "$CURRENT_BINDINGS_STR" =~ "$SLOT_URI" ]]; then
        NEW_BINDINGS_STR=$(python3 -c "import sys, ast; l=ast.literal_eval(sys.argv[1]); l.append(sys.argv[2]); print(l)" "$CURRENT_BINDINGS_STR" "$SLOT_URI")
        gsettings set org.gnome.settings-daemon.plugins.media-keys custom-keybindings "$NEW_BINDINGS_STR"
    fi
    echo "F4 shortcut setup completed."
fi

# Remove this script after successful execution
rm -f "$0"
SHORTCUT_SCRIPT
            chmod +x "$FIRST_RUN_SCRIPT"
            chown "$REAL_USER:$REAL_USER" "$FIRST_RUN_SCRIPT"
            chown "$REAL_USER:$REAL_USER" "$USER_HOME/.config/a.m.d-helper"
            
            # 添加到用户的 autostart 中（一次性运行）
            AUTOSTART_DIR="$USER_HOME/.config/autostart"
            mkdir -p "$AUTOSTART_DIR"
            cat > "$AUTOSTART_DIR/a.m.d-helper-setup.desktop" << DESKTOP_EOF
[Desktop Entry]
Type=Application
Name=A.M.D-HELPER Shortcut Setup
Exec=$FIRST_RUN_SCRIPT
Hidden=false
NoDisplay=true
X-GNOME-Autostart-enabled=true
DESKTOP_EOF
            chown "$REAL_USER:$REAL_USER" "$AUTOSTART_DIR/a.m.d-helper-setup.desktop"
            echo "Created first-login shortcut setup script."
        else
            # D-Bus socket 存在，直接设置快捷键
            DBUS_ADDRESS="unix:path=$XDG_RUNTIME_DIR/bus"

            run_gsettings() { sudo -u "$REAL_USER" DBUS_SESSION_BUS_ADDRESS="$DBUS_ADDRESS" XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" timeout 5 gsettings "$@"; }

            SHORTCUT_APP_NAME="A.M.D-HELPER OCR"
            CMD_TO_RUN="/usr/share/a.m.d-helper/run.sh"
            BINDING="F4"
            
            TARGET_SLOT=""
            for i in {0..19}; do
                SLOT_PATH="/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom$i/"
                EXISTING_NAME=$(run_gsettings get org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:"$SLOT_PATH" name 2>/dev/null || echo "free")
                
                if [[ "$EXISTING_NAME" == "free" || "$EXISTING_NAME" == "''" || "$EXISTING_NAME" == "'$SHORTCUT_APP_NAME'" ]]; then
                    TARGET_SLOT="custom$i"
                    break
                fi
            done

            if [ -n "$TARGET_SLOT" ]; then
                echo "Using available keybinding slot: $TARGET_SLOT"
                KEYBINDING_PATH="org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/$TARGET_SLOT/"
                SLOT_URI="/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/$TARGET_SLOT/"

                run_gsettings set "$KEYBINDING_PATH" name "$SHORTCUT_APP_NAME"
                run_gsettings set "$KEYBINDING_PATH" command "$CMD_TO_RUN"
                run_gsettings set "$KEYBINDING_PATH" binding "$BINDING"

                CURRENT_BINDINGS_STR=$(run_gsettings get org.gnome.settings-daemon.plugins.media-keys custom-keybindings | sed "s/@as //" )
                if [[ ! "$CURRENT_BINDINGS_STR" =~ "$SLOT_URI" ]]; then
                    NEW_BINDINGS_STR=$(python3 -c "import sys, ast; l=ast.literal_eval(sys.argv[1]); l.append(sys.argv[2]); print(l)" "$CURRENT_BINDINGS_STR" "$SLOT_URI")
                    run_gsettings set org.gnome.settings-daemon.plugins.media-keys custom-keybindings "$NEW_BINDINGS_STR"
                fi
                echo "GNOME shortcut setup completed for slot $TARGET_SLOT."
            else
                echo "WARNING: Could not find an available custom keybinding slot after checking custom0 through custom19. Shortcut not set."
            fi
        fi
    else
        echo "WARNING: 'gsettings' command not found or not running in a user session. Could not set F4 keyboard shortcut."
    fi
} >> "$LOG_FILE" 2>&1

echo "Installation finished successfully."
exit 0
EOF

# --- Create DEBIAN/prerm (pre-removal) script ---
echo "Creating DEBIAN/prerm script for automated cleanup..."
cat <<'EOF' > "$DEB_DIR/DEBIAN/prerm"
#!/bin/bash
set -e

APP_DIR="/usr/share/a.m.d-helper"
LOG_FILE="/tmp/a.m.d-helper-uninstall.log"

echo "Starting A.M.D-HELPER pre-removal cleanup..." > "$LOG_FILE"
exec >> "$LOG_FILE" 2>&1

REAL_USER=${SUDO_USER:-$(whoami)}
USER_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)

echo "Cleanup for user: $REAL_USER"

echo "Stopping any running A.M.D-HELPER processes..."
pkill -f "$APP_DIR/tray.py" || true

if command -v gsettings &> /dev/null && [ -n "$USER_HOME" ]; then
    echo "Attempting to remove GNOME keyboard shortcut..."
    
    DBUS_ADDRESS="unix:path=$XDG_RUNTIME_DIR/bus"
    if [ -z "$XDG_RUNTIME_DIR" ]; then
        XDG_RUNTIME_DIR="/run/user/$(id -u $REAL_USER)"
        DBUS_ADDRESS="unix:path=$XDG_RUNTIME_DIR/bus"
    fi

    run_gsettings() { sudo -u "$REAL_USER" DBUS_SESSION_BUS_ADDRESS="$DBUS_ADDRESS" timeout 5 gsettings "$@"; }

    SHORTCUT_APP_NAME="A.M.D-HELPER OCR"
    
    # Loop through all possible slots to ensure all instances are cleaned up
    for i in {0..19}; do
        SLOT_PATH="/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom$i/"
        EXISTING_NAME=$(run_gsettings get org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:"$SLOT_PATH" name 2>/dev/null || echo "free")

        if [[ "$EXISTING_NAME" == "'$SHORTCUT_APP_NAME'" ]]; then
            echo "Found keybinding in slot custom$i. Removing it."
            SLOT_URI="/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom$i/"
            
            # Remove the URI from the main list of custom keybindings
            CURRENT_BINDINGS_STR=$(run_gsettings get org.gnome.settings-daemon.plugins.media-keys custom-keybindings | sed "s/@as //")
            if [[ "$CURRENT_BINDINGS_STR" =~ "$SLOT_URI" ]]; then
                NEW_BINDINGS_STR=$(python3 -c "import sys, ast; l=ast.literal_eval(sys.argv[1]); l.remove(sys.argv[2]); print(l)" "$CURRENT_BINDINGS_STR" "$SLOT_URI")
                run_gsettings set org.gnome.settings-daemon.plugins.media-keys custom-keybindings "$NEW_BINDINGS_STR"
            fi

            # Reset the specific slot's settings to clear it completely
            KEYBINDING_PATH="org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:$SLOT_URI"
            run_gsettings reset "$KEYBINDING_PATH" name
            run_gsettings reset "$KEYBINDING_PATH" command
            run_gsettings reset "$KEYBINDING_PATH" binding
            echo "Keyboard shortcut in slot custom$i removed."
        fi
    done
fi

rm -f /etc/xdg/autostart/a.m.d-helper.desktop

echo "Pre-removal cleanup complete."
exit 0
EOF

# --- Create DEBIAN/postrm (post-removal) script ---
echo "Creating DEBIAN/postrm script for final cleanup..."
cat <<'EOF' > "$DEB_DIR/DEBIAN/postrm"
#!/bin/bash
set -e
echo "Running post-removal cleanup..."
rm -f /tmp/a.m.d-helper-install.log
rm -f /tmp/a.m.d-helper-uninstall.log
echo "A.M.D-HELPER has been uninstalled."
exit 0
EOF

# --- Create .desktop files ---
echo "Creating .desktop files for application launcher and autostart..."

cat <<EOF > "$DEB_DIR/usr/share/applications/a.m.d-helper.desktop"
[Desktop Entry]
Name=A.M.D-HELPER
Comment=$DESCRIPTION_SHORT
Exec=/usr/share/a.m.d-helper/tray.sh
Icon=/usr/share/a.m.d-helper/about.png
Terminal=false
Type=Application
Categories=Utility;Accessibility;
EOF

cat <<EOF > "$DEB_DIR/etc/xdg/autostart/a.m.d-helper.desktop"
[Desktop Entry]
Name=A.M.D-HELPER Tray
Comment=Start the A.M.D-HELPER accessibility service
Exec=/usr/share/a.m.d-helper/tray.sh
Icon=/usr/share/a.m.d-helper/about.png
Terminal=false
Type=Application
X-GNOME-Autostart-enabled=true
EOF

# --- Set script permissions ---
echo "Setting executable permissions on control scripts..."
chmod 0755 "$DEB_DIR/DEBIAN/postinst"
chmod 0755 "$DEB_DIR/DEBIAN/prerm"
chmod 0755 "$DEB_DIR/DEBIAN/postrm"

# --- Build the .deb package ---
echo "Building the Debian package..."
dpkg-deb --build "$DEB_DIR"

echo ""
echo "---------------------------------------------------"
echo "Build complete!"
echo "Package created: ${DEB_DIR}.deb"
echo "---------------------------------------------------"

exit 0
