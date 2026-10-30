#!/usr/bin/env python3
# -*- coding: utf-8 -*-

# 强制 pystray 使用 appindicator 后端
import os
os.environ['PYSTRAY_BACKEND'] = 'appindicator'

import sys
import json
import signal
import threading
import asyncio
import locale
import subprocess
import shutil
import smtplib
import requests
import logging
import traceback
from datetime import datetime
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart
from PIL import Image, ImageDraw

import pystray
from pystray import MenuItem, Menu

from dbus_next.service import ServiceInterface, method
from dbus_next.aio import MessageBus
from dbus_next.constants import BusType, NameFlag

# --- 日志配置 ---
LOG_FILE = "/tmp/a.m.d-helper-tray.log"

# 创建 logger
logger = logging.getLogger("AMD-HELPER")
logger.setLevel(logging.DEBUG)

# 文件处理器 - 记录所有级别
file_handler = logging.FileHandler(LOG_FILE, mode='a', encoding='utf-8')
file_handler.setLevel(logging.DEBUG)
file_formatter = logging.Formatter('%(asctime)s [%(levelname)s] %(message)s', datefmt='%Y-%m-%d %H:%M:%S')
file_handler.setFormatter(file_formatter)

# 控制台处理器 - 只显示 INFO 及以上
console_handler = logging.StreamHandler(sys.stdout)
console_handler.setLevel(logging.INFO)
console_formatter = logging.Formatter('%(message)s')
console_handler.setFormatter(console_formatter)

logger.addHandler(file_handler)
logger.addHandler(console_handler)

# 诊断用：kill -USR1 <tray_pid> 会把所有线程的调用栈写进日志。
# 排查「按了 F4 没反应 / 音频停不下来 / 托盘卡死」这类静默故障时，
# 先看栈，别靠猜（Python 3.14 + faulthandler 是标准库，不引入依赖）。
try:
    import faulthandler

    _FAULT_FILE = open(LOG_FILE, "a", encoding="utf-8", buffering=1)
    faulthandler.register(signal.SIGUSR1, file=_FAULT_FILE, all_threads=True)
except Exception:  # noqa: BLE001
    pass

# 确保可以从当前目录导入模块
sys.path.append(os.path.dirname(__file__))
from core import OcrAndTtsProcessor

# --- 全局变量 & 常量 ---
APP_NAME = "A.M.D-HELPER"
DBUS_SERVICE_NAME = "org.amd_helper.Service"
DBUS_INTERFACE_NAME = "org.amd_helper.Interface"
DBUS_OBJECT_PATH = "/org/amd_helper/Main"
VERSION = "0.57.1"
CONTACT_EMAIL = "postmaster@mail.430022.xyz"
ABOUT_TEXT = "This tool provides instant OCR and TTS functionality."

# --- 路径处理 ---
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
# 默认配置文件路径（只读）
DEFAULT_CONFIG_PATH = os.path.join(SCRIPT_DIR, "config.json")
# 用户特定的配置文件路径（读写）
USER_CONFIG_DIR = os.path.expanduser(os.path.join("~", ".config", "a.m.d-helper"))
USER_CONFIG_PATH = os.path.join(USER_CONFIG_DIR, "config.json")
ABOUT_ICON_PATH = os.path.join(SCRIPT_DIR, "about.png")

