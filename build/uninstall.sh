#!/bin/bash

# ==============================================================================
# A.M.D-helper 卸载脚本
# ==============================================================================

# 必须以 root 权限运行
if [ "$EUID" -ne 0 ]; then
  echo "请使用 sudo 运行此脚本: sudo bash ./uninstall.sh"
  exit 1
fi

set -e

# --- 语音引导函数 ---
speak() {
  echo "$1"
  if command -v spd-say &> /dev/null; then
    spd-say -w "$1"
  fi
}

# ==============================================================================
# 1. 准备工作
# ==============================================================================
speak "即将为您卸载 A.M.D-helper。"
APP_NAME="amd-helper"
APP_DIR="/opt/$APP_NAME"
REAL_USER="${SUDO_USER:-$(whoami)}"
REAL_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)
INSTALL_INFO_FILE="$APP_DIR/install-info.txt"

# ==============================================================================
# 2. 移除桌面环境配置
# ==============================================================================
speak "正在移除开机自启动和全局快捷键。"
if [ -f "$INSTALL_INFO_FILE" ]; then
    source "$INSTALL_INFO_FILE"
    
    sudo -u "$REAL_USER" bash << EOF
        # 移除自启动文件
        if [ ! -z "$AUTOSTART_FILE" ]; then
            rm -f "$AUTOSTART_FILE"
        fi

        # 移除快捷键
        if command -v gsettings &> /dev/null && [ ! -z "$SHORTCUT_IDS" ]; then
            CUSTOM_KEYS_PATH="/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/"
            current_custom_keys=$(gsettings get org.gnome.settings-daemon.plugins.media-keys custom-keybindings)
            
            for id in $SHORTCUT_IDS; do
                key_path="${CUSTOM_KEYS_PATH}${id}/"
                current_custom_keys=${current_custom_keys//'${key_path}'/}
                current_custom_keys=${current_custom_keys//, '${key_path}'/}
                current_custom_keys=${current_custom_keys//'${key_path}'/}
                gsettings reset-recursively "org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:${key_path}"
            done

            if [[ $current_custom_keys == "[, ]" ]] || [[ $current_custom_keys == "[]" ]]; then
                current_custom_keys="[]"
            fi
            gsettings set org.gnome.settings-daemon.plugins.media-keys custom-keybindings "$current_custom_keys"
        fi
EOF
fi

# ==============================================================================
# 3. 移除应用文件
# ==============================================================================
speak "正在删除应用主目录和符号链接。"
rm -rf "$APP_DIR"
rm -f /usr/local/bin/$APP_NAME

# ==============================================================================
# 4. 完成
# ==============================================================================
speak "A.M.D-helper 已成功卸载。"
echo "卸载完成！"
