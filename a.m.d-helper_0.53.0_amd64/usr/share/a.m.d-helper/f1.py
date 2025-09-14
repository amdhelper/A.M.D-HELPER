# f1.py (Final Architecture v6 - ydotool + evdev thread)
# -*- coding: utf-8 -*-

"""
辅助工具 f1.py：通过鼠标悬停朗读屏幕上的文本，并提供视觉光晕效果。

最终架构:
- 主线程通过轮询 `ydotool` 获取鼠标坐标。
- 一个独立的后台线程使用 `evdev` 监听ESC按键。
- 使用 PyQt6 原生的信号/槽机制进行安全的跨线程通信。

运行前置条件:
1.  安装 ydotool: `sudo apt-get install ydotool`
2.  将用户加入input组: `sudo usermod -aG input $USER` (然后需重新登录)
3.  在一个终端中启动ydotool服务: `sudo ydotoold --socket-path=/var/run/ydotoold.socket --socket-own=$USER:$USER`
4.  在运行脚本的终端中设置环境变量: `export YDOTOOL_SOCKET=/var/run/ydotoold.socket`

运行方式:
- 以普通用户身份运行: `python3 f1.py` (无需 sudo)

依赖库:
pip install PyQt6 qasync evdev jeepney edge-tts sounddevice pyttsx3 python-dateutil
"""

import asyncio
import json
import os
import re
import sys
import tempfile
import time
import threading
from pathlib import Path
from dateutil import parser as date_parser

import evdev
import pyttsx3
import qasync
import sounddevice as sd
from PyQt6.QtCore import Qt, QRect, QObject, pyqtSignal
from PyQt6.QtGui import QPainter, QColor, QBrush, QPainterPath
from PyQt6.QtWidgets import QApplication, QWidget
from jeepney import new_method_call
from jeepney.io.asyncio import open_dbus_connection

# --- 配置 ---
HALO_BASE_COLOR = QColor(10, 132, 255, 70)
HALO_PROGRESS_COLOR = QColor(255, 214, 10, 90)
POLL_INTERVAL = 0.05 # 鼠标轮询间隔 (秒)
TTS_VOICE = "zh-CN-XiaoxiaoNeural"

# --- D-Bus AT-SPI 定义 ---
AT_SPI_BUS_NAME = "org.a11y.Bus"
AT_SPI_PATH = "/org/a11y/bus"
AT_SPI_ROOT_IFACE = "org.a11y.atspi.Registry"
COMPONENT_IFACE = "org.a11y.atspi.Component"
TEXT_IFACE = "org.a11y.atspi.Text"

# --- Helper Functions & Classes ---
def _get_config():
    try:
        with open("config.json", "r", encoding="utf-8") as f: return json.load(f)
    except (FileNotFoundError, json.JSONDecodeError): return {}

class LocalPiperTtsEngine:
    async def synthesize(self, text: str, output_path: str, lang: str = 'zh'):
        config = _get_config()
        piper_models = config.get("piper_models", {})
        model_key = lang if lang in piper_models else config.get("active_piper_model", "zh")
        model_path = piper_models.get(model_key)
        if not model_path or not os.path.exists(model_path):
            raise FileNotFoundError(f"Piper model for key '{model_key}' not found.")
        command = ["piper", "--model", model_path, "--output_file", output_path]
        process = await asyncio.create_subprocess_exec(
            *command, stdin=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.PIPE)
        _, stderr = await process.communicate(input=text.encode('utf-8'))
        if process.returncode != 0:
            raise RuntimeError(f"Piper-TTS failed: {stderr.decode()}")

class HaloWindow(QWidget):
    def __init__(self):
        super().__init__()
        self.setWindowFlags(
            Qt.WindowType.FramelessWindowHint | Qt.WindowType.WindowStaysOnTopHint | Qt.WindowType.Tool)
        self.setAttribute(Qt.WidgetAttribute.WA_TranslucentBackground)
        self.setAttribute(Qt.WidgetAttribute.WA_ShowWithoutActivating)
        self._bounds = QRect()
        self._progress = 0.0

    def paintEvent(self, event):
        painter = QPainter(self)
        painter.setRenderHint(QPainter.RenderHint.Antialiasing)
        path = QPainterPath()
        path.addRoundedRect(self.rect(), 10, 10)
        painter.fillPath(path, QBrush(HALO_BASE_COLOR))
        if self._progress > 0:
            progress_rect = QRect(0, 0, int(self.width() * self._progress), self.height())
            progress_path = QPainterPath()
            progress_path.addRoundedRect(progress_rect, 10, 10)
            painter.fillPath(progress_path, QBrush(HALO_PROGRESS_COLOR))

    def update_geometry(self, bounds, progress=0.0):
        self._bounds = QRect(*bounds) if bounds else QRect()
        self._progress = progress
        if not self._bounds.isEmpty(): self.setGeometry(self._bounds); self.show()
        else: self.hide()
        self.update()

    def set_progress(self, progress):
        self._progress = max(0.0, min(1.0, progress)); self.update()