# --- 国际化 (i18n) ---
TRANSLATIONS = {
    "en": {
        "initializing": "Initializing...",
        "ready_notification": f"{APP_NAME} is ready",
        "ready_message": "Models loaded successfully, ready to use.",
        "trigger_ocr": "Trigger Screenshot OCR",
        "tts_model": "TTS Model",
        "language": "Language",
        "help": "Shortcut Help",
        "report_issue": "Report Issue",
        "about": "About",
        "exit": "Exit",
        "copy_f4": "Copy F4 Screenshot Command",
        "copy_f1": "Copy F1 Hover Command",
        "open_shortcuts": "Open System Shortcuts",
        "repair_shortcut": "Re-bind F4 Shortcut",
        "shortcut_fixed_notification": "Shortcut Ready",
        "shortcut_fixed_message": "F4 is now bound to A.M.D-HELPER.",
        "shortcut_failed_notification": "Shortcut Setup Failed",
        "shortcut_failed_message": "Could not bind F4 automatically. Open system shortcut settings and bind F4 to /usr/share/a.m.d-helper/run.sh",
        "copy_startup": "Copy Autostart Command",
        "open_startup": "Open Autostart Settings",
        "tts_switched_notification": "TTS Engine Switched",
        "tts_switched_message": "Current engine: {engine}",
        "lang_switched_notification": "Language Switched",
        "lang_switched_message": "Language set to English.",
        "command_copied_notification": "Copied Successfully",
        "command_copied_message": "Command copied to clipboard.",
        "error_pyperclip_notification": "Copy Failed",
        "error_pyperclip_message": "No clipboard tool available. Please install 'wl-clipboard' (Wayland) or 'xclip' (X11).",
        "error_open_settings_notification": "Operation Failed",
        "error_open_settings_message": "Could not open system settings automatically. Please open them manually.",
        "settings_opened_message": "System settings opened. Open Keyboard, then View and Customize Shortcuts.",
        "about_window_title": f"About {APP_NAME}",
        "about_version": f"Version: {VERSION}",
        "about_contact": f"Contact: {CONTACT_EMAIL}",
        "report_issue_window_title": "Report Issue",
        "report_issue_description": "Please describe the issue you encountered:",
        "report_issue_log_label": "The following logs will be sent along with your report:",
        "report_issue_submit": "Submit",
        "report_issue_cancel": "Cancel",
        "report_issue_success_title": "Success",
        "report_issue_success_message": "Your report has been submitted successfully. Thank you!",
        "report_issue_failure_title": "Error",
        "report_issue_failure_message": "Failed to submit the report. Please check your network connection or try again later.",
    },
    "zh_CN": {
        "initializing": "正在初始化...",
        "ready_notification": f"{APP_NAME} 已就绪",
        "ready_message": "模型加载成功，可以开始使用了",
        "trigger_ocr": "手动触发截图OCR",
        "tts_model": "TTS 模型",
        "language": "语言",
        "help": "快捷键帮助",
        "report_issue": "上报问题",
        "about": "关于",
        "exit": "退出",
        "copy_f4": "复制F4截图命令",
        "copy_f1": "复制F1悬停命令",
        "open_shortcuts": "打开系统快捷键设置",
        "repair_shortcut": "重新绑定F4快捷键",
        "shortcut_fixed_notification": "快捷键已就绪",
        "shortcut_fixed_message": "F4 已绑定到 A.M.D-HELPER",
        "shortcut_failed_notification": "快捷键设置失败",
        "shortcut_failed_message": "无法自动绑定 F4。请在系统快捷键设置里把 F4 绑定到 /usr/share/a.m.d-helper/run.sh",
        "copy_startup": "复制自启动命令",
        "open_startup": "打开自启动设置",
        "tts_switched_notification": "TTS引擎已切换",
        "tts_switched_message": "当前引擎: {engine}",
        "lang_switched_notification": "语言已切换",
        "lang_switched_message": "语言已设置为简体中文。",
        "command_copied_notification": "复制成功",
        "command_copied_message": "命令已复制到剪贴板",
        "error_pyperclip_notification": "复制失败",
        "error_pyperclip_message": "系统没有可用的剪贴板工具，请安装 wl-clipboard（Wayland）或 xclip（X11）。",
        "error_open_settings_notification": "操作失败",
        "error_open_settings_message": "无法自动打开系统设置，请手动操作。",
        "settings_opened_message": "已打开系统设置。请进入键盘，再点查看及自定义快捷键。",
        "about_window_title": f"关于 {APP_NAME}",
        "about_version": f"版本: {VERSION}",
        "about_contact": f"联系: {CONTACT_EMAIL}",
        "report_issue_window_title": "上报问题",
        "report_issue_description": "请描述您遇到的问题:",
        "report_issue_log_label": "以下日志将随报告一同发送:",
        "report_issue_submit": "提交",
        "report_issue_cancel": "取消",
        "report_issue_success_title": "成功",
        "report_issue_success_message": "您的问题已成功提交，感谢您的反馈！",
        "report_issue_failure_title": "错误",
        "report_issue_failure_message": "提交失败，请检查您的网络连接或稍后再试。",
    },
    "zh_TW": {
        "initializing": "正在初始化...",
        "ready_notification": f"{APP_NAME} 已就緒",
        "ready_message": "模型加載成功，可以開始使用了",
        "trigger_ocr": "手動觸發截圖OCR",
        "tts_model": "TTS 模型",
        "language": "語言",
        "help": "快捷鍵幫助",
        "report_issue": "上報問題",
        "about": "關於",
        "exit": "退出",
        "copy_f4": "複製F4截圖命令",
        "copy_f1": "複製F1懸停命令",
        "open_shortcuts": "打開系統快捷鍵設定",
        "repair_shortcut": "重新綁定F4快捷鍵",
        "shortcut_fixed_notification": "快捷鍵已就緒",
        "shortcut_fixed_message": "F4 已綁定到 A.M.D-HELPER",
        "shortcut_failed_notification": "快捷鍵設定失敗",
        "shortcut_failed_message": "無法自動綁定 F4。請在系統快捷鍵設定裡把 F4 綁定到 /usr/share/a.m.d-helper/run.sh",
        "copy_startup": "複製自啟動命令",
        "open_startup": "打開自啟動設定",
        "tts_switched_notification": "TTS引擎已切換",
        "tts_switched_message": "當前引擎: {engine}",
        "lang_switched_notification": "語言已切換",
        "lang_switched_message": "語言已設定為繁體中文。",
        "command_copied_notification": "複製成功",
        "command_copied_message": "命令已複製到剪貼簿",
        "error_pyperclip_notification": "複製失敗",
        "error_pyperclip_message": "系統沒有可用的剪貼簿工具，請安裝 wl-clipboard（Wayland）或 xclip（X11）。",
        "error_open_settings_notification": "操作失敗",
        "error_open_settings_message": "無法自動打開系統設定，請手動操作。",
        "settings_opened_message": "已打開系統設定。請進入鍵盤，再點查看及自訂快速鍵。",
        "about_window_title": f"關於 {APP_NAME}",
        "about_version": f"版本: {VERSION}",
        "about_contact": f"聯繫: {CONTACT_EMAIL}",
        "report_issue_window_title": "上報問題",
        "report_issue_description": "請描述您遇到的問題:",
        "report_issue_log_label": "以下日誌將隨報告一同發送:",
        "report_issue_submit": "提交",
        "report_issue_cancel": "取消",
        "report_issue_success_title": "成功",
        "report_issue_success_message": "您的問題已成功提交，感謝您的反饋！",
        "report_issue_failure_title": "錯誤",
        "report_issue_failure_message": "提交失敗，請檢查您的網絡連接或稍後再試。",
    }
}
CURRENT_LANG = "en"

