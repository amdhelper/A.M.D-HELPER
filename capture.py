#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
A.M.D-HELPER 截图模块（Ubuntu 22.04 ~ 26.04 / X11 + Wayland 通用）

主路径（Wayland/GNOME 必须走这条）：
  1. 用 xdg-desktop-portal 的 **非交互** 截图抓一张真实的全屏画面（约 0.6 秒）；
  2. 自己画一个全屏覆盖层，把这张画面原样显示出来，鼠标变成十字准星；
  3. 用户拖框 → 松开 → 裁切保存 → 交给托盘做 OCR + 朗读。

为什么不再调用 portal 的交互式截图（interactive=true）：
  * Ubuntu 26.04 / GNOME Shell 50 下，普通进程调 interactive 会被拒绝，
    表现为「先出现一个白色小方块（父窗口），十秒后失败」；
  * 失败后旧代码回退到 X11(mss) 抓屏。Wayland 下 XWayland 根窗口是**黑的**，
    覆盖层就把整块黑屏显示给用户 —— 用户等于闭着眼睛框选，必然识别失败。

为什么不再把 mss/gnome-screenshot 当 Wayland 的兜底：
  同上，Wayland 会话里它们拿不到真实画面。宁可直接报错（托盘会用语音说
  「截图失败，请重试」），也不要给用户一个黑屏让他乱框。

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


class _Cancelled(Exception):
    pass


def _log(msg):
    print(f"[capture] {msg}", file=sys.stderr, flush=True)


def _is_wayland():
    return (
        os.environ.get("XDG_SESSION_TYPE", "").lower() == "wayland"
        or bool(os.environ.get("WAYLAND_DISPLAY"))
    )


# --------------------------------------------------------------------------
# 抓全屏
# --------------------------------------------------------------------------


def capture_portal_fullscreen():
    """xdg-desktop-portal 非交互截图，返回 (PIL.Image, [要清理的临时文件])。

    实测：GNOME 50 / Ubuntu 26.04 下不需要 parent_window，也不会弹授权框，
    0.6 秒返回真实画面（含多显示器合成）。portal 会把截图存一份到 ~/图片，
    我们随后删掉，避免每次按 F4 都往用户目录里堆垃圾。
    """
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
        try:
            code, results = params.unpack()
            result["code"] = code
            result["results"] = {
                k: (v.unpack() if hasattr(v, "unpack") else v) for k, v in results.items()
            }
        except Exception as exc:  # noqa: BLE001
            result["error"] = str(exc)
        loop.quit()

    sub_id = bus.signal_subscribe(
        "org.freedesktop.portal.Desktop",
        "org.freedesktop.portal.Request",
        "Response",
        path,
        None,
        Gio.DBusSignalFlags.NONE,
        on_response,
    )

    try:
        options = {
            "handle_token": GLib.Variant("s", token),
            "interactive": GLib.Variant("b", False),
            "modal": GLib.Variant("b", False),
        }
        bus.call_sync(
            "org.freedesktop.portal.Desktop",
            "/org/freedesktop/portal/desktop",
            "org.freedesktop.portal.Screenshot",
            "Screenshot",
            GLib.Variant("(sa{sv})", ("", options)),
            GLib.VariantType.new("(o)"),
            Gio.DBusCallFlags.NONE,
            15000,
            None,
        )
        GLib.timeout_add_seconds(20, lambda: (result.update(timeout=True), loop.quit(), False)[-1])
        loop.run()
    finally:
        try:
            bus.signal_unsubscribe(sub_id)
        except Exception:  # noqa: BLE001
            pass

    if result.get("timeout"):
        raise RuntimeError("portal 截图超时")
    if result.get("error"):
        raise RuntimeError(f"portal 回调异常: {result['error']}")
    if result.get("code") != 0:
        raise RuntimeError(f"portal 截图返回 code={result.get('code')}")

    uri = (result.get("results") or {}).get("uri")
    if not uri:
        raise RuntimeError("portal 没有返回截图路径")

    src = urllib.parse.unquote(uri.replace("file://", ""))
    with Image.open(src) as img:
        img.load()
        image = img.convert("RGB")
    return image, [src]