class Communicator(QObject):
    esc_pressed = pyqtSignal()

class HoverReader:
    def __init__(self, loop):
        self.loop = loop
        self.halo = HaloWindow()
        self.communicator = Communicator()
        self.dbus_conn = None
        self.tts_task = None
        self.last_accessible_path = None
        self.last_x, self.last_y = -1, -1
        self.keyboard_device = None
        self.listener_thread = None
        self.is_running = False

    async def initialize(self):
        print("Initializing...")
        if os.environ.get("YDOTOOL_SOCKET") is None:
            print("❌ Critical: YDOTOOL_SOCKET environment variable is not set.", file=sys.stderr)
            return False
        print("✅ YDOTOOL_SOCKET found.")

        try: self.dbus_conn = await open_dbus_connection()
        except Exception as e: print(f"❌ Critical: D-Bus connection failed: {e}", file=sys.stderr); return False
        print("✅ D-Bus connection successful.")

        try: self._find_keyboard_device()
        except Exception as e: 
            print(f"❌ Critical: Error finding keyboard device: {e}", file=sys.stderr)
            print("   Ensure user is in 'input' group and has re-logged in.", file=sys.stderr); return False

        if not self.keyboard_device:
            print("❌ Critical: Could not find keyboard device.", file=sys.stderr); return False
        print(f"✅ Keyboard found: {self.keyboard_device.name}")
        
        self.communicator.esc_pressed.connect(self.on_esc_pressed)
        return True

    def _find_keyboard_device(self):
        devices = [evdev.InputDevice(path) for path in evdev.list_devices()]
        for device in devices:
            if "virtual" in device.name.lower():
                continue # Ignore virtual devices
            caps = device.capabilities(verbose=False)
            if evdev.ecodes.EV_KEY in caps and evdev.ecodes.KEY_ESC in caps[evdev.ecodes.EV_KEY]:
                self.keyboard_device = device
                return

    def _keyboard_listener_thread_target(self):
        try:
            for event in self.keyboard_device.read_loop():
                if not self.is_running: break
                if event.type == evdev.ecodes.EV_KEY and event.code == evdev.ecodes.KEY_ESC and event.value == 1:
                    self.communicator.esc_pressed.emit()
                    break
        except (IOError, OSError) as e:
            print(f"Keyboard listener thread error: {e}", file=sys.stderr)

    async def poll_mouse_location(self):
        """Periodically polls mouse location using ydotool."""
        while self.is_running:
            try:
                proc = await asyncio.create_subprocess_exec(
                    'ydotool', 'getmouselocation', stdout=asyncio.subprocess.PIPE)
                stdout, _ = await proc.communicate()
                output = stdout.decode()
                match = re.search(r"X: (\\d+) Y: (\\d+)", output)
                if match:
                    x, y = int(match.group(1)), int(match.group(2))
                    if x != self.last_x or y != self.last_y:
                        self.last_x, self.last_y = x, y
                        await self.process_hover(x, y)
            except FileNotFoundError:
                print("❌ Critical: 'ydotool' command not found. Is it installed and in your PATH?", file=sys.stderr)
                self.communicator.esc_pressed.emit()
                break
            except Exception as e:
                print(f"Mouse polling error: {e}", file=sys.stderr)
            
            await asyncio.sleep(POLL_INTERVAL)

    def start_listeners(self):
        self.is_running = True
        # Start keyboard listener in a thread
        self.listener_thread = threading.Thread(target=self._keyboard_listener_thread_target, daemon=True)
        self.listener_thread.start()
        print("✅ Keyboard listener thread started.")
        # Start mouse poller as an asyncio task
        asyncio.create_task(self.poll_mouse_location())
        print("✅ Mouse polling started.")

    def stop_listeners(self):
        self.is_running = False
        print("✅ Listeners stopped.")

    def on_esc_pressed(self):
        print("ESC pressed, shutting down...")
        if self.tts_task and not self.tts_task.done(): self.tts_task.cancel()
        QApplication.instance().quit()

    async def process_hover(self, x, y):
        try: name, path = await self._get_accessible_at_point(x, y)
        except Exception: name, path = None, None
        if path and path == self.last_accessible_path: return
        self.last_accessible_path = path
        if self.tts_task and not self.tts_task.done(): self.tts_task.cancel()
        if not name or not path: self.halo.update_geometry(None); return
        try:
            text = await self._get_text(name, path)
            bounds = await self._get_component_extents(name, path)
        except Exception: text, bounds = None, None
        if text and bounds and any(bounds):
            self.halo.update_geometry(bounds)
            self.tts_task = asyncio.create_task(self._tts_worker(text))
        else: self.halo.update_geometry(None)

    async def _get_accessible_at_point(self, x, y):
        msg = new_method_call(AT_SPI_BUS_NAME, AT_SPI_PATH, AT_SPI_ROOT_IFACE, 'GetAccessibleAt')
        msg.body = (int(x), int(y)); reply = await self.dbus_conn.send_and_get_reply(msg); return reply.body[0]

    async def _get_component_extents(self, name, path):
        msg = new_method_call(name, path, COMPONENT_IFACE, 'GetExtents')
        msg.body = (0,); reply = await self.dbus_conn.send_and_get_reply(msg); return reply.body[0]

    async def _get_text(self, name, path):
        msg_len = new_method_call(name, path, TEXT_IFACE, 'get_CharacterCount')
        reply_len = await self.dbus_conn.send_and_get_reply(msg_len)
        char_count = reply_len.body[0]
        if char_count == 0: return ""
        msg_text = new_method_call(name, path, TEXT_IFACE, 'GetText')
        msg_text.body = (0, char_count); reply_text = await self.dbus_conn.send_and_get_reply(msg_text); return reply_text.body[0]

    async def _tts_worker(self, text):
        try: await self._tts_online_edge_tts(text)
        except asyncio.CancelledError: pass
        except Exception as e:
            print(f"L1: Online TTS failed: {e}. Trying L2: Piper.")
            try: await self._tts_offline_piper(text)
            except asyncio.CancelledError: pass
            except Exception as e2:
                print(f"L2: Piper TTS failed: {e2}. Trying L3: pyttsx3.")
                try: await self._tts_offline_pyttsx3(text)
                except Exception as e3: print(f"L3: pyttsx3 also failed: {e3}")
        finally:
            if not asyncio.current_task().cancelled():
                await asyncio.sleep(0.2); self.last_accessible_path = None; self.halo.update_geometry(None)

    def _parse_srt(self, srt_content):
        entries = []
        for match in re.finditer(r'\d+\n(\d{2}:\d{2}:\d{2},\d{3}) --> (\d{2}:\d{2}:\d{2},\d{3})\n', srt_content):
            start = (date_parser.parse(match.group(1)) - date_parser.parse("00:00:00,000")).total_seconds()
            end = (date_parser.parse(match.group(2)) - date_parser.parse("00:00:00,000")).total_seconds()
            entries.append({'start': start, 'end': end})
        return entries

    async def _tts_online_edge_tts(self, text):
        from edge_tts import Communicate
        with tempfile.NamedTemporaryFile(delete=False, suffix=".mp3") as audio_f, \
             tempfile.NamedTemporaryFile(delete=False, mode="w+", suffix=".srt") as srt_f:
            audio_fname, srt_fname = audio_f.name, srt_f.name
        communicate = Communicate(text, TTS_VOICE)
        await communicate.save(audio_fname, subtitles_file=srt_fname)
        timestamps = self._parse_srt(Path(srt_fname).read_text())
        if not timestamps: return
        total_duration = timestamps[-1]['end']
        data, fs = sd.read(audio_fname, dtype='float32')
        sd.play(data, fs); start_time = time.time()
        while self.is_running:
            await asyncio.sleep(0.05); elapsed = time.time() - start_time
            if elapsed > total_duration + 0.5: break
            self.halo.set_progress(elapsed / total_duration)
        sd.stop(); Path(audio_fname).unlink(); Path(srt_fname).unlink()

    async def _tts_offline_piper(self, text):
        self.halo.set_progress(1.0)
        engine = LocalPiperTtsEngine()
        with tempfile.NamedTemporaryFile(delete=False, suffix=".wav") as audio_f: audio_fname = audio_f.name
        await engine.synthesize(text, audio_fname)
        data, fs = sd.read(audio_fname, dtype='float32')
        await self.loop.run_in_executor(None, sd.play, data, fs)
        await self.loop.run_in_executor(None, sd.wait)
        Path(audio_fname).unlink()

    async def _tts_offline_pyttsx3(self, text):
        self.halo.set_progress(1.0)
        engine = pyttsx3.init()
        engine.say(text)
        await self.loop.run_in_executor(None, engine.runAndWait)

async def main():
    app = QApplication(sys.argv)
    loop = qasync.QEventLoop(app)
    asyncio.set_event_loop(loop)

    reader = HoverReader(loop)
    if not await reader.initialize():
        return

    reader.start_listeners()
    app.aboutToQuit.connect(reader.stop_listeners)

    print("✅ F1 Hover Reader is running. Move mouse to read text. Press ESC to exit.")

    with loop:
        loop.run_forever()

if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        print("\nExiting...")