def get_language_setting():
    """获取系统语言并映射到支持的语言"""
    try:
        lang, _ = locale.getlocale()
        if not lang:
            lang = os.environ.get("LANG", "en_US.UTF-8")
    except Exception:
        lang = "en_US.UTF-8"
    
    if lang.startswith("zh_CN"):
        return "zh_CN"
    if lang.startswith("zh_TW") or lang.startswith("zh_HK"):
        return "zh_TW"
    return "en"

def _(key):
    """翻译函数"""
    return TRANSLATIONS.get(CURRENT_LANG, TRANSLATIONS["en"]).get(key, key)

# --- D-Bus 服务 ---
class AmdHelperService(ServiceInterface):
    def __init__(self, processor):
        super().__init__(DBUS_INTERFACE_NAME)
        self.processor = processor

    @method()
    def trigger_ocr(self):
        print("D-Bus: 收到 trigger_ocr 请求")
        threading.Thread(target=self.processor.run_full_process, daemon=True).start()

# --- 配置读写 ---
def get_full_config():
    """
    获取完整的配置。
    如果用户配置不存在，则从默认位置复制一份新的。
    增加了详细的日志记录和更强的鲁棒性。
    """
    # 明确定义所有相关路径
    script_dir = os.path.dirname(os.path.abspath(__file__))
    default_config_path = os.path.join(script_dir, "config.json")
    user_config_dir = os.path.expanduser("~/.config/a.m.d-helper")
    user_config_path = os.path.join(user_config_dir, "config.json")

    # 核心逻辑：检查用户配置文件是否存在
    if not os.path.exists(user_config_path):
        print(f"ℹ️ 用户配置文件 '{user_config_path}' 不存在，将尝试创建。")
        try:
            os.makedirs(user_config_dir, exist_ok=True)
            # 检查默认配置文件是否存在，以便复制
            if os.path.exists(default_config_path):
                shutil.copy2(default_config_path, user_config_path)
                print(f"✅ 已成功从 '{default_config_path}' 复制并创建了新的用户配置文件。")
            else:
                # 如果默认文件也找不到，就地创建一个基础配置
                print(f"⚠️ 警告: 默认配置文件 '{default_config_path}' 未找到。将创建一个基础配置文件。")
                fallback_config = {"tts_model": "piper", "language": get_language_setting()}
                with open(user_config_path, "w", encoding="utf-8") as f:
                    json.dump(fallback_config, f, indent=4)
                return fallback_config
        except Exception as e:
            # 如果在创建过程中出现任何权限或IO错误
            print(f"❌ 创建或复制用户配置文件时出错: {e}")
            print("将回退到内存中的临时默认配置。设置将不会被保存。")
            return {"tts_model": "piper", "language": get_language_setting()}

    # 如果文件存在，则读取它
    try:
        with open(user_config_path, "r", encoding="utf-8") as f:
            config = json.load(f)
            print(f"ℹ️ 成功从 '{user_config_path}' 加载配置。")
            return config
    except (FileNotFoundError, json.JSONDecodeError) as e:
        # 如果文件在检查后被删除，或内容损坏
        print(f"❌ 读取用户配置文件 '{user_config_path}' 失败: {e}。将使用内存中的默认配置。")
        return {"tts_model": "piper", "language": get_language_setting()}

def write_config(config):
    """
    将配置写入用户配置文件。
    此函数现在是独立的，并且路径是硬编码的，以确保写入正确的位置。
    """
    user_config_dir = os.path.expanduser("~/.config/a.m.d-helper")
    user_config_path = os.path.join(user_config_dir, "config.json")
    
    try:
        print(f"ℹ️ 准备写入配置文件到: {user_config_path}")
        os.makedirs(user_config_dir, exist_ok=True)
        with open(user_config_path, "w", encoding="utf-8") as f:
            json.dump(config, f, indent=4)
        print("✅ 配置文件写入成功。")
    except Exception as e:
        # 捕获所有可能的写入错误
        print(f"❌ 写入配置文件 '{user_config_path}' 失败: {e}")

# --- 快捷键帮助函数 ---
try:
    import pyperclip
    PYPERCLIP_AVAILABLE = True
except ImportError:
    PYPERCLIP_AVAILABLE = False


