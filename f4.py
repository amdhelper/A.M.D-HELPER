#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""F4 快捷键入口：把「截图+OCR+朗读」的活交给常驻托盘进程。

设计要点（视障用户可用性）：
  * F4 只负责触发，真正的截图/OCR/朗读都在 tray 后台做；
  * 如果托盘没在跑（刚开机、上次崩了、被 kill 了），这里会自动把托盘拉起来
    再触发，用户不需要知道「服务」这个概念，也不会出现「按了没反应」；
  * 任何失败都用 notify-send 弹通知，避免静默失败。
"""

import asyncio
import os
import shutil
import subprocess
import sys

from dbus_next.aio import MessageBus
from dbus_next.constants import BusType

# D-Bus 配置，必须与 tray.py 中的定义完全一致
DBUS_SERVICE_NAME = "org.amd_helper.Service"
DBUS_INTERFACE_NAME = "org.amd_helper.Interface"
DBUS_OBJECT_PATH = "/org/amd_helper/Main"

APP_DIR = os.path.dirname(os.path.abspath(__file__))


def notify(title, body):
    try:
        if shutil.which("notify-send"):
            subprocess.Popen(
                ["notify-send", "-a", "A.M.D-HELPER", title, body],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
    except Exception:  # noqa: BLE001
        pass


def start_tray():
    """后台拉起托盘服务（模型加载要十几秒）。"""
    tray_sh = os.path.join(APP_DIR, "tray.sh")
    if not os.path.exists(tray_sh):
        return False
    try:
        subprocess.Popen(
            ["bash", tray_sh],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
            cwd=APP_DIR,
        )
        return True
    except Exception:  # noqa: BLE001
        return False


async def wait_service(bus, timeout=40.0):
    waited = 0.0
    while waited < timeout:
        try:
            introspection = await bus.introspect(DBUS_SERVICE_NAME, DBUS_OBJECT_PATH)
            return bus.get_proxy_object(DBUS_SERVICE_NAME, DBUS_OBJECT_PATH, introspection)
        except Exception:  # noqa: BLE001
            await asyncio.sleep(0.5)
            waited += 0.5
    return None


async def main():
    try:
        bus = await MessageBus(bus_type=BusType.SESSION).connect()
    except Exception as exc:  # noqa: BLE001
        notify("A.M.D-HELPER 启动失败", f"连不上用户 D-Bus 会话: {exc}")
        return 1

    proxy = await wait_service(bus, timeout=0.6)
    if proxy is None:
        # 托盘没在跑 → 自动拉起，等它就绪后再触发
        if start_tray():
            notify("A.M.D-HELPER", "正在启动识别服务，请稍候…")
            proxy = await wait_service(bus, timeout=60.0)
        if proxy is None:
            notify(
                "A.M.D-HELPER 未启动",
                f"识别服务启动失败。请在终端执行: bash {APP_DIR}/tray.sh，然后查看 /tmp/a.m.d-helper-tray.log",
            )
            print("错误：无法连接到 A.M.D-HELPER 服务。", file=sys.stderr)
            return 1

    try:
        interface = proxy.get_interface(DBUS_INTERFACE_NAME)
        await interface.call_trigger_ocr()
        return 0
    except Exception as exc:  # noqa: BLE001
        notify("A.M.D-HELPER 出错", f"触发识别失败: {exc}")
        print(f"错误：调用 trigger_ocr 失败: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(asyncio.run(main()))
