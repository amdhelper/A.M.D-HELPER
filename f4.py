#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import asyncio
import sys
from dbus_next.aio import MessageBus
from dbus_next.constants import BusType

# D-Bus 配置，必须与 tray.py 中的定义完全一致
DBUS_SERVICE_NAME = "org.amd_helper.Service"
DBUS_INTERFACE_NAME = "org.amd_helper.Interface"
DBUS_OBJECT_PATH = "/org/amd_helper/Main"

async def main():
    """连接到D-Bus服务并调用方法。"""
    try:
        bus = await MessageBus(bus_type=BusType.SESSION).connect()
        
        # 1. 手动进行“内省”，获取远程服务的XML定义
        introspection = await bus.introspect(DBUS_SERVICE_NAME, DBUS_OBJECT_PATH)
        
        # 2. 使用内省数据来获取远程对象的代理
        proxy = bus.get_proxy_object(DBUS_SERVICE_NAME, DBUS_OBJECT_PATH, introspection)
        
        # 3. 从代理中获取我们感兴趣的接口
        interface = proxy.get_interface(DBUS_INTERFACE_NAME)
        
        # 4. 直接调用方法 (方法名前加上 'call_')
        print(f"正在调用 D-Bus 方法: {DBUS_INTERFACE_NAME}.trigger_ocr")
        await interface.call_trigger_ocr()
        print("方法调用成功，截图识别流程已在后台触发。")

    except Exception as e:
        print(f"错误：无法连接到 A.M.D-HELPER 服务或调用方法。", file=sys.stderr)
        print(f"请确保 A.M.D-HELPER 托盘应用 (tray.py) 正在运行。", file=sys.stderr)
        print(f"详细错误: {e}", file=sys.stderr)
        sys.exit(1)

if __name__ == "__main__":
    asyncio.run(main())