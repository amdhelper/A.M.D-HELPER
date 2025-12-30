#!/bin/bash
#
# This script packages the A.M.D-HELPER application into a .deb file for Debian-based systems.
# It is designed to create a fully automated installation experience, especially for visually impaired users.
#
# v8 - Fixed shortcut setup and cleaned up duplicate code

set -e

# --- Configuration ---
APP_NAME="a.m.d-helper"
VERSION="0.56.3"
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
cat <<'POSTINST_EOF' > "$DEB_DIR/DEBIAN/postinst"
#!/bin/bash
set -e

APP_DIR="/usr/share/a.m.d-helper"
VENV_DIR="$APP_DIR/venv"
LOG_FILE="/tmp/a.m.d-helper-install.log"

echo "--- A.M.D-HELPER Installation Log ---" > "$LOG_FILE"
date >> "$LOG_FILE"
echo "------------------------------------" >> "$LOG_FILE"

echo "Starting A.M.D-HELPER post-installation setup..."
echo "A detailed log is available in $LOG_FILE"

REAL_USER=${SUDO_USER:-$(whoami)}
USER_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)
echo "Installation user: $REAL_USER, HOME: $USER_HOME" >> "$LOG_FILE"

# --- 1. Create and populate virtual environment ---
echo "Creating Python virtual environment..."
python3 -m venv --system-site-packages "$VENV_DIR" >> "$LOG_FILE" 2>&1

echo "Installing Python dependencies. This may take several minutes..."

PIP_MIRROR_OPTIONS="--index-url https://pypi.tuna.tsinghua.edu.cn/simple"
PIP_TIMEOUT_OPTION="--timeout 90"

echo "Step 1/3: Upgrading pip..."
if ! "$VENV_DIR/bin/pip" install $PIP_TIMEOUT_OPTION $PIP_MIRROR_OPTIONS --upgrade pip 2>&1 | tee -a "$LOG_FILE"; then
    if ! "$VENV_DIR/bin/pip" install $PIP_TIMEOUT_OPTION --upgrade pip 2>&1 | tee -a "$LOG_FILE"; then
        echo "FATAL: Failed to upgrade pip." | tee -a "$LOG_FILE"
        exit 1
    fi
fi

echo "Step 2/3: Installing application requirements..."
if ! "$VENV_DIR/bin/pip" install $PIP_TIMEOUT_OPTION $PIP_MIRROR_OPTIONS -r "$APP_DIR/requirements.txt" 2>&1 | tee -a "$LOG_FILE"; then
    if ! "$VENV_DIR/bin/pip" install $PIP_TIMEOUT_OPTION -r "$APP_DIR/requirements.txt" 2>&1 | tee -a "$LOG_FILE"; then
        echo "FATAL: Failed to install requirements." | tee -a "$LOG_FILE"
        exit 1
    fi
fi

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
    chmod +x "$APP_DIR/run.sh" 2>/dev/null || true
    chmod +x "$APP_DIR/run_hover.sh" 2>/dev/null || true
    chmod +x "$APP_DIR/tray.sh" 2>/dev/null || true
} >> "$LOG_FILE" 2>&1

