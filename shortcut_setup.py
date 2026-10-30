#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
A.M.D-HELPER 快捷键自动绑定。

目标：deb 安装完成后（以及每次托盘启动时）自动把 F4 绑到
/usr/share/a.m.d-helper/run.sh，用户不需要手动进“设置 → 键盘”添加。

支持：
  * GNOME / Ubuntu（gsettings，custom keybindings）
  * KDE Plasma（kglobalshortcutsrc + kwriteconfig6/5）
  * XFCE（xfconf-query）

幂等：已经绑定正确时直接返回 0，不改动其它快捷键。

退出码：0 = 已就绪；1 = 当前桌面环境不支持或写入失败
"""

import os
import re
import shutil
import subprocess
import sys

APP_DIR = "/usr/share/a.m.d-helper"
COMMAND = f"{APP_DIR}/run.sh"
SHORTCUT_NAME = "A.M.D-HELPER OCR"
BINDING = "F4"
GNOME_SCHEMA = "org.gnome.settings-daemon.plugins.media-keys"
GNOME_REL = "/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/"

LOG_PATH = "/tmp/a.m.d-helper-shortcut.log"


def log(msg):
    line = f"[{__import__('datetime').datetime.now().strftime('%Y-%m-%d %H:%M:%S')}] {msg}"
    print(line)
    try:
        with open(LOG_PATH, "a", encoding="utf-8") as fh:
            fh.write(line + "\n")
    except OSError:
        pass


def run(cmd, timeout=20):
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
    except (OSError, subprocess.SubprocessError) as exc:
        return subprocess.CompletedProcess(cmd, 1, "", str(exc))


def _detect_desktop():
    desktop = (os.environ.get("XDG_CURRENT_DESKTOP") or "").lower()
    session = (os.environ.get("XDG_SESSION_DESKTOP") or "").lower()
    combined = f"{desktop}:{session}"
    if "gnome" in combined or "ubuntu" in combined or "unity" in combined:
        return "gnome"
    if "kde" in combined or "plasma" in combined:
        return "kde"
    if "xfce" in combined:
        return "xfce"
    # 环境变量缺失时按可用工具推断
    if shutil.which("gsettings") and os.environ.get("DBUS_SESSION_BUS_ADDRESS"):
        return "gnome"
    if shutil.which("xfconf-query"):
        return "xfce"
    if shutil.which("kwriteconfig6") or shutil.which("kwriteconfig5"):
        return "kde"
    return "unknown"


# --------------------------------------------------------------------------
# GNOME
# --------------------------------------------------------------------------


def _gsettings_get(schema_args):
    res = run(["gsettings", "get"] + schema_args)
    if res.returncode != 0:
        return ""
    return res.stdout.strip()


def _gsettings_set(schema_args, value):
    res = run(["gsettings", "set"] + schema_args + [value])
    if res.returncode != 0:
        log(f"gsettings set 失败: {' '.join(schema_args)} = {value}: {res.stderr.strip()}")
        return False
    return True


def _slot_path(index):
    return f"{GNOME_REL}custom{index}/"


def _custom_list():
    raw = _gsettings_get([GNOME_SCHEMA, "custom-keybindings"])
    return re.findall(r"'([^']+)'", raw)


def _write_custom_list(paths):
    value = "[" + ", ".join(f"'{p}'" for p in paths) + "]"
    return _gsettings_set([GNOME_SCHEMA, "custom-keybindings"], value)


def setup_gnome():
    if not shutil.which("gsettings"):
        log("没有 gsettings，跳过 GNOME 绑定")
        return False

    current = _custom_list()
    log(f"现有自定义快捷键槽位: {current}")

    target = None
    for path in current:
        name = _gsettings_get([f"{GNOME_SCHEMA}.custom-keybinding:{path}", "name"])
        command = _gsettings_get([f"{GNOME_SCHEMA}.custom-keybinding:{path}", "command"])
        binding = _gsettings_get([f"{GNOME_SCHEMA}.custom-keybinding:{path}", "binding"])
        log(f"检查 {path} name={name} command={command} binding={binding}")
        if name.strip("'") == SHORTCUT_NAME or command.strip("'") == COMMAND:
            target = path
            break

    if target is None:
        used = set(current)
        for index in range(0, 32):
            if _slot_path(index) not in used:
                target = _slot_path(index)
                current.append(target)
                if not _write_custom_list(current):
                    return False
                log(f"新建槽位 {target}")
                break

    if target is None:
        log("没有可用的快捷键槽位（custom0-31 都被占用）")
        return False

    schema = f"{GNOME_SCHEMA}.custom-keybinding:{target}"
    ok = True
    ok &= _gsettings_set([schema, "name"], SHORTCUT_NAME)
    ok &= _gsettings_set([schema, "command"], COMMAND)
    ok &= _gsettings_set([schema, "binding"], BINDING)

    # 再确认槽位在列表里（某些系统上单独设置子键不会自动进列表）
    paths = _custom_list()
    if target not in paths:
        paths.append(target)
        ok &= _write_custom_list(paths)

    # 校验
    name = _gsettings_get([schema, "name"]).strip("'")
    command = _gsettings_get([schema, "command"]).strip("'")
    binding = _gsettings_get([schema, "binding"]).strip("'")
    in_list = target in _custom_list()
    log(f"校验: name={name} command={command} binding={binding} in_list={in_list}")

    if ok and name == SHORTCUT_NAME and command == COMMAND and binding == BINDING and in_list:
        log(f"✅ F4 快捷键已就绪（{target}）")
        return True

    log("❌ GNOME 快捷键写入后校验未通过")
    return False


# --------------------------------------------------------------------------
# KDE
# --------------------------------------------------------------------------


def setup_kde():
    kwrite = shutil.which("kwriteconfig6") or shutil.which("kwriteconfig5")
    if not kwrite:
        log("没有 kwriteconfig6/5，跳过 KDE 绑定")
        return False

    apps_dir = os.path.expanduser("~/.local/share/applications")
    os.makedirs(apps_dir, exist_ok=True)
    desktop_file = os.path.join(apps_dir, "amd-helper.desktop")
    with open(desktop_file, "w", encoding="utf-8") as fh:
        fh.write(
            "[Desktop Entry]\n"
            "Type=Application\n"
            "Name=A.M.D-HELPER OCR\n"
            f"Exec={COMMAND}\n"
            "Terminal=false\n"
            "NoDisplay=true\n"
        )

    args = [
        kwrite,
        "--file",
        "kglobalshortcutsrc",
        "--group",
        "services",
        "--group",
        "amd-helper.desktop",
        "--key",
        "_launch",
        f"{BINDING},none,A.M.D-HELPER OCR",
    ]
    res = run(args)
    if res.returncode != 0:
        log(f"KDE 写入失败: {res.stderr.strip()}")
        return False

    # 通知 KDE 重新读取快捷键
    run(["dbus-send", "--session", "--type=signal", "/kglobalaccel",
         "org.kde.KGlobalAccel.reconfigure"])
    log("✅ KDE F4 快捷键已写入")
    return True


# --------------------------------------------------------------------------
# XFCE
# --------------------------------------------------------------------------


def setup_xfce():
    xfconf = shutil.which("xfconf-query")
    if not xfconf:
        log("没有 xfconf-query，跳过 XFCE 绑定")
        return False
    res = run([
        xfconf, "-c", "xfce4-keyboard-shortcuts", "-p",
        f"/commands/custom/{BINDING}", "-n", "-t", "string", "-s", COMMAND,
    ])
    if res.returncode != 0:
        log(f"XFCE 写入失败: {res.stderr.strip()}")
        return False
    log(f"✅ XFCE {BINDING} 快捷键已写入")
    return True


def status_gnome():
    """返回 (是否已绑定, "按键 命令")。"""
    for path in _custom_list():
        schema = f"{GNOME_SCHEMA}.custom-keybinding:{path}"
        name = _gsettings_get([schema, "name"]).strip("'")
        command = _gsettings_get([schema, "command"]).strip("'")
        binding = _gsettings_get([schema, "binding"]).strip("'")
        if name == SHORTCUT_NAME or command == COMMAND:
            return True, f"{binding or '(空)'} {command}".strip()
    return False, ""


def main():
    if "--status" in sys.argv[1:]:
        desktop = _detect_desktop()
        if desktop == "gnome":
            ok, info = status_gnome()
            print(f"BOUND {info}" if ok else "MISSING")
            return 0 if ok else 1
        print(f"UNSUPPORTED {desktop}")
        return 1

    desktop = _detect_desktop()
    log(f"当前桌面环境: {desktop}")

    handler = {"gnome": setup_gnome, "kde": setup_kde, "xfce": setup_xfce}.get(desktop)
    if handler is None:
        log("无法识别桌面环境，跳过自动绑定")
        return 1

    try:
        return 0 if handler() else 1
    except Exception as exc:  # noqa: BLE001
        log(f"设置快捷键时异常: {exc}")
        return 1


if __name__ == "__main__":
    sys.exit(main())