def copy_to_clipboard(text: str) -> bool:
    """把文本写入系统剪贴板（Wayland 优先 wl-copy，X11 用 xclip）。

    不能用 pyperclip：它内部的 wl-copy 调用会继承管道，
    在 Wayland 下 communicate() 永远不返回（托盘菜单直接卡死）。
    这里把子进程 stdout/stderr 指到 DEVNULL 并设超时，保证菜单不阻塞。
    """
    env = os.environ.copy()
    wayland = bool(env.get("WAYLAND_DISPLAY"))
    display = bool(env.get("DISPLAY"))

    candidates = []
    if wayland and shutil.which("wl-copy"):
        candidates.append(["wl-copy"])
    if display and shutil.which("xclip"):
        candidates.append(["xclip", "-selection", "clipboard"])
    if display and shutil.which("xsel"):
        candidates.append(["xsel", "-b", "-i"])
    if wayland and shutil.which("wl-copy") and ["wl-copy"] not in candidates:
        candidates.append(["wl-copy"])
    if shutil.which("xclip") and ["xclip", "-selection", "clipboard"] not in candidates:
        candidates.append(["xclip", "-selection", "clipboard"])

    payload = text.encode("utf-8")
    for cmd in candidates:
        proc = None
        try:
            proc = subprocess.Popen(
                cmd,
                stdin=subprocess.PIPE,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
            proc.communicate(input=payload, timeout=3)
            if proc.returncode == 0:
                return True
        except Exception as exc:  # noqa: BLE001
            logger.warning(f"剪贴板命令失败 {cmd}: {exc}")
            if proc is not None:
                try:
                    proc.kill()
                except Exception:  # noqa: BLE001
                    pass

    # 最后兜底：pyperclip（X11 下一般可用；Wayland 下可能阻塞，放到子线程里跑）
    if PYPERCLIP_AVAILABLE:
        try:
            result = {}

            def _do():
                try:
                    import pyperclip as _pc

                    _pc.copy(text)
                    result["ok"] = True
                except Exception:  # noqa: BLE001
                    result["ok"] = False

            th = threading.Thread(target=_do, daemon=True)
            th.start()
            th.join(2.0)
            return result.get("ok", False)
        except Exception:  # noqa: BLE001
            pass
    return False


def _child_gui_env():
    """给 gnome-control-center 等 GUI 子进程准备干净环境。

    托盘进程自己的 GDK_BACKEND 可能被设成 x11（pystray 需要 X11 托盘），
    子进程继承后会退化成 XWayland，在 Ubuntu 26.04 上报
    "Authorization required / Failed to open display" ——
    表现就是托盘「打开快捷键设置」点了没反应。
    """
    env = os.environ.copy()
    env.pop("GDK_BACKEND", None)
    uid = os.getuid()
    env.setdefault("XDG_RUNTIME_DIR", f"/run/user/{uid}")
    env.setdefault("DBUS_SESSION_BUS_ADDRESS", f"unix:path=/run/user/{uid}/bus")
    if not env.get("XAUTHORITY"):
        import glob as _glob

        cands = sorted(_glob.glob(f"/run/user/{uid}/.mutter-Xwaylandauth.*"))
        if cands:
            env["XAUTHORITY"] = cands[-1]
    return env


def open_system_settings(kind="keyboard"):
    """打开系统设置面板（kind: keyboard=快捷键 / autostart=自启动）。"""
    desktop = os.environ.get("XDG_CURRENT_DESKTOP", "").lower()
    if kind == "autostart":
        candidates = [
            ["gnome-session-properties"],
            ["gnome-startup-applications"],
            ["kcmshell6", "kcm_autostart"],
            ["kcmshell5", "kcm_autostart"],
            ["xfce4-session-settings"],
        ]
    else:
        candidates = []
        if "gnome" in desktop or "ubuntu" in desktop or "unity" in desktop:
            candidates = [
                ["gnome-control-center", "keyboard"],
            ]
        elif "kde" in desktop or "plasma" in desktop:
            candidates = [["systemsettings5", "shortcuts"], ["systemsettings", "kcm_keys"]]
        elif "xfce" in desktop:
            candidates = [["xfce4-keyboard-settings"]]
        candidates += [
            ["gnome-control-center", "keyboard"],
            ["systemsettings5", "shortcuts"],
            ["xfce4-keyboard-settings"],
        ]

    env = _child_gui_env()
    for cmd in candidates:
        if not shutil.which(cmd[0]):
            continue
        try:
            proc = subprocess.Popen(
                cmd,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                env=env,
                start_new_session=True,
            )
            # GUI 程序会一直活着（或转发给已运行实例），不能等它退出
            try:
                proc.wait(timeout=3)
            except subprocess.TimeoutExpired:
                return True
            if proc.returncode == 0:
                return True
        except Exception as exc:  # noqa: BLE001
            logger.warning(f"打开设置失败 {cmd}: {exc}")
    return False

# --- 关于窗口 ---
# 延迟导入 tkinter 以避免在非GUI环境中出现问题
def show_about_window_tk():
    try:
        import tkinter as tk
        from tkinter import ttk
        from PIL import ImageTk
    except ImportError:
        print("错误: 关于窗口需要 tkinter 和 Pillow (PIL) 库。")
        return

    win = tk.Tk()
    win.title(_("about_window_title"))
    win.resizable(False, False)
    win.attributes('-topmost', True) # 保持窗口在最前
    win.configure(bg='#2b2b2b') # 设置窗口背景色

    # --- TTK 样式配置 ---
    style = ttk.Style(win)
    style.theme_use('clam') # 使用一个允许修改背景色的主题
    
    # 配置主框架样式
    style.configure('TFrame', background='#2b2b2b')
    
    # 配置标签样式
    style.configure('TLabel', background='#2b2b2b', foreground='white')
    
    # 配置粗体标签样式
    style.configure('Bold.TLabel', font=('Helvetica', 16, 'bold'))

    main_frame = ttk.Frame(win, padding="20", style='TFrame')
    main_frame.grid(row=0, column=0, sticky=(tk.W, tk.E, tk.N, tk.S))

    try:
        img = Image.open(ABOUT_ICON_PATH)
        img = img.resize((128, 128), Image.Resampling.LANCZOS)
        photo = ImageTk.PhotoImage(img)
        # 对于图片标签，背景色需要单独设置
        image_label = tk.Label(main_frame, image=photo, bg='#2b2b2b')
        image_label.image = photo  # Keep a reference!
        image_label.grid(row=0, column=0, rowspan=4, padx=(0, 20))
    except FileNotFoundError:
        print(f"警告: 未找到 'about.png' 文件 at {ABOUT_ICON_PATH}")

    ttk.Label(main_frame, text=APP_NAME, style='Bold.TLabel').grid(row=0, column=1, sticky=tk.W)
    ttk.Label(main_frame, text=_("about_version"), style='TLabel').grid(row=1, column=1, sticky=tk.W, pady=5)
    ttk.Label(main_frame, text=ABOUT_TEXT, style='TLabel').grid(row=2, column=1, sticky=tk.W, pady=5)
    ttk.Label(main_frame, text=_("about_contact"), style='TLabel').grid(row=3, column=1, sticky=tk.W, pady=5)

    # 将窗口居中
    win.update_idletasks()
    x = (win.winfo_screenwidth() - win.winfo_reqwidth()) // 2
    y = (win.winfo_screenheight() - win.winfo_reqheight()) // 2
    win.geometry(f"+{x}+{y}")

    win.mainloop()

# --- 邮件上报功能 ---
def send_report_via_worker(description, log_content):
    """通过Cloudflare Worker发送邮件报告，以保证凭证安全。"""
    try:
        url = "https://xmt.xmt.workers.dev/"
        
        # 准备要发送的数据
        data = {
            "to": "test@mail.430022.xyz",
            "subject": f"A.M.D-Helper Bug Report from User: {os.getlogin()}",
            "text": f"User Description:\n------------------\n{description}\n\nLog Content:\n------------------\n{log_content}"
        }
        
        print(f"🚀 准备通过Worker发送问题报告到: {url}")
        
        # 发送POST请求
        response = requests.post(url, json=data, timeout=20)
        
        # 检查响应
        if response.status_code == 200 and response.json().get("success"):
            print(f"✅ 报告发送成功: {response.text}")
            return True
        else:
            print(f"❌ 报告发送失败。状态码: {response.status_code}, 响应: {response.text}")
            return False
            
    except ImportError:
        print("❌ 错误: 'requests' 库未安装。请运行 'pip install requests'。")
        return False
    except Exception as e:
        print(f"❌ 发送报告时发生未知错误: {e}")
        return False

def collect_system_info():
    """收集系统环境信息"""
    import platform
    import subprocess
    
    info_lines = []
    info_lines.append("=== 系统环境信息 ===")
    info_lines.append(f"操作系统: {platform.system()} {platform.release()}")
    info_lines.append(f"发行版: {platform.platform()}")
    info_lines.append(f"Python 版本: {platform.python_version()}")
    info_lines.append(f"Python 路径: {sys.executable}")
    info_lines.append(f"架构: {platform.machine()}")
    
    # 桌面环境
    desktop = os.environ.get('XDG_CURRENT_DESKTOP', 'Unknown')
    session_type = os.environ.get('XDG_SESSION_TYPE', 'Unknown')
    info_lines.append(f"桌面环境: {desktop}")
    info_lines.append(f"会话类型: {session_type}")
    
    # 网络连接测试
    try:
        result = subprocess.run(['ping', '-c', '1', '-W', '2', 'speech.platform.bing.com'], 
                              capture_output=True, timeout=5)
        network_status = "可达" if result.returncode == 0 else "不可达"
    except:
        network_status = "测试失败"
    info_lines.append(f"Edge-TTS 服务器: {network_status}")
    
    # edge-tts 版本
    try:
        import edge_tts
        edge_version = getattr(edge_tts, '__version__', 'unknown')
        info_lines.append(f"edge-tts 版本: {edge_version}")
    except:
        info_lines.append("edge-tts 版本: 未安装")
    
    # 配置文件内容
    try:
        with open(USER_CONFIG_PATH, 'r') as f:
            config_content = f.read()
        info_lines.append(f"配置文件: {config_content}")
    except:
        info_lines.append("配置文件: 读取失败")
    
    info_lines.append("=" * 30)
    return "\n".join(info_lines)

def show_report_issue_window():
    """显示用于上报问题的Tkinter窗口，并应用深色主题。"""
    logger.debug("show_report_issue_window 被调用")
    try:
        import tkinter as tk
        from tkinter import ttk, scrolledtext, messagebox
        logger.debug("tkinter 导入成功")
    except ImportError as e:
        logger.error(f"错误: 上报问题功能需要 tkinter: {e}")
        return

    try:
        # 收集系统信息
        system_info = collect_system_info()
        
        log_file = "/tmp/a.m.d-helper-tray.log"
        log_content = "Log file not found."
        try:
            with open(log_file, "r", encoding="utf-8") as f:
                lines = f.readlines()
                log_content = "".join(lines[-100:])
            logger.debug(f"读取日志文件成功，共 {len(lines)} 行")
        except FileNotFoundError:
            logger.warning(f"日志文件 '{log_file}' 未找到。")
        
        # 合并系统信息和日志
        full_log = system_info + "\n\n=== 应用日志 ===\n" + log_content

        win = tk.Tk()
        win.title(_("report_issue_window_title"))
        win.configure(bg='#2b2b2b')
        logger.debug("Tk 窗口创建成功")

        style = ttk.Style(win)
        style.theme_use('clam')
        
        # --- 统一深色主题配置 ---
        bg_color = '#2b2b2b'
        fg_color = 'white'
        insert_bg = 'white' # 光标颜色
        style.configure('.', background=bg_color, foreground=fg_color)
        style.configure('TFrame', background=bg_color)
        style.configure('TLabel', background=bg_color, foreground=fg_color)
        style.configure('TButton', background='#3c3f41', foreground=fg_color, borderwidth=1, focusthickness=3, focuscolor=fg_color)
        style.map('TButton', background=[('active', '#4f5254')])

        main_frame = ttk.Frame(win, padding="10", style='TFrame')
        main_frame.pack(expand=True, fill=tk.BOTH)

        ttk.Label(main_frame, text=_("report_issue_description")).pack(anchor='w', pady=(0, 5))
        
        # 使用标准tk.Text并手动设置颜色，因为它比ttk.ScrolledText更容易定制
        user_text_frame = tk.Frame(main_frame, bd=1, relief=tk.SOLID, bg='#3c3f41')
        user_text = tk.Text(user_text_frame, height=5, width=60, bg=bg_color, fg=fg_color, insertbackground=insert_bg, relief=tk.FLAT, borderwidth=0)
        user_text_scroll = ttk.Scrollbar(user_text_frame, command=user_text.yview)
        user_text['yscrollcommand'] = user_text_scroll.set
        user_text_scroll.pack(side=tk.RIGHT, fill=tk.Y)
        user_text.pack(side=tk.LEFT, expand=True, fill=tk.BOTH)
        user_text_frame.pack(expand=True, fill=tk.BOTH, pady=5)
        user_text.focus()

        ttk.Label(main_frame, text=_("report_issue_log_label")).pack(anchor='w', pady=(10, 5))
        
        log_display_frame = tk.Frame(main_frame, bd=1, relief=tk.SOLID, bg='#3c3f41')
        log_display = tk.Text(log_display_frame, height=15, width=60, bg=bg_color, fg=fg_color, insertbackground=insert_bg, relief=tk.FLAT, borderwidth=0)
        log_display_scroll = ttk.Scrollbar(log_display_frame, command=log_display.yview)
        log_display['yscrollcommand'] = log_display_scroll.set
        log_display.insert(tk.INSERT, full_log)
        log_display.config(state='disabled')
        log_display_scroll.pack(side=tk.RIGHT, fill=tk.Y)
        log_display.pack(side=tk.LEFT, expand=True, fill=tk.BOTH)
        log_display_frame.pack(expand=True, fill=tk.BOTH, pady=5)

        def copy_log_action():
            """复制日志到剪贴板"""
            try:
                import pyperclip
                pyperclip.copy(full_log)
                copy_button.config(text="✓ 已复制")
                win.after(2000, lambda: copy_button.config(text="复制日志"))
            except Exception as e:
                logger.error(f"复制日志失败: {e}")

        def submit_action():
            description = user_text.get("1.0", tk.END).strip()
            def do_send():
                success = send_report_via_worker(description, full_log)
                win.after(0, lambda: on_send_complete(success))
            
            threading.Thread(target=do_send, daemon=True).start()
            submit_button.config(state="disabled", text="Sending...")

        def on_send_complete(success):
            if success:
                messagebox.showinfo(_("report_issue_success_title"), _("report_issue_success_message"))
                win.destroy()
            else:
                messagebox.showerror(_("report_issue_failure_title"), _("report_issue_failure_message"))
                submit_button.config(state="normal", text=_("report_issue_submit"))

        button_frame = ttk.Frame(main_frame, style='TFrame')
        button_frame.pack(fill=tk.X, pady=(10, 0))

        copy_button = ttk.Button(button_frame, text="复制日志", command=copy_log_action, style='TButton')
        copy_button.pack(side=tk.LEFT)

        submit_button = ttk.Button(button_frame, text=_("report_issue_submit"), command=submit_action, style='TButton')
        submit_button.pack(side=tk.RIGHT, padx=5)
        
        cancel_button = ttk.Button(button_frame, text=_("report_issue_cancel"), command=win.destroy, style='TButton')
        cancel_button.pack(side=tk.RIGHT)

        logger.debug("上报问题窗口准备显示，进入 mainloop")
        win.mainloop()
        logger.debug("上报问题窗口已关闭")
    except Exception as e:
        logger.error(f"show_report_issue_window 发生异常: {e}")
        logger.error(f"异常详情:\n{traceback.format_exc()}")





# --- 主应用类 ---
def cleanup_stuck_screenshot_processes():
    """清理旧版本 libshot 留下的 gnome-screenshot -a 僵尸进程。

    Ubuntu 26.04 / GNOME Shell 50 下 `gnome-screenshot -a` 会永久挂住，
    并且把它抓住的那一帧冻结住，之后所有截图都返回同一张旧图。
    只杀我们自己的临时文件（-f /tmp/tmp*.png）对应的进程，不碰用户手动开的。
    """
    killed = 0
    try:
        for pid_dir in os.listdir("/proc"):
            if not pid_dir.isdigit():
                continue
            try:
                with open(f"/proc/{pid_dir}/cmdline", "rb") as fh:
                    cmdline = fh.read().replace(b"\0", b" ").decode("utf-8", "replace")
            except OSError:
                continue
            if "gnome-screenshot" in cmdline and "-a" in cmdline and "/tmp/tmp" in cmdline:
                try:
                    os.kill(int(pid_dir), 9)
                    killed += 1
                except OSError:
                    pass
    except OSError:
        pass
    if killed:
        logger.warning(f"清理了 {killed} 个卡死的 gnome-screenshot -a 进程")


def ensure_shortcut_binding():
    """托盘启动时再确认一次 F4 绑定（deb 安装时没赶上图形会话也能自愈）。"""
    script = os.path.join(SCRIPT_DIR, "shortcut_setup.py")
    if not os.path.exists(script):
        return
    try:
        proc = subprocess.run(
            [sys.executable, script], capture_output=True, text=True, timeout=30
        )
        if proc.returncode == 0:
            logger.info("F4 快捷键自检通过")
        else:
            logger.warning(f"F4 快捷键自检失败：{(proc.stdout or '').strip()[-500:]}")
    except Exception as exc:  # noqa: BLE001
        logger.warning(f"F4 快捷键自检异常: {exc}")


class AppTray:
    def __init__(self):
        self.icon = None
        self.processor = None
        self.loop = None
        self.service = None
        self.dbus_bus = None
        self.exit_event = asyncio.Event()
        # 核心优化：添加配置缓存
        self.config = get_full_config()

    def _create_tray_image(self):
        image = Image.new('RGB', (64, 64), color='#2b2b2b')
        draw = ImageDraw.Draw(image)
        draw.rectangle([8, 8, 56, 56], fill='#0078d4')
        draw.text((16, 22), "AMD", fill='white') # Shorter text
        return image

    def _set_tts_engine_action(self, engine_name):
        if self.config.get("tts_model") != engine_name:
            self.config["tts_model"] = engine_name
            write_config(self.config)
            print(f"TTS 引擎已切换为: {engine_name}")
            
            if self.processor:
                # 直接将最新的配置传递给核心，避免文件读写延迟
                self.processor.reload_tts_engine(self.config)

            # self.icon.update_menu() # update_menu() 有时会导致闪烁或问题，重新构建更稳定
            self.icon.menu = self.build_menu()
            self.icon.notify(
                _("tts_switched_notification"),
                _("tts_switched_message").format(engine=engine_name.upper())
            )

    def set_language(self, lang_code):
        global CURRENT_LANG
        if CURRENT_LANG != lang_code:
            CURRENT_LANG = lang_code
            self.config["language"] = lang_code
            write_config(self.config)
            
            self.icon.menu = self.build_menu()
            self.icon.notify(
                _("lang_switched_notification"),
                _("lang_switched_message")
            )

    def _speak(self, text):
        """视障用户看不到通知气泡，关键操作必须给语音反馈。"""
        try:
            if self.processor is not None:
                self.processor.speak(text)
        except Exception as exc:  # noqa: BLE001
            logger.warning(f"语音提示失败: {exc}")

    def _copy_command_action(self, command_to_copy):
        ok = copy_to_clipboard(command_to_copy)
        if ok:
            self.icon.notify(
                _("command_copied_notification"),
                _("command_copied_message") + "\n" + command_to_copy,
            )
            self._speak(_("command_copied_message"))
        else:
            self.icon.notify(_("error_pyperclip_notification"), _("error_pyperclip_message"))
            self._speak(_("error_pyperclip_message"))

    def _open_settings(self, kind="keyboard"):
        def worker():
            if open_system_settings(kind):
                self._speak(_("settings_opened_message") if kind == "keyboard" else _("open_startup"))
            else:
                self.icon.notify(
                    _("error_open_settings_notification"),
                    _("error_open_settings_message"),
                )
                self._speak(_("error_open_settings_message"))

        # 别在托盘菜单线程里等 GUI 程序，避免菜单卡住
        threading.Thread(target=worker, daemon=True).start()

    def _repair_shortcut(self):
        """重新写入 F4 快捷键绑定（用户手动修复入口）。"""
        script = os.path.join(SCRIPT_DIR, "shortcut_setup.py")

        def worker():
            ok = False
            try:
                proc = subprocess.run(
                    [sys.executable, script], capture_output=True, text=True, timeout=30
                )
                ok = proc.returncode == 0
                if not ok:
                    logger.warning(f"快捷键修复失败: {proc.stdout}\n{proc.stderr}")
            except Exception as exc:  # noqa: BLE001
                logger.warning(f"快捷键修复异常: {exc}")
            if ok:
                self.icon.notify(_("shortcut_fixed_notification"), _("shortcut_fixed_message"))
                self._speak(_("shortcut_fixed_message"))
            else:
                self.icon.notify(_("shortcut_failed_notification"), _("shortcut_failed_message"))
                self._speak(_("shortcut_failed_message"))

        threading.Thread(target=worker, daemon=True).start()

    def show_about_window(self):
        # 在单独的线程中运行UI，以避免阻塞主事件循环
        threading.Thread(target=show_about_window_tk, daemon=True).start()

    def build_menu(self):
        # 复制给用户粘贴到「系统设置 → 键盘快捷键」的命令必须是 run.sh：
        # 直接复制 "python3 f4.py" 会用系统 python 跑，缺 dbus_next，粘进去按了没反应。
        f4_command = os.path.join(SCRIPT_DIR, "run.sh")
        f1_command = os.path.join(SCRIPT_DIR, "run_hover.sh")
        tray_command = f"bash {os.path.join(SCRIPT_DIR, 'tray.sh')}"

        return Menu(
            MenuItem(_('trigger_ocr'), lambda: self.service.trigger_ocr()),
            Menu.SEPARATOR,
            MenuItem(_('tts_model'), Menu(
                MenuItem('Edge TTS', lambda: self._set_tts_engine_action('edge'), checked=lambda item: self.config.get("tts_model") == 'edge', radio=True),
                MenuItem('Piper TTS', lambda: self._set_tts_engine_action('piper'), checked=lambda item: self.config.get("tts_model") == 'piper', radio=True)
            )),
            MenuItem(_('language'), Menu(
                MenuItem('English', lambda: self.set_language('en'), checked=lambda item: self.config.get("language") == 'en', radio=True),
                MenuItem('简体中文', lambda: self.set_language('zh_CN'), checked=lambda item: self.config.get("language") == 'zh_CN', radio=True),
                MenuItem('繁體中文', lambda: self.set_language('zh_TW'), checked=lambda item: self.config.get("language") == 'zh_TW', radio=True)
            )),
            MenuItem(_('help'), Menu(
                MenuItem(_('copy_f4'), lambda: self._copy_command_action(f4_command)),
                MenuItem(_('copy_f1'), lambda: self._copy_command_action(f1_command)),
                Menu.SEPARATOR,
                MenuItem(_('repair_shortcut'), self._repair_shortcut),
                MenuItem(_('open_shortcuts'), lambda: self._open_settings("keyboard")),
                Menu.SEPARATOR,
                MenuItem(_('copy_startup'), lambda: self._copy_command_action(tray_command)),
                MenuItem(_('open_startup'), lambda: self._open_settings("autostart"))
            )),
            MenuItem(_('report_issue'), lambda: threading.Thread(target=show_report_issue_window, daemon=True).start()),
            MenuItem(_('about'), self.show_about_window),
            Menu.SEPARATOR,
            MenuItem(_('exit'), self.on_quit)
        )

    def on_quit(self):
        print("正在退出...")
        if not self.exit_event.is_set():
            self.loop.call_soon_threadsafe(self.exit_event.set)

    async def main_async(self):
        global CURRENT_LANG
        config = get_full_config()
        CURRENT_LANG = config.get("language", get_language_setting())

        self.dbus_bus = await MessageBus(bus_type=BusType.SESSION).connect()
        
        try:
            await self.dbus_bus.request_name(DBUS_SERVICE_NAME, NameFlag.DO_NOT_QUEUE)
        except Exception:
            print(f"错误: 服务 '{DBUS_SERVICE_NAME}' 已在运行。正在退出。")
            return

        print("D-Bus服务名获取成功，应用为唯一实例。")

        # 启动自愈：清掉会把屏幕冻住的旧截图进程 + 确认 F4 绑定
        cleanup_stuck_screenshot_processes()
        threading.Thread(target=ensure_shortcut_binding, daemon=True).start()

        print("正在加载AI模型，请稍候...")
        self.processor = OcrAndTtsProcessor()
        print("模型加载完毕，服务准备就绪。")
        self.icon.notify(_("ready_notification"), _("ready_message"))

        self.service = AmdHelperService(self.processor)
        self.dbus_bus.export(DBUS_OBJECT_PATH, self.service)
        print(f"D-Bus服务已在 '{DBUS_OBJECT_PATH}' 发布。")

        self.loop = asyncio.get_running_loop()
        
        self.icon.menu = self.build_menu()
        
        tray_thread = threading.Thread(target=self.icon.run, daemon=True)
        tray_thread.start()

        await self.exit_event.wait()
        
        print("主事件循环收到退出信号，开始清理...")
        self.dbus_bus.disconnect()
        self.icon.stop()
        self.processor.cleanup()
        print("清理完成。")

    def run(self):
        global CURRENT_LANG
        CURRENT_LANG = get_full_config().get("language", get_language_setting())

        image = self._create_tray_image()
        self.icon = pystray.Icon(APP_NAME.lower().replace("-", "_"), image, f"{APP_NAME} 服务", menu=Menu(MenuItem(_("initializing"), None)))

        self.loop = asyncio.new_event_loop()
        asyncio.set_event_loop(self.loop)

        def signal_handler(sig, frame):
            print(f"捕获到信号 {sig}, 正在启动关闭流程...")
            self.on_quit()

        signal.signal(signal.SIGINT, signal_handler)
        signal.signal(signal.SIGTERM, signal_handler)

        try:
            self.loop.run_until_complete(self.main_async())
        except Exception as e:
            print(f"主循环中发生未捕获的异常: {e}")
        finally:
            print("开始最终的事件循环清理...")
            tasks = [t for t in asyncio.all_tasks(loop=self.loop) if t is not asyncio.current_task()]
            if tasks:
                [task.cancel() for task in tasks]
                self.loop.run_until_complete(asyncio.gather(*tasks, return_exceptions=True))
            self.loop.close()
            print("程序已干净地退出。")

if __name__ == '__main__':
    app = AppTray()
    app.run()