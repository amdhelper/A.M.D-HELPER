# input_listener.py (v2 with enhanced device detection)
# -*- coding: utf-8 -*-

import sys
import selectors
import evdev
from evdev import ecodes

def find_devices():
    """Find and return the first keyboard and mouse device with more robust logic."""
    keyboard_device, mouse_device = None, None
    devices = [evdev.InputDevice(path) for path in evdev.list_devices()]

    print("--- Detected Input Devices ---", file=sys.stderr, flush=True)
    for device in devices:
        caps = device.capabilities(verbose=False)
        device_info = f"Path: {device.path}, Name: {device.name}"

        # A more reliable check for a keyboard (e.g., has letter keys)
        is_keyboard = (ecodes.EV_KEY in caps and 
                       ecodes.KEY_A in caps[ecodes.EV_KEY] and 
                       ecodes.KEY_Z in caps[ecodes.EV_KEY])

        # A more reliable check for a mouse (has absolute axes AND a primary button)
        is_mouse = (ecodes.EV_ABS in caps and 
                    ecodes.ABS_X in caps[ecodes.EV_ABS] and 
                    ecodes.ABS_Y in caps[ecodes.EV_ABS] and
                    ecodes.EV_KEY in caps and
                    ecodes.BTN_MOUSE in caps[ecodes.EV_KEY])

        print(f"{device_info} -> Is Keyboard? {is_keyboard}, Is Mouse? {is_mouse}", file=sys.stderr, flush=True)

        if not keyboard_device and is_keyboard:
            keyboard_device = device
        
        if not mouse_device and is_mouse:
            mouse_device = device
            
    print("--------------------------", file=sys.stderr, flush=True)
    return keyboard_device, mouse_device

def main():
    keyboard, mouse = find_devices()
    if not keyboard or not mouse:
        print("E Could not find all required devices (keyboard, mouse).", file=sys.stderr, flush=True)
        return 1

    print(f"I Listener started. Keyboard: {keyboard.name}, Mouse: {mouse.name}", file=sys.stderr, flush=True)

    selector = selectors.DefaultSelector()
    selector.register(keyboard, selectors.EVENT_READ)
    selector.register(mouse, selectors.EVENT_READ)

    mouse_x, mouse_y = 0, 0
    
    try:
        while True:
            for key, _ in selector.select():
                device = key.fileobj
                for event in device.read():
                    if device.path == keyboard.path:
                        if event.type == ecodes.EV_KEY and event.code == ecodes.KEY_ESC and event.value == 1:
                            print("K ESC", flush=True)
                            return 0
                    elif device.path == mouse.path:
                        if event.type == ecodes.EV_ABS:
                            if event.code == ecodes.ABS_X:
                                mouse_x = event.value
                            elif event.code == ecodes.ABS_Y:
                                mouse_y = event.value
                        elif event.type == ecodes.EV_SYN and event.code == ecodes.SYN_REPORT:
                            print(f"M {mouse_x} {mouse_y}", flush=True)
    except (KeyboardInterrupt, BrokenPipeError):
        pass
    finally:
        print("I Listener shutting down.", file=sys.stderr, flush=True)
        selector.close()

if __name__ == "__main__":
    sys.exit(main())