# --- 3. Set custom keyboard shortcut for F4 ---
echo "Setting up keyboard shortcut..."
{
    if command -v gsettings &> /dev/null && [ -n "$USER_HOME" ]; then
        echo "Setting up F4 keyboard shortcut for GNOME..."

        # 创建快捷键设置脚本
        SHORTCUT_SCRIPT="$USER_HOME/.config/a.m.d-helper/setup-shortcut.sh"
        mkdir -p "$USER_HOME/.config/a.m.d-helper"
        
        cat > "$SHORTCUT_SCRIPT" << 'SHORTCUT_EOF'
#!/bin/bash
# F4 快捷键设置脚本 - 修复版
LOG="/tmp/a.m.d-helper-shortcut.log"
echo "=== 快捷键设置 $(date) ===" >> "$LOG"

SHORTCUT_NAME="A.M.D-HELPER OCR"
CMD="/usr/share/a.m.d-helper/run.sh"
BINDING="F4"
FOUND_SLOT=""

# 检查是否已存在，同时验证 binding 是否正确设置
for i in $(seq 0 19); do
    SLOT="/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom$i/"
    NAME=$(gsettings get org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:"$SLOT" name 2>/dev/null || echo "")
    CURRENT_BINDING=$(gsettings get org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:"$SLOT" binding 2>/dev/null || echo "")
    CURRENT_CMD=$(gsettings get org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:"$SLOT" command 2>/dev/null || echo "")
    echo "检查 custom$i: name=$NAME, binding=$CURRENT_BINDING, command=$CURRENT_CMD" >> "$LOG"
    
    if [[ "$NAME" == "'$SHORTCUT_NAME'" ]]; then
        FOUND_SLOT="$i"
        # 检查 binding 和 command 是否正确
        if [[ "$CURRENT_BINDING" == "'$BINDING'" && "$CURRENT_CMD" == "'$CMD'" ]]; then
            # 还需要检查是否在 custom-keybindings 列表中
            KEYBINDINGS=$(gsettings get org.gnome.settings-daemon.plugins.media-keys custom-keybindings)
            echo "当前快捷键列表: $KEYBINDINGS" >> "$LOG"
            if [[ "$KEYBINDINGS" == *"$SLOT"* ]]; then
                echo "快捷键已正确配置于 custom$i" >> "$LOG"
                exit 0
            else
                echo "快捷键存在但未在列表中，需要添加" >> "$LOG"
            fi
        else
            echo "快捷键存在但配置不完整，需要修复" >> "$LOG"
        fi
        break
    fi
done

# 如果找到了但配置不完整，修复它
if [[ -n "$FOUND_SLOT" ]]; then
    SLOT="/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom$FOUND_SLOT/"
    echo "修复槽位 custom$FOUND_SLOT" >> "$LOG"
    
    gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:"$SLOT" name "$SHORTCUT_NAME" 2>> "$LOG"
    gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:"$SLOT" command "$CMD" 2>> "$LOG"
    gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:"$SLOT" binding "$BINDING" 2>> "$LOG"
    
    # 确保在列表中
    CURRENT=$(gsettings get org.gnome.settings-daemon.plugins.media-keys custom-keybindings)
    if [[ "$CURRENT" != *"$SLOT"* ]]; then
        if [[ "$CURRENT" == "@as []" ]]; then
            NEW="['$SLOT']"
        else
            NEW=$(echo "$CURRENT" | sed "s/]$/, '$SLOT']/")
        fi
        echo "更新快捷键列表: $NEW" >> "$LOG"
        gsettings set org.gnome.settings-daemon.plugins.media-keys custom-keybindings "$NEW" 2>> "$LOG"
    fi
    
    echo "F4 快捷键修复成功 (slot: custom$FOUND_SLOT)" >> "$LOG"
    exit 0
fi

# 查找空槽位创建新快捷键
for i in $(seq 0 19); do
    SLOT="/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom$i/"
    NAME=$(gsettings get org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:"$SLOT" name 2>/dev/null || echo "")
    if [[ -z "$NAME" || "$NAME" == "''" ]]; then
        echo "使用空槽位 custom$i" >> "$LOG"
        
        gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:"$SLOT" name "$SHORTCUT_NAME" 2>> "$LOG"
        gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:"$SLOT" command "$CMD" 2>> "$LOG"
        gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:"$SLOT" binding "$BINDING" 2>> "$LOG"
        
        CURRENT=$(gsettings get org.gnome.settings-daemon.plugins.media-keys custom-keybindings)
        echo "当前快捷键列表: $CURRENT" >> "$LOG"
        if [[ "$CURRENT" == "@as []" ]]; then
            NEW="['$SLOT']"
        else
            NEW=$(echo "$CURRENT" | sed "s/]$/, '$SLOT']/")
        fi
        echo "新快捷键列表: $NEW" >> "$LOG"
        gsettings set org.gnome.settings-daemon.plugins.media-keys custom-keybindings "$NEW" 2>> "$LOG"
        
        echo "F4 快捷键设置成功 (slot: custom$i)" >> "$LOG"
        exit 0
    fi
done

echo "没有可用的快捷键槽位" >> "$LOG"
exit 1
SHORTCUT_EOF

        chmod +x "$SHORTCUT_SCRIPT"
        chown "$REAL_USER:$REAL_USER" "$SHORTCUT_SCRIPT"
        chown "$REAL_USER:$REAL_USER" "$USER_HOME/.config/a.m.d-helper"
        
        # 创建 autostart 条目 - 首次登录时自动设置快捷键
        AUTOSTART_DIR="$USER_HOME/.config/autostart"
        mkdir -p "$AUTOSTART_DIR"
        cat > "$AUTOSTART_DIR/a.m.d-helper-setup.desktop" << DESKTOP_EOF
[Desktop Entry]
Type=Application
Name=A.M.D-HELPER Shortcut Setup
Exec=$SHORTCUT_SCRIPT
Hidden=false
NoDisplay=true
X-GNOME-Autostart-enabled=true
X-GNOME-Autostart-Delay=5
DESKTOP_EOF
        chown "$REAL_USER:$REAL_USER" "$AUTOSTART_DIR/a.m.d-helper-setup.desktop"
        
        echo "快捷键设置脚本已创建，将在下次登录时自动运行。"
        echo "你也可以手动运行: $SHORTCUT_SCRIPT"
    fi
} >> "$LOG_FILE" 2>&1

echo "Installation finished successfully."
exit 0
POSTINST_EOF

# --- Create DEBIAN/prerm (pre-removal) script ---
echo "Creating DEBIAN/prerm script..."
cat <<'PRERM_EOF' > "$DEB_DIR/DEBIAN/prerm"
#!/bin/bash
set -e

APP_DIR="/usr/share/a.m.d-helper"
LOG_FILE="/tmp/a.m.d-helper-uninstall.log"

echo "Starting cleanup..." > "$LOG_FILE"

REAL_USER=${SUDO_USER:-$(whoami)}
USER_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)

pkill -f "$APP_DIR/tray.py" || true

# 清理快捷键设置脚本
rm -f "$USER_HOME/.config/a.m.d-helper/setup-shortcut.sh"
rm -f "$USER_HOME/.config/autostart/a.m.d-helper-setup.desktop"
rm -f /etc/xdg/autostart/a.m.d-helper.desktop

echo "Cleanup complete." >> "$LOG_FILE"
exit 0
PRERM_EOF

# --- Create DEBIAN/postrm (post-removal) script ---
cat <<'POSTRM_EOF' > "$DEB_DIR/DEBIAN/postrm"
#!/bin/bash
set -e
rm -f /tmp/a.m.d-helper-install.log
rm -f /tmp/a.m.d-helper-uninstall.log
rm -f /tmp/a.m.d-helper-shortcut-setup.log
exit 0
POSTRM_EOF

# --- Create .desktop files ---
echo "Creating .desktop files..."

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