def capture_gnome_screenshot():
    """gnome-screenshot -f 兜底（Wayland 下它内部也走 portal）。"""
    fd, out_path = tempfile.mkstemp(suffix=".png", prefix="amdhelper_gs_")
    os.close(fd)
    try:
        proc = subprocess.run(
            ["gnome-screenshot", "-f", out_path],
            capture_output=True,
            text=True,
            timeout=25,
            env={**os.environ, "PYTHONNOUSERSITE": "1"},
        )
        if proc.returncode != 0 or not os.path.exists(out_path) or os.path.getsize(out_path) == 0:
            raise RuntimeError(f"gnome-screenshot 失败: {proc.stderr.strip()[:200]}")
        with Image.open(out_path) as img:
            img.load()
            return img.convert("RGB"), [out_path]
    except Exception:
        try:
            os.remove(out_path)
        except OSError:
            pass
        raise


def capture_x11_mss():
    """X11 直接抓屏。**Wayland 会话下拿到的 XWayland 根窗口是黑图，禁止使用。**"""
    import mss

    with mss.mss() as sct:
        shot = sct.grab(sct.monitors[0])
        return Image.frombytes("RGB", shot.size, shot.bgra, "raw", "BGRX"), []


def _looks_blank(image):
    """判断图像是不是纯色/全黑（Wayland 下抓错后端时的典型产物）。"""
    try:
        small = image.convert("L").resize((48, 48))
        data = list(small.getdata())
    except Exception:  # noqa: BLE001
        return False
    if not data:
        return True
    mean = sum(data) / len(data)
    var = sum((v - mean) ** 2 for v in data) / len(data)
    return mean < 8 and var < 6


def capture_screen():
    """按可靠性依次尝试，返回 (PIL.Image, 清理列表)。Wayland 下不允许黑图兜底。"""
    wayland = _is_wayland()
    errors = []

    backends = [("portal", capture_portal_fullscreen)]
    if not wayland:
        backends.append(("x11-mss", capture_x11_mss))
        backends.append(("gnome-screenshot", capture_gnome_screenshot))
    else:
        # Wayland 上 portal 挂掉时，gnome-screenshot 仍可能通过 portal 成功
        backends.append(("gnome-screenshot", capture_gnome_screenshot))

    for name, func in backends:
        try:
            image, cleanup = func()
            if image is None or image.size[0] < 2 or image.size[1] < 2:
                raise RuntimeError("图像尺寸异常")
            if _looks_blank(image):
                raise RuntimeError("抓到的是纯色/黑图（后端拿不到真实画面）")
            _log(f"抓屏成功: {name} {image.size[0]}x{image.size[1]}")
            return image, cleanup
        except Exception as exc:  # noqa: BLE001
            errors.append(f"{name}: {exc}")
            _log(f"{name} 不可用: {exc}")

    raise RuntimeError("抓屏失败 -> " + " | ".join(errors))


# --------------------------------------------------------------------------
# 自绘选区覆盖层（显示真实画面 + 十字准星）
# --------------------------------------------------------------------------

BANNER = "框选要朗读的文字：按住鼠标左键拖动，松开开始识别    Esc 取消    回车=整屏朗读"


