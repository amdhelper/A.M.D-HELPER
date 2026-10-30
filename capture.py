#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
A.M.D-HELPER 截图模块（Ubuntu 22.04 ~ 26.04 / X11 + Wayland 通用）

主路径：xdg-desktop-portal 的「交互式截图」= 直接弹出 GNOME 系统自带的选区界面
（就是按 PrintScreen 看到的那个十字准星 + 拖框界面），选完由系统裁好交给我们。
这比自己画覆盖层可靠得多，也不需要我们自己处理鼠标事件。

关键坑（2026-10 Ubuntu 26.04 实测）：
  * 调 portal 时必须带一个真实的 parent_window（父窗口 id），
    传空字符串时 GNOME 的截图窗口"Failed to associate portal window"，
    界面不会出现，还会把整个桌面卡在截图模式里（鼠标被抢、画面冻结）。
  * org.gnome.Shell.Screenshot 的 SelectArea / InteractiveScreenshot
    对普通进程一律 AccessDenied，只能用 portal。

兜底：portal 不可用时退回「先抓全屏 + 自绘选区覆盖层」。

退出码：0 成功，2 用户取消，1 失败
输出：成功时 stdout 打印 "OK <path> <w>x<h>"
"""

import argparse
import glob
import os
import subprocess
import sys
import tempfile
import time
import urllib.parse
import uuid

from PIL import Image

APP_NAME = "A.M.D-HELPER"


def _log(msg):
    print(f"[capture] {msg}", file=sys.stderr, flush=True)


def _ensure_xauthority():
    """在 Wayland 会话里补上 Xwayland 的授权文件，否则建的 X11 父窗口连不上。"""
    if os.environ.get("XAUTHORITY") and os.path.exists(os.environ["XAUTHORITY"]):
        return
    uid = os.getuid()
    for pattern in (f"/run/user/{uid}/.mutter-Xwaylandauth.*", f"/run/user/{uid}/.Xauthority"):
        matches = sorted(glob.glob(pattern))
        if matches:
            os.environ["XAUTHORITY"] = matches[-1]
            return


# --------------------------------------------------------------------------
# 主路径：portal 交互式截图（系统原生选区界面）
# --------------------------------------------------------------------------


def _make_parent_window():
    """建一个 1x1 的隐藏 X11 窗口，只为了拿到 parent_window 句柄。

    注意：GDK_BACKEND 必须在 import Gtk 之前设置，否则 GTK 会先选定 Wayland
    后端，窗口拿不到 X11 xid（实测 GdkWaylandWindow）。
    """
    _ensure_xauthority()
    os.environ["GDK_BACKEND"] = "x11"

    import gi

    gi.require_version("Gtk", "3.0")
    gi.require_version("Gdk", "3.0")
    gi.require_version("GdkX11", "3.0")
    from gi.repository import GdkX11, Gtk

    win = Gtk.Window()
    win.set_decorated(False)
    win.set_default_size(1, 1)
    win.move(-100, -100)
    win.show_all()
    for _ in range(50):
        while Gtk.events_pending():
            Gtk.main_iteration_do(False)
        if win.get_window() is not None:
            break
        time.sleep(0.02)

    gdk_win = win.get_window()
    if gdk_win is None:
        _log("父窗口未 realize")
        return None, None
    try:
        xid = GdkX11.X11Window.get_xid(gdk_win)
    except Exception as exc:  # noqa: BLE001
        _log(f"取不到 X11 xid（{exc}），当前后端不是 X11")
        return None, None
    return win, (f"x11:{xid}" if xid else "")


def capture_interactive_portal(timeout=180):
    """调 portal 交互式截图，返回 (PIL.Image, 源文件路径)。用户取消抛 _Cancelled。"""
    import gi

    gi.require_version("Gtk", "3.0")
    from gi.repository import Gio, GLib

    parent_win, parent_id = _make_parent_window()
    if not parent_id:
        raise RuntimeError("无法创建 X11 父窗口，portal 交互式截图不可用")

    token = "amdhelper_" + uuid.uuid4().hex
    bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
    sender = bus.get_unique_name()[1:].replace(".", "_")
    path = f"/org/freedesktop/portal/desktop/request/{sender}/{token}"

    loop = GLib.MainLoop()
    result = {}

    def on_response(conn, sender_name, object_path, iface, signal, params):
        try:
            code, results = params.unpack()
            result["code"] = code
            result["results"] = {k: (v.unpack() if hasattr(v, "unpack") else v) for k, v in results.items()}
        except Exception as exc:  # noqa: BLE001
            result["error"] = str(exc)
        loop.quit()

    bus.signal_subscribe(
        "org.freedesktop.portal.Desktop",
        "org.freedesktop.portal.Request",
        "Response",
        path,
        None,
        Gio.DBusSignalFlags.NONE,
        on_response,
    )

    options = {
        "handle_token": GLib.Variant("s", token),
        "interactive": GLib.Variant("b", True),
        "modal": GLib.Variant("b", True),
    }
    bus.call_sync(
        "org.freedesktop.portal.Desktop",
        "/org/freedesktop/portal/desktop",
        "org.freedesktop.portal.Screenshot",
        "Screenshot",
        GLib.Variant("(sa{sv})", (parent_id, options)),
        GLib.VariantType.new("(o)"),
        Gio.DBusCallFlags.NONE,
        20000,
        None,
    )

    GLib.timeout_add_seconds(timeout, lambda: (result.update(timeout=True), loop.quit(), False)[-1])
    loop.run()

    if parent_win is not None:
        try:
            parent_win.destroy()
        except Exception:  # noqa: BLE001
            pass

    if result.get("timeout"):
        raise RuntimeError("等待用户选区超时")

    code = result.get("code")
    if code in (1, 2):
        raise _Cancelled()
    if code != 0:
        raise RuntimeError(f"portal 截图失败: {result}")

    uri = result.get("results", {}).get("uri")
    if not uri:
        raise _Cancelled()

    src = urllib.parse.unquote(uri.replace("file://", ""))
    with Image.open(src) as img:
        img.load()
        image = img.convert("RGB")
    return image, src


# --------------------------------------------------------------------------
# 兜底：抓全屏 + 自绘选区
# --------------------------------------------------------------------------


class _Cancelled(Exception):
    pass


def capture_fullscreen():
    """非交互抓全屏（portal → gnome-screenshot → X11），用于兜底方案。"""
    errors = []
    # 1) portal 非交互
    try:
        import gi

        gi.require_version("Gtk", "3.0")
        from gi.repository import Gio, GLib

        token = "amdhelper_full_" + uuid.uuid4().hex
        bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
        sender = bus.get_unique_name()[1:].replace(".", "_")
        path = f"/org/freedesktop/portal/desktop/request/{sender}/{token}"
        loop = GLib.MainLoop()
        result = {}

        def on_response(conn, sender_name, object_path, iface, signal, params):
            code, results = params.unpack()
            result["code"] = code
            result["results"] = {k: (v.unpack() if hasattr(v, "unpack") else v) for k, v in results.items()}
            loop.quit()

        bus.signal_subscribe("org.freedesktop.portal.Desktop", "org.freedesktop.portal.Request",
                             "Response", path, None, Gio.DBusSignalFlags.NONE, on_response)
        options = {
            "handle_token": GLib.Variant("s", token),
            "interactive": GLib.Variant("b", False),
            "modal": GLib.Variant("b", False),
        }
        bus.call_sync("org.freedesktop.portal.Desktop", "/org/freedesktop/portal/desktop",
                      "org.freedesktop.portal.Screenshot", "Screenshot",
                      GLib.Variant("(sa{sv})", ("", options)), GLib.VariantType.new("(o)"),
                      Gio.DBusCallFlags.NONE, 15000, None)
        GLib.timeout_add_seconds(15, lambda: (result.update(timeout=True), loop.quit(), False)[-1])
        loop.run()
        uri = result.get("results", {}).get("uri")
        if result.get("code") == 0 and uri:
            src = urllib.parse.unquote(uri.replace("file://", ""))
            with Image.open(src) as img:
                img.load()
                return img.convert("RGB"), [src]
        errors.append(f"portal: {result}")
    except Exception as exc:  # noqa: BLE001
        errors.append(f"portal: {exc}")

    # 2) X11 直接抓
    try:
        import mss

        with mss.mss() as sct:
            shot = sct.grab(sct.monitors[0])
            return Image.frombytes("RGB", shot.size, shot.bgra, "raw", "BGRX"), []
    except Exception as exc:  # noqa: BLE001
        errors.append(f"mss: {exc}")

    raise RuntimeError("抓屏失败 -> " + " | ".join(errors))


def select_region_overlay(image, timeout=180):
    """自绘全屏选区（兜底方案），返回矩形或 None。"""
    import gi

    gi.require_version("Gtk", "3.0")
    gi.require_version("Gdk", "3.0")
    gi.require_version("GdkPixbuf", "2.0")
    from gi.repository import Gdk, GdkPixbuf, GLib, Gtk

    img_w, img_h = image.size
    rgb = image.tobytes()
    pixbuf = GdkPixbuf.Pixbuf.new_from_bytes(
        GLib.Bytes.new(rgb), GdkPixbuf.Colorspace.RGB, False, 8, img_w, img_h, img_w * 3
    )

    state = {"start": None, "sel": None, "result": None, "done": False, "armed": time.monotonic()}
    win = Gtk.Window(type=Gtk.WindowType.TOPLEVEL)
    win.set_decorated(False)
    win.set_keep_above(True)
    win.set_can_focus(True)
    display = Gdk.Display.get_default()
    mon = display.get_primary_monitor() if display else None
    if mon:
        g = mon.get_geometry()
        win.set_default_size(g.width, g.height)

    area = Gtk.DrawingArea()
    area.add_events(
        Gdk.EventMask.BUTTON_PRESS_MASK | Gdk.EventMask.BUTTON_RELEASE_MASK
        | Gdk.EventMask.POINTER_MOTION_MASK | Gdk.EventMask.ENTER_NOTIFY_MASK
    )
    win.add(area)

    def to_img(x, y):
        a = area.get_allocation()
        return x * img_w / float(a.width or 1), y * img_h / float(a.height or 1)

    def rect_now():
        if not state["start"] or not state["sel"]:
            return None
        x0, y0 = state["start"]
        x1, y1 = state["sel"]
        if abs(x1 - x0) < 8 or abs(y1 - y0) < 8:
            return None
        return (min(x0, x1), min(y0, y1), abs(x1 - x0), abs(y1 - y0))

    def draw(widget, cr):
        a = widget.get_allocation()
        if a.width <= 0:
            return False
        cr.save()
        cr.scale(a.width / float(img_w), a.height / float(img_h))
        Gdk.cairo_set_source_pixbuf(cr, pixbuf, 0, 0)
        cr.paint()
        cr.set_source_rgba(0, 0, 0, 0.6)
        cr.rectangle(0, 0, img_w, img_h)
        cr.fill()
        r = rect_now()
        if r:
            x, y, w, h = r
            cr.save()
            cr.rectangle(x, y, w, h)
            cr.clip()
            Gdk.cairo_set_source_pixbuf(cr, pixbuf, 0, 0)
            cr.paint()
            cr.restore()
            cr.set_line_width(max(3, 6 * a.width / float(img_w)))
            cr.set_source_rgb(1, 0.85, 0.15)
            cr.rectangle(x, y, w, h)
            cr.stroke()
        cr.restore()
        cr.save()
        cr.set_source_rgba(0, 0, 0, 0.8)
        cr.rectangle(0, 0, a.width, 78)
        cr.fill()
        cr.set_source_rgb(1, 1, 1)
        cr.select_font_face("Sans", 0, 1)
        cr.set_font_size(30)
        cr.move_to(28, 52)
        cr.show_text("按住鼠标左键圈选要朗读的区域   松开鼠标开始识别   Esc 取消")
        cr.restore()
        return False

    area.connect("draw", draw)

    def finish(rect):
        if state["done"]:
            return
        state["done"] = True
        state["result"] = rect
        win.destroy()

    def on_press(w, e):
        if time.monotonic() - state["armed"] < 0.4:
            return False
        if e.button == 3:
            finish(None)
            return True
        if e.button != 1:
            return False
        p = to_img(e.x, e.y)
        state["start"] = p
        state["sel"] = p
        return True

    def on_motion(w, e):
        if state["start"] is None:
            return False
        x, y = to_img(e.x, e.y)
        state["sel"] = (max(0, min(img_w, x)), max(0, min(img_h, y)))
        w.queue_draw()
        return True

    def on_release(w, e):
        if e.button != 1 or state["start"] is None:
            return False
        x, y = to_img(e.x, e.y)
        state["sel"] = (max(0, min(img_w, x)), max(0, min(img_h, y)))
        r = rect_now()
        finish(r)
        return True

    def on_key(w, e):
        from gi.repository import Gdk as _G

        if e.keyval == _G.KEY_Escape:
            finish(None)
            return True
        if e.keyval in (_G.KEY_Return, _G.KEY_KP_Enter):
            r = rect_now()
            if r:
                finish(r)
            return True
        return False

    area.connect("button-press-event", on_press)
    area.connect("motion-notify-event", on_motion)
    area.connect("button-release-event", on_release)
    win.connect("key-press-event", on_key)
    win.connect("destroy", lambda *_: Gtk.main_quit())

    win.show_all()
    win.present()
    win.connect("map", lambda *_: (win.fullscreen(), win.present(), False)[-1])
    GLib.idle_add(lambda: (win.fullscreen(), False)[-1])
    win.grab_focus()
    area.grab_focus()
    try:
        Gdk.Display.get_default().beep()
    except Exception:  # noqa: BLE001
        pass
    GLib.timeout_add_seconds(timeout, lambda: (finish(None), False)[-1])
    Gtk.main()
    return state["result"]


# --------------------------------------------------------------------------
# main
# --------------------------------------------------------------------------


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", required=True)
    parser.add_argument("--timeout", type=int, default=180)
    parser.add_argument("--full", action="store_true", help="跳过选区，直接整屏")
    parser.add_argument("--no-portal", action="store_true", help="强制使用自绘选区（调试用）")
    args = parser.parse_args()

    cleanup = []

    try:
        if args.full:
            image, cleanup = capture_fullscreen()
        elif args.no_portal:
            image, cleanup = capture_fullscreen()
            rect = select_region_overlay(image, timeout=args.timeout)
            if rect is None:
                print("CANCEL")
                return 2
            left, top, w, h = [int(round(v)) for v in rect]
            image = image.crop((left, top, left + w, top + h))
        else:
            # 主路径：系统原生选区界面
            try:
                image, src = capture_interactive_portal(timeout=args.timeout)
                cleanup = [src]
            except _Cancelled:
                print("CANCEL")
                return 2
            except Exception as exc:  # noqa: BLE001
                _log(f"portal 交互式截图不可用（{exc}），改用自绘选区")
                image, cleanup = capture_fullscreen()
                rect = select_region_overlay(image, timeout=args.timeout)
                if rect is None:
                    print("CANCEL")
                    return 2
                left, top, w, h = [int(round(v)) for v in rect]
                image = image.crop((left, top, left + w, top + h))

        os.makedirs(os.path.dirname(os.path.abspath(args.out)), exist_ok=True)
        image.save(args.out, "PNG")
        print(f"OK {args.out} {image.size[0]}x{image.size[1]}")
        return 0
    except _Cancelled:
        print("CANCEL")
        return 2
    except Exception as exc:  # noqa: BLE001
        _log(f"失败: {exc}")
        import traceback

        traceback.print_exc()
        print(f"ERROR {exc}")
        return 1
    finally:
        for p in cleanup:
            try:
                if p and os.path.exists(p) and os.path.getmtime(p) > time.time() - 180:
                    os.remove(p)
            except OSError:
                pass


if __name__ == "__main__":
    sys.exit(main())
