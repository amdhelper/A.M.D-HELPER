#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
截图入口。

真实工作交给同目录下的 capture.py（独立进程）：
  * 先用 xdg-desktop-portal 抓一张全屏冻结图
  * 再显示全屏选区覆盖层（鼠标十字准星，拖动圈选）
  * 松开后裁切保存，返回文件路径

为什么不在这里直接开 GTK 窗口：
  tray.py 主进程已经在跑 pystray/GTK 事件循环，同进程再开一个 Gtk.main()
  会和托盘菜单互相干扰；独立进程还能保证截图失败/卡死时不影响托盘服务。
"""

import os
import subprocess
import sys
import tempfile
import time

APP_DIR = os.path.dirname(os.path.abspath(__file__))
CAPTURE_SCRIPT = os.path.join(APP_DIR, "capture.py")
CAPTURE_TIMEOUT = 240  # 秒；用户圈选最多等这么久


class CaptureCancelled(Exception):
    """用户按 Esc / 右键主动取消。"""


class CaptureError(Exception):
    """截图流程本身失败（拿不到屏幕、模块缺失等）。"""


class Screenshotter:
    """调用 capture.py 完成“抓全屏 + 圈选 + 裁切”。"""

    def __init__(self):
        pass

    def _child_env(self):
        env = os.environ.copy()
        # Wayland 会话下不要强制 X11 后端（会退化成 XWayland，拿不到真实画面）
        if env.get("XDG_SESSION_TYPE") == "wayland" or env.get("WAYLAND_DISPLAY"):
            env.pop("GDK_BACKEND", None)
        env.setdefault("PYTHONNOUSERSITE", "1")
        return env

    def take_screenshot(self) -> str:
        """
        执行交互式截图，返回裁切后图片的绝对路径。
        用户取消抛 CaptureCancelled，失败抛 CaptureError。
        """
        if not os.path.exists(CAPTURE_SCRIPT):
            raise CaptureError(f"找不到截图模块: {CAPTURE_SCRIPT}")

        fd, out_path = tempfile.mkstemp(suffix=".png", prefix="amdhelper_capture_")
        os.close(fd)
        try:
            os.unlink(out_path)
        except OSError:
            pass

        cmd = [
            sys.executable,
            CAPTURE_SCRIPT,
            "--out",
            out_path,
            "--timeout",
            str(CAPTURE_TIMEOUT),
        ]
        print("🖼️  请选择截图区域...")
        started = time.time()
        try:
            proc = subprocess.run(
                cmd,
                capture_output=True,
                text=True,
                timeout=CAPTURE_TIMEOUT + 60,
                env=self._child_env(),
                cwd=APP_DIR,
            )
        except subprocess.TimeoutExpired as exc:
            raise CaptureError("截图超时") from exc
        except Exception as exc:  # noqa: BLE001
            raise CaptureError(f"启动截图进程失败: {exc}") from exc

        stderr_tail = (proc.stderr or "").strip().splitlines()[-6:]
        for line in stderr_tail:
            print(line)

        if proc.returncode == 2:
            print("⏹️  用户取消了截图")
            raise CaptureCancelled()

        if proc.returncode != 0 or not os.path.exists(out_path) or os.path.getsize(out_path) == 0:
            if os.path.exists(out_path):
                os.remove(out_path)
            raise CaptureError(f"截图失败 (exit={proc.returncode}) {(proc.stdout or '').strip()}")

        print(f"✅ 截图成功 ({time.time() - started:.1f}s): {out_path}")
        return out_path


if __name__ == "__main__":
    screenshotter = Screenshotter()
    try:
        path = screenshotter.take_screenshot()
        print(f"✅ 测试成功，截图路径: {path}")
    except CaptureCancelled:
        print("⏹️  用户取消了截图")
    except CaptureError as exc:
        print(f"❌ 截图失败: {exc}")
