#!/bin/bash
# ============================================================================
# A.M.D-HELPER 运行环境修复脚本
#
# 用途:
#   系统大版本升级（例如 Ubuntu 24.04 -> 26.04）后，系统 python3 可能从
#   3.12 变成 3.14。此时旧的 venv 仍然指向上一个解释器，site-packages 里的
#   预编译扩展（torch / numpy / onnxruntime / pygame ...）全部无法加载，
#   托盘程序一启动就报:
#     ModuleNotFoundError: No module named 'pystray'
#   本脚本按当前系统 Python 重建 venv 并重新安装全部依赖。
#
# 用法:
#   sudo /usr/share/a.m.d-helper/repair-venv.sh
#
# 说明:
#   - 只重建 venv 目录，不会动 models/（Piper 语音模型）与用户配置。
#   - 可重复执行，幂等。
# ============================================================================
set -e
set -o pipefail

APP_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
VENV_DIR="$APP_DIR/venv"
LOG_FILE="/tmp/a.m.d-helper-repair.log"
PIP_MIRROR_OPTIONS="--index-url https://pypi.tuna.tsinghua.edu.cn/simple"
PIP_TIMEOUT_OPTION="--timeout 90 --retries 3"

if [ "$(id -u)" -ne 0 ]; then
    echo "错误: 需要 root 权限。请运行: sudo $0" >&2
    exit 1
fi

echo "--- A.M.D-HELPER 环境修复 $(date) ---" | tee -a "$LOG_FILE"

SYS_PYTHON="/usr/bin/python3"
[ -x "$SYS_PYTHON" ] || SYS_PYTHON="$(command -v python3)"
# 同 postinst：避免 pip 因 ~/.local 里已有包而跳过 venv 内的安装。
export PYTHONNOUSERSITE=1
# 构建隔离环境（PEP 517）也走镜像源，避免 pypi.org 不可达时卡死。
export PIP_INDEX_URL="https://pypi.tuna.tsinghua.edu.cn/simple"
export PIP_TIMEOUT=90
export PIP_RETRIES=3
SYS_PY_VER=$("$SYS_PYTHON" -c 'import sys; print("%d.%d" % sys.version_info[:2])')
VENV_PY_VER=""
if [ -f "$VENV_DIR/pyvenv.cfg" ]; then
    VENV_PY_VER=$(sed -n 's/^version = \([0-9][0-9]*\.[0-9][0-9]*\).*/\1/p' "$VENV_DIR/pyvenv.cfg" | head -n 1)
fi
echo "系统 Python: $SYS_PY_VER | 旧 venv Python: ${VENV_PY_VER:-无}" | tee -a "$LOG_FILE"

# 停止正在运行的托盘实例，避免旧进程占用 D-Bus 名
pkill -f "$APP_DIR/tray.py" 2>/dev/null || true

echo "重建虚拟环境 $VENV_DIR ..." | tee -a "$LOG_FILE"
rm -rf "$VENV_DIR"
"$SYS_PYTHON" -m venv --system-site-packages "$VENV_DIR" >> "$LOG_FILE" 2>&1

echo "升级 pip ..." | tee -a "$LOG_FILE"
"$VENV_DIR/bin/pip" install $PIP_TIMEOUT_OPTION $PIP_MIRROR_OPTIONS --upgrade pip >> "$LOG_FILE" 2>&1 \
    || "$VENV_DIR/bin/pip" install $PIP_TIMEOUT_OPTION --upgrade pip >> "$LOG_FILE" 2>&1

echo "安装 PyTorch (CPU 版) ..." | tee -a "$LOG_FILE"
if "$VENV_DIR/bin/pip" install $PIP_TIMEOUT_OPTION --no-deps --index-url https://download.pytorch.org/whl/cpu torch torchvision >> "$LOG_FILE" 2>&1; then
    "$VENV_DIR/bin/pip" install $PIP_TIMEOUT_OPTION $PIP_MIRROR_OPTIONS filelock typing-extensions sympy networkx jinja2 fsspec >> "$LOG_FILE" 2>&1 \
        || echo "警告: PyTorch 依赖安装不完整。" | tee -a "$LOG_FILE"
else
    echo "CPU 版安装失败，回退默认源 ..." | tee -a "$LOG_FILE"
    "$VENV_DIR/bin/pip" install $PIP_TIMEOUT_OPTION $PIP_MIRROR_OPTIONS torch torchvision >> "$LOG_FILE" 2>&1 \
        || echo "警告: PyTorch 安装失败，OCR 将不可用。" | tee -a "$LOG_FILE"
fi

echo "安装应用依赖 (requirements.txt) ..." | tee -a "$LOG_FILE"
if ! "$VENV_DIR/bin/pip" install $PIP_TIMEOUT_OPTION $PIP_MIRROR_OPTIONS -r "$APP_DIR/requirements.txt" >> "$LOG_FILE" 2>&1; then
    "$VENV_DIR/bin/pip" install $PIP_TIMEOUT_OPTION -r "$APP_DIR/requirements.txt" >> "$LOG_FILE" 2>&1 \
        || { echo "错误: 依赖安装失败，详见 $LOG_FILE" | tee -a "$LOG_FILE"; exit 1; }
fi

echo "安装本地 libshot ..." | tee -a "$LOG_FILE"
"$VENV_DIR/bin/pip" install $PIP_TIMEOUT_OPTION $PIP_MIRROR_OPTIONS setuptools wheel >> "$LOG_FILE" 2>&1 || true
"$VENV_DIR/bin/pip" install $PIP_TIMEOUT_OPTION $PIP_MIRROR_OPTIONS --no-build-isolation "$APP_DIR/libshot" >> "$LOG_FILE" 2>&1 \
    || { echo "错误: libshot 安装失败，详见 $LOG_FILE" | tee -a "$LOG_FILE"; exit 1; }

chown -R root:root "$VENV_DIR" 2>/dev/null || true

echo "自检 ..." | tee -a "$LOG_FILE"
if "$VENV_DIR/bin/python" - <<'PY_VERIFY' >> "$LOG_FILE" 2>&1
import sys

missing = []
for mod in ("gi", "pystray", "dbus_next", "PIL", "pyperclip", "mss", "jeepney", "pygame", "edge_tts", "easyocr", "torch"):
    try:
        __import__(mod)
    except Exception as exc:
        missing.append("%s: %s" % (mod, exc))

if missing:
    print("MISSING_OR_BROKEN:")
    print("\n".join(missing))
    sys.exit(1)

import gi
gi.require_version("Gtk", "3.0")
gi.require_version("Atspi", "2.0")
from gi.repository import Gtk, Atspi  # noqa: F401
print("环境自检通过: Python %s" % sys.version.split()[0])
PY_VERIFY
then
    echo "✅ 修复完成。请重新登录桌面，或在托盘菜单退出后重新启动。" | tee -a "$LOG_FILE"
    echo "   启动命令: $APP_DIR/tray.sh" | tee -a "$LOG_FILE"
    exit 0
else
    echo "❌ 自检失败，详见 $LOG_FILE" | tee -a "$LOG_FILE"
    tail -n 30 "$LOG_FILE" >&2
    exit 1
fi