def select_region_overlay(image, timeout=180):
    """全屏显示抓到的画面并让用户框选，返回矩形 (x, y, w, h) 或 None。"""
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

    state = {
        "start": None,
        "sel": None,
        "cursor": (0, 0),
        "result": None,
        "done": False,
        "armed": time.monotonic(),
    }

    win = Gtk.Window(type=Gtk.WindowType.TOPLEVEL)
    win.set_decorated(False)
    win.set_keep_above(True)
    win.set_can_focus(True)
    win.set_skip_taskbar_hint(True)
    win.set_skip_pager_hint(True)
    win.set_resizable(True)
    win.set_title("A.M.D-HELPER 框选")

    # 关键：必须先把窗口尺寸设成显示器大小，再 fullscreen。
    # 只调 fullscreen() 而窗口没有尺寸时，GNOME Wayland 下窗口会保持默认的
    # 小尺寸（实测变成屏幕中间一个 300x250 的小方块），根本不是全屏覆盖层。
    display = Gdk.Display.get_default()
    mon_w, mon_h = 1920, 1080
    try:
        mon = display.get_primary_monitor() if display else None
        if mon is None and display is not None:
            mon = display.get_monitor(0)
        if mon is not None:
            g = mon.get_geometry()
            mon_w, mon_h = g.width, g.height
    except Exception:  # noqa: BLE001
        pass
    win.set_default_size(mon_w, mon_h)
    win.resize(mon_w, mon_h)

    area = Gtk.DrawingArea()
    area.add_events(
        Gdk.EventMask.BUTTON_PRESS_MASK
        | Gdk.EventMask.BUTTON_RELEASE_MASK
        | Gdk.EventMask.POINTER_MOTION_MASK
        | Gdk.EventMask.ENTER_NOTIFY_MASK
    )
    win.add(area)

    # 十字准星：让用户一眼（哪怕只剩一点点视力）就知道自己该拖框了
    try:
        cursor = Gdk.Cursor.new_from_name(Gdk.Display.get_default(), "crosshair")
    except Exception:  # noqa: BLE001
        cursor = None

    def to_img(x, y):
        a = area.get_allocation()
        return (
            max(0.0, min(img_w, x * img_w / float(a.width or 1))),
            max(0.0, min(img_h, y * img_h / float(a.height or 1))),
        )

    def rect_now():
        if not state["start"] or not state["sel"]:
            return None
        x0, y0 = state["start"]
        x1, y1 = state["sel"]
        if abs(x1 - x0) < 6 or abs(y1 - y0) < 6:
            return None
        return (min(x0, x1), min(y0, y1), abs(x1 - x0), abs(y1 - y0))

    def draw(widget, cr):
        a = widget.get_allocation()
        if a.width <= 0 or a.height <= 0:
            return False
        if not state.get("logged"):
            state["logged"] = True
            try:
                st = win.get_window().get_state() if win.get_window() else None
            except Exception:  # noqa: BLE001
                st = None
            _log(f"覆盖层绘制: 分配={a.width}x{a.height} 显示器={mon_w}x{mon_h} 图像={img_w}x{img_h} 窗口状态={st}")
        sx = a.width / float(img_w)
        sy = a.height / float(img_h)

        cr.save()
        cr.scale(sx, sy)
        # 1) 原始画面（暗一点，突出选区）
        Gdk.cairo_set_source_pixbuf(cr, pixbuf, 0, 0)
        cr.paint()
        cr.set_source_rgba(0, 0, 0, 0.55)
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

            lw = max(2.0, 4.0 * sx)
            cr.set_line_width(lw)
            cr.set_source_rgb(1.0, 0.85, 0.15)
            cr.rectangle(x, y, w, h)
            cr.stroke()

            # 框选尺寸提示（大字，方便低视力用户）
            cr.set_source_rgba(0, 0, 0, 0.75)
            cr.rectangle(x, max(0, y - 46 * sy), max(240 * sx, w), 46 * sy)
            cr.fill()
            cr.set_source_rgb(1, 1, 1)
            cr.select_font_face("Sans", 0, 1)
            cr.set_font_size(30)
            cr.move_to(x + 12 * sx, max(32 * sy, y - 12 * sy))
            cr.show_text(f"{int(w)} x {int(h)} 像素")
        else:
            # 还没开始拖：跟着鼠标画细十字线，帮助对准文字行
            cx, cy = state["cursor"]
            cr.set_line_width(max(1.0, 1.5 * sx))
            cr.set_source_rgba(1.0, 0.85, 0.15, 0.9)
            cr.move_to(cx, 0)
            cr.line_to(cx, img_h)
            cr.move_to(0, cy)
            cr.line_to(img_w, cy)
            cr.stroke()
        cr.restore()

        # 2) 顶部说明条（屏幕坐标，不随图像缩放）
        cr.save()
        cr.set_source_rgba(0, 0, 0, 0.82)
        cr.rectangle(0, 0, a.width, 64)
        cr.fill()
        cr.set_source_rgb(1, 1, 1)
        cr.select_font_face("Sans", 0, 1)
        cr.set_font_size(26)
        cr.move_to(24, 42)
        cr.show_text(BANNER)
        cr.restore()
        return False

    area.connect("draw", draw)

    def finish(rect):
        if state["done"]:
            return
        state["done"] = True
        state["result"] = rect
        win.destroy()
        Gtk.main_quit()

    def on_realize(widget):
        if cursor is not None:
            try:
                widget.get_window().set_cursor(cursor)
            except Exception:  # noqa: BLE001
                pass

    def on_press(w, e):
        if time.monotonic() - state["armed"] < 0.35:
            return False
        if e.button == 3:
            finish(None)
            return True
        if e.button != 1:
            return False
        p = to_img(e.x, e.y)
        state["start"] = p
        state["sel"] = p
        w.queue_draw()
        return True

    def on_motion(w, e):
        state["cursor"] = to_img(e.x, e.y)
        if state["start"] is not None:
            state["sel"] = state["cursor"]
        w.queue_draw()
        return True

    def on_release(w, e):
        if e.button != 1 or state["start"] is None:
            return False
        state["sel"] = to_img(e.x, e.y)
        r = rect_now()
        if r is None:
            # 只是点了一下没拖动 → 当作用户还没画好，继续等待
            state["start"] = None
            w.queue_draw()
            return True
        try:
            Gdk.Display.get_default().beep()
        except Exception:  # noqa: BLE001
            pass
        finish(r)
        return True

    def on_key(w, e):
        from gi.repository import Gdk as _G

        if e.keyval == _G.KEY_Escape:
            finish(None)
            return True
        if e.keyval in (_G.KEY_Return, _G.KEY_KP_Enter):
            finish(rect_now() or (0, 0, img_w, img_h))
            return True
        return False

    area.connect("realize", on_realize)
    area.connect("button-press-event", on_press)
    area.connect("motion-notify-event", on_motion)
    area.connect("button-release-event", on_release)
    win.connect("key-press-event", on_key)
    win.connect("destroy", lambda *_: Gtk.main_quit())

    win.show_all()
    win.present()
    win.connect("map", lambda *_: (win.fullscreen(), win.present(), False)[-1])
    GLib.idle_add(lambda: (win.fullscreen(), False)[-1])
    # Wayland 下 map 后的第一帧还没拿到最终尺寸，再补一次 fullscreen 兜底
    GLib.timeout_add(150, lambda: (win.fullscreen(), win.present(), False)[-1])
    GLib.timeout_add(120, lambda: (win.grab_focus(), area.grab_focus(), False)[-1])
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
    parser.add_argument("--no-overlay", action="store_true", help="不弹选区覆盖层（调试用）")
    args = parser.parse_args()

    cleanup = []
    try:
        image, cleanup = capture_screen()

        if not args.full and not args.no_overlay:
            rect = select_region_overlay(image, timeout=args.timeout)
            if rect is None:
                print("CANCEL")
                return 2
            left, top, w, h = [int(round(v)) for v in rect]
            w = max(1, min(w, image.size[0] - left))
            h = max(1, min(h, image.size[1] - top))
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